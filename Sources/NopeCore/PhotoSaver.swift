import Foundation

/// Turns a captured photo into saved files: develops the selected formats, signs them, reads
/// each one back against its allowlist, and adds only clean files to Photos.
///
/// The order is fixed, and each step is a protocol so the whole pipeline is tested with fakes:
///
/// 1. Build the files. A Bayer RAW photo's DNG already has its metadata built from the
///    allowlist by the capture backend; HEIF and JPEG are developed from it
///    (``PhotoDeveloping``). A lens without RAW gives its processed fallback file.
/// 2. Read each file back (``MetadataReading``) and check it with ``MetadataVerifier``.
///    Any violation rejects the whole photo: nothing is saved (AGENTS.md, "Fail closed").
/// 3. Sign each file (``PhotoSigning``), when signing is on and a signer exists, and check the
///    signed file the same way. A signed file that fails is never saved: the unsigned file,
///    which passed, is saved instead, and the status says it isn't signed
///    (``SignatureStatus/UnsignedReason/signedFileFailedCheck``).
/// 4. Add the files to Photos with add-only access (``PhotoLibrary``), a RAW and its processed
///    file as one asset (``PhotoLibraryAsset/assets(for:)``).
/// 5. Make the last-photo thumbnail (``PhotoThumbnailing``) and the "What's in this photo"
///    details (``PhotoDetails``) from the saved files, in memory.
public struct PhotoSaver: Sendable {
    /// Develops HEIF and JPEG from the RAW.
    private let developer: any PhotoDeveloping
    /// Signs files, or `nil` when this build has no signer.
    private let signer: (any PhotoSigning)?
    /// Reads finished files back.
    private let reader: any MetadataReading
    /// Adds files to Photos.
    private let library: any PhotoLibrary
    /// Makes the last-photo thumbnail, or `nil` for none.
    private let thumbnailer: (any PhotoThumbnailing)?
    /// Reads the monotonic clock, for the timings in the details.
    private let now: @Sendable () -> ContinuousClock.Instant

    /// The app's version, written with its name when ``MetadataItem/appNameAndVersion`` is on.
    public let appVersion: String

    /// Creates a pipeline.
    ///
    /// - Parameters:
    ///   - developer: Develops HEIF and JPEG from the RAW.
    ///   - signer: Signs files, or `nil` to save them unsigned (the status says so).
    ///   - reader: Reads finished files back.
    ///   - library: Adds files to Photos.
    ///   - appVersion: The app's version, such as `0.2.0`.
    ///   - thumbnailer: Makes the last-photo thumbnail, or `nil` for none.
    ///   - now: Reads the clock for the timings. Tests pass a scripted one.
    public init(
        developer: any PhotoDeveloping, signer: (any PhotoSigning)?, reader: any MetadataReading,
        library: any PhotoLibrary, appVersion: String, thumbnailer: (any PhotoThumbnailing)? = nil,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.developer = developer
        self.signer = signer
        self.reader = reader
        self.library = library
        self.appVersion = appVersion
        self.thumbnailer = thumbnailer
        self.now = now
    }

    /// The metadata plan for a set of choices, with this app's version.
    ///
    /// - Parameter settings: The person's metadata choices.
    /// - Returns: The plan.
    public func plan(for settings: MetadataSettings) -> MetadataPlan {
        MetadataPlan(settings: settings, appVersion: appVersion)
    }

    /// Saves one photo.
    ///
    /// Side effects: may show the add-only Photos prompt; adds the photo to Photos.
    ///
    /// - Parameters:
    ///   - photo: The captured photo, with its metadata already built for the plan.
    ///   - settings: The formats and metadata choices.
    ///   - captureDuration: How long the camera took to return the photo, for the details, or
    ///     `nil` when unknown.
    /// - Returns: What was saved, with its thumbnail and details.
    /// - Throws: ``CaptureError/developmentFailed`` if a format can't be developed,
    ///   ``CaptureError/metadataNotAllowed`` if any unsigned file fails the read-back (nothing is
    ///   saved),
    ///   or the library's ``CaptureError/photosAccessDenied`` or ``CaptureError/saveFailed``.
    public func save(
        _ photo: CapturedPhoto, settings: SaveSettings, captureDuration: Duration? = nil
    ) async throws(CaptureError) -> SavedPhoto {
        let plan = plan(for: settings.metadata)
        var timings = SaveTimings(capture: captureDuration)
        let files = try await buildFiles(for: photo, settings: settings, plan: plan, timings: &timings)
        var status = SignatureStatus.signed
        var finished: [PhotoDetails.CheckedFile] = []
        for file in files {
            // Fail closed: the unsigned file must pass before anything else happens to it.
            let unsigned = try check(file, signed: false, plan: plan, rawImageData: photo.rawImageData, timings: &timings)
            switch await sign(file, isOn: settings.metadata.signsPhotos, timings: &timings) {
            case .signed(let signedFile):
                // A signed file is saved only if it passes too; otherwise the unsigned file,
                // which did, is saved instead and the status says so (issue #66).
                if let readBack = try? check(
                    signedFile, signed: true, plan: plan, rawImageData: photo.rawImageData, timings: &timings)
                {
                    finished.append(PhotoDetails.CheckedFile(file: signedFile, readBack: readBack))
                    continue
                }
                if status == .signed { status = .unsigned(.signedFileFailedCheck) }
            case .notSigned(let reason):
                if status == .signed { status = .unsigned(reason) }
            }
            finished.append(PhotoDetails.CheckedFile(file: file, readBack: unsigned))
        }
        let start = now()
        try await library.add(PhotoLibraryAsset.assets(for: finished.map(\.file)))
        timings.save = now() - start
        var metadata: [PhotoFormat: MetadataInventory] = [:]
        for checked in finished { metadata[checked.file.format] = checked.readBack.file.inventory }
        return SavedPhoto(
            formats: finished.map(\.file.format), isProcessedFallback: !photo.format.isBayerRAW, signature: status,
            metadata: metadata, thumbnail: thumbnail(of: finished.map(\.file)),
            details: PhotoDetails.build(
                files: finished, plan: plan, look: settings.developedLook, signature: status, timings: timings))
    }

