import Foundation

/// Turns a captured photo into saved files: develops the selected formats, signs them, reads
/// each one back against its allowlist, and adds only clean files to Photos.
///
/// The order is fixed, and each step is a protocol so the whole pipeline is tested with fakes:
///
/// 1. Build the files. A Bayer RAW photo's DNG already has its metadata built from the
///    allowlist by the capture backend; HEIF and JPEG are developed from it
///    (``PhotoDeveloping``). A lens without RAW gives its processed fallback file.
/// 2. Sign each file (``PhotoSigning``), when signing is on and a signer exists.
/// 3. Read each file back (``MetadataReading``) and check it with ``MetadataVerifier``.
///    Any violation rejects the whole photo: nothing is saved (AGENTS.md, "Fail closed").
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
    ///   ``CaptureError/metadataNotAllowed`` if any file fails the read-back (nothing is saved),
    ///   or the library's ``CaptureError/photosAccessDenied`` or ``CaptureError/saveFailed``.
    public func save(_ photo: CapturedPhoto, settings: SaveSettings) async throws(CaptureError) -> SavedPhoto {
        let plan = plan(for: settings.metadata)
        let files = try await buildFiles(for: photo, settings: settings, plan: plan)
        let (signed, signature) = await sign(files, isOn: settings.metadata.signsPhotos)
        var metadata: [PhotoFormat: MetadataInventory] = [:]
        for (file, isSigned) in signed {
            let readBack = try reader.readBack(file)
            let allowlist = plan.allowlist(for: file.format, signed: isSigned)
            let violations = MetadataVerifier.violations(
                in: readBack, allowlist: allowlist, expectedRawImageData: photo.rawImageData)
            guard violations.isEmpty else { throw .metadataNotAllowed }
            metadata[file.format] = readBack.file.inventory
        }
        let finished = signed.map(\.file)
        try await library.add(PhotoLibraryAsset.assets(for: finished))
        return SavedPhoto(
            formats: finished.map(\.format), isProcessedFallback: !photo.format.isBayerRAW, signature: signature,
            metadata: metadata)
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
            return [PhotoFile(format: fallback == .heif ? .heif : .jpeg, data: photo.data)]
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

    /// Signs each file, keeping the unsigned file if signing is off, unavailable or fails.
    ///
    /// - Parameters:
    ///   - files: The files.
    ///   - isOn: Whether the person has signing on.
    /// - Returns: Each file with whether it is signed, and the photo's signature status.
    private func sign(_ files: [PhotoFile], isOn: Bool) async -> ([(file: PhotoFile, isSigned: Bool)], SignatureStatus) {
        guard isOn else { return (files.map { ($0, false) }, .unsigned(.turnedOff)) }
        guard let signer else { return (files.map { ($0, false) }, .unsigned(.unavailable)) }
        var result: [(file: PhotoFile, isSigned: Bool)] = []
        var status = SignatureStatus.signed
        for file in files {
            do {
                result.append((try await signer.sign(file), true))
            } catch {
                result.append((file, false))
                status = .unsigned(.failed)
            }
        }
        return (result, status)
    }
}
