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
public struct PhotoSaver: Sendable {
    /// Develops HEIF and JPEG from the RAW.
    private let developer: any PhotoDeveloping
    /// Signs files, or `nil` when this build has no signer.
    private let signer: (any PhotoSigning)?
    /// Reads finished files back.
    private let reader: any MetadataReading
    /// Adds files to Photos.
    private let library: any PhotoLibrary

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
    public init(
        developer: any PhotoDeveloping, signer: (any PhotoSigning)?, reader: any MetadataReading,
        library: any PhotoLibrary, appVersion: String
    ) {
        self.developer = developer
        self.signer = signer
        self.reader = reader
        self.library = library
        self.appVersion = appVersion
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
    /// - Returns: What was saved.
    /// - Throws: ``CaptureError/developmentFailed`` if a format can't be developed,
    ///   ``CaptureError/metadataNotAllowed`` if any unsigned file fails the read-back (nothing is
    ///   saved),
    ///   or the library's ``CaptureError/photosAccessDenied`` or ``CaptureError/saveFailed``.
    public func save(_ photo: CapturedPhoto, settings: SaveSettings) async throws(CaptureError) -> SavedPhoto {
        let plan = plan(for: settings.metadata)
        let files = try await buildFiles(for: photo, settings: settings, plan: plan)
        var status = SignatureStatus.signed
        var finished: [PhotoFile] = []
        var metadata: [PhotoFormat: MetadataInventory] = [:]
        for file in files {
            // Fail closed: the unsigned file must pass before anything else happens to it.
            let unsigned = try check(file, signed: false, plan: plan, rawImageData: photo.rawImageData)
            switch await sign(file, isOn: settings.metadata.signsPhotos) {
            case .signed(let signedFile):
                // A signed file is saved only if it passes too; otherwise the unsigned file,
                // which did, is saved instead and the status says so (issue #66).
                if let inventory = try? check(signedFile, signed: true, plan: plan, rawImageData: photo.rawImageData) {
                    finished.append(signedFile)
                    metadata[file.format] = inventory
                    continue
                }
                if status == .signed { status = .unsigned(.signedFileFailedCheck) }
            case .notSigned(let reason):
                if status == .signed { status = .unsigned(reason) }
            }
            finished.append(file)
            metadata[file.format] = unsigned
        }
        try await library.add(PhotoLibraryAsset.assets(for: finished))
        return SavedPhoto(
            formats: finished.map(\.format), isProcessedFallback: !photo.format.isBayerRAW, signature: status,
            metadata: metadata)
    }

    /// Reads a file back and checks it against its allowlist (AGENTS.md, "Fail closed").
    ///
    /// - Parameters:
    ///   - file: The finished file.
    ///   - signed: Whether the file carries a Content Credentials manifest.
    ///   - plan: The metadata plan.
    ///   - rawImageData: The RAW image data the camera returned, which a DNG must still hold.
    /// - Returns: The file's read-back inventory.
    /// - Throws: The reader's error, or ``CaptureError/metadataNotAllowed`` for any violation.
    private func check(
        _ file: PhotoFile, signed: Bool, plan: MetadataPlan, rawImageData: Data?
    ) throws(CaptureError) -> MetadataInventory {
        let readBack = try reader.readBack(file)
        let violations = MetadataVerifier.violations(
            in: readBack, allowlist: plan.allowlist(for: file.format, signed: signed), expectedRawImageData: rawImageData)
        guard violations.isEmpty else { throw .metadataNotAllowed }
        return readBack.file.inventory
    }

    /// Builds the files to save: the DNG and the developed formats for a RAW photo, or the
    /// processed fallback file.
    ///
    /// - Parameters:
    ///   - photo: The captured photo.
    ///   - settings: The selected formats and the developed look.
    ///   - plan: The metadata plan for developed files.
    /// - Returns: The files, RAW first.
    /// - Throws: ``CaptureError/developmentFailed`` from the developer.
    private func buildFiles(
        for photo: CapturedPhoto, settings: SaveSettings, plan: MetadataPlan
    ) async throws(CaptureError) -> [PhotoFile] {
        switch photo.format {
        case .processedFallback(let fallback):
            return [PhotoFile(format: fallback == .heif ? .heif : .jpeg, data: photo.data, isProcessedByDevice: true)]
        case .bayerRAW:
            let raw = PhotoFile(format: .raw, data: photo.data)
            var files = settings.formats.contains(.raw) ? [raw] : []
            for format in [PhotoFormat.heif, .jpeg] where settings.formats.contains(format) {
                files.append(
                    try await developer.develop(raw, to: format, look: settings.developedLook, metadata: plan))
            }
            return files
        }
    }

    /// Signs one file.
    ///
    /// - Parameters:
    ///   - file: The file, which has passed the read-back.
    ///   - isOn: Whether the person has signing on.
    /// - Returns: The signed file, or why there is none: signing is off, unavailable or failed.
    private func sign(_ file: PhotoFile, isOn: Bool) async -> SigningOutcome {
        guard isOn else { return .notSigned(.turnedOff) }
        guard let signer else { return .notSigned(.unavailable) }
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