    /// The last-photo thumbnail, from the file that is quickest to read: the HEIF or JPEG when
    /// there is one, otherwise the DNG.
    ///
    /// - Parameter files: The saved files.
    /// - Returns: The thumbnail, or `nil` without a thumbnailer or when the file can't be read.
    private func thumbnail(of files: [PhotoFile]) -> PhotoThumbnail? {
        guard let thumbnailer else { return nil }
        let source = files.first { $0.format != .raw } ?? files.first
        return source.flatMap(thumbnailer.thumbnail(of:))
    }

    /// Reads a file back and checks it against its allowlist (AGENTS.md, "Fail closed").
    ///
    /// - Parameters:
    ///   - file: The finished file.
    ///   - signed: Whether the file carries a Content Credentials manifest.
    ///   - plan: The metadata plan.
    ///   - rawImageData: The RAW image data the camera returned, which a DNG must still hold.
    ///   - timings: The timings, which get the read-back's time.
    /// - Returns: The file's read-back.
    /// - Throws: The reader's error, or ``CaptureError/metadataNotAllowed`` for any violation.
    private func check(
        _ file: PhotoFile, signed: Bool, plan: MetadataPlan, rawImageData: Data?, timings: inout SaveTimings
    ) throws(CaptureError) -> MetadataReadBack {
        let start = now()
        defer { timings.add(now() - start, to: \.readBack) }
        let readBack = try reader.readBack(file)
        let violations = MetadataVerifier.violations(
            in: readBack, allowlist: plan.allowlist(for: file.format, signed: signed), expectedRawImageData: rawImageData)
        guard violations.isEmpty else { throw .metadataNotAllowed }
        return readBack
    }

    /// Builds the files to save: the DNG and the developed formats for a RAW photo, or the
    /// processed fallback file.
    ///
    /// - Parameters:
    ///   - photo: The captured photo.
    ///   - settings: The selected formats and the developed look.
    ///   - plan: The metadata plan for developed files.
    ///   - timings: The timings, which get the development time.
    /// - Returns: The files, RAW first.
    /// - Throws: ``CaptureError/developmentFailed`` from the developer.
    private func buildFiles(
        for photo: CapturedPhoto, settings: SaveSettings, plan: MetadataPlan, timings: inout SaveTimings
    ) async throws(CaptureError) -> [PhotoFile] {
        switch photo.format {
        case .processedFallback(let fallback):
            return [PhotoFile(format: fallback == .heif ? .heif : .jpeg, data: photo.data, isProcessedByDevice: true)]
        case .bayerRAW:
            let raw = PhotoFile(format: .raw, data: photo.data)
            var files = settings.formats.contains(.raw) ? [raw] : []
            for format in [PhotoFormat.heif, .jpeg] where settings.formats.contains(format) {
                let start = now()
                let developed = try await developer.develop(raw, to: format, look: settings.developedLook, metadata: plan)
                timings.add(now() - start, to: \.develop)
                files.append(developed)
            }
            return files
        }
    }

    /// Signs one file.
    ///
    /// - Parameters:
    ///   - file: The file, which has passed the read-back.
    ///   - isOn: Whether the person has signing on.
    ///   - timings: The timings, which get the signer's time.
    /// - Returns: The signed file, or why there is none: signing is off, unavailable or failed.
    private func sign(_ file: PhotoFile, isOn: Bool, timings: inout SaveTimings) async -> SigningOutcome {
        guard isOn else { return .notSigned(.turnedOff) }
        guard let signer else { return .notSigned(.unavailable) }
        let start = now()
        defer { timings.add(now() - start, to: \.sign) }
        do {
            return .signed(try await signer.sign(file))
        } catch {
            return .notSigned(.failed)
        }
    }

    /// What signing one file gave.
    private enum SigningOutcome {
        /// The signed file, not yet read back.
        case signed(PhotoFile)
        /// No signed file, for this reason.
        case notSigned(SignatureStatus.UnsignedReason)
    }
}
