import Foundation

/// The camera's own state in a settings preset (issue #72): the lens, the manual exposure values,
/// Close-Up, the drive mode, bracketing, the interval series and the astro helper.
///
/// These values belong to ``CameraModel``, not to ``NopeSettings``: the app doesn't remember them
/// between launches (AGENTS.md, "Cognitive": no surprise modes), so a preset keeps them itself.
/// ``CameraModel/cameraSetup`` reads them and ``CameraModel/applyCameraSetup(_:manualControlsOn:)``
/// sets them again through the same intents an interface sends, so every rule of the camera
/// (lens ranges, exposure modes, what a lens supports) still applies.
///
/// Left out on purpose, because they belong to one moment and one scene rather than to a setup:
/// the torch being on (the light always starts off, issue #38), a tapped focus point and the
/// focus and exposure locks, the focus magnifier, clean view while the camera is open (its
/// setting, "Start in Clean View", is in ``NopeSettings``) and the comparison shot.
///
/// The encoding is forward compatible: every value is optional when decoding, and a value that is
/// missing (a preset saved by an earlier version) or not understood (a choice added by a later
/// version) is read as its ``factory`` value.
public struct CameraSetup: Codable, Equatable, Sendable {
    /// A lens, described so that it can be found again: by its identifier on this device, or, on
    /// another device or after the identifiers change, by its kind and magnification.
    public struct LensChoice: Codable, Equatable, Sendable {
        /// The lens's identifier (``Lens/id``).
        public var id: String

        /// The lens's kind, as ``CameraSetup/kindName(_:)`` names it.
        public var kind: String

        /// How much closer the lens sees than the wide camera (``Lens/magnification``), or `nil`.
        public var magnification: Double?

        /// Describes a lens.
        ///
        /// - Parameter lens: The lens.
        public init(_ lens: Lens) {
            id = lens.id
            kind = CameraSetup.kindName(lens.kind)
            magnification = lens.magnification
        }

        /// The lens on a device that matches this choice: the same identifier, or else the lens of
        /// the same kind whose magnification is nearest.
        ///
        /// - Parameter capabilities: The device's lenses.
        /// - Returns: The lens, or `nil` when the device has no lens of this kind.
        public func match(in capabilities: DeviceCapabilities) -> Lens? {
            if let lens = capabilities.lens(withID: id) { return lens }
            let sameKind = capabilities.lenses.filter { CameraSetup.kindName($0.kind) == kind }
            return sameKind.min {
                abs(($0.magnification ?? 1) - (magnification ?? 1)) < abs(($1.magnification ?? 1) - (magnification ?? 1))
            }
        }
    }

    /// The lens, or `nil` for the device's default lens.
    public var lens: LensChoice?

    /// The ISO, or `nil` for Auto.
    public var iso: Double?

    /// The exposure duration in seconds, or `nil` for Auto.
    public var shutter: Double?

    /// The aperture as an f-number, or `nil` for Auto.
    public var aperture: Double?

    /// The relative focus position from 0 to 1, or `nil` for autofocus.
    public var focus: Double?

    /// The white balance, or `nil` for Auto.
    public var whiteBalance: WhiteBalanceValue?

    /// Exposure compensation in EV; 0 is none. It applies in full auto too.
    public var exposureCompensation: Double

    /// How auto exposure measures the scene, as a ``MeteringMode`` raw value.
    public var metering: String

    /// Whether autofocus is limited to near subjects (Close-Up).
    public var nearFocusLimit: Bool

    /// What the shutter does, as ``CameraSetup/driveName(_:)`` names it.
    public var drive: String

    /// The exposure bracket, or `nil` when bracketing is off.
    public var bracket: BracketValue?

    /// The time between interval photos, in seconds.
    public var intervalSeconds: Double

    /// How many photos an interval series takes.
    public var intervalCount: Int

    /// Whether the astro helper is on.
    public var astroIsOn: Bool

    /// How many frames an astro run takes.
    public var astroFrameCount: Int

    /// The delay before an astro run's first frame, in seconds.
    public var astroStartDelay: Int

    /// A white balance, as stored in a preset.
    public struct WhiteBalanceValue: Codable, Equatable, Sendable {
        /// The color temperature, in kelvin.
        public var temperature: Double

        /// The tint.
        public var tint: Double

        /// Copies a white balance.
        ///
        /// - Parameter whiteBalance: The white balance.
        public init(_ whiteBalance: WhiteBalance) {
            temperature = whiteBalance.temperature
            tint = whiteBalance.tint
        }
    }

    /// An exposure bracket, as stored in a preset.
    public struct BracketValue: Codable, Equatable, Sendable {
        /// The number of frames.
        public var frameCount: Int

        /// The step between frames, in EV.
        public var step: Double

        /// The order of the frames. A preset saved before the order existed has none, and reads
        /// as ``BracketOrder/darkestFirst``, the order it was taken in then.
        public var order: BracketOrder

        /// Copies a bracket.
        ///
        /// - Parameter bracket: The bracket.
        public init(_ bracket: BracketSettings) {
            frameCount = bracket.frameCount
            step = bracket.step
            order = bracket.order
        }

        /// Reads a bracket, with ``BracketOrder/darkestFirst`` when the order is missing or
        /// unknown.
        ///
        /// - Parameter decoder: The decoder.
        /// - Throws: A `DecodingError` when the frame count or the step is missing.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            frameCount = try container.decode(Int.self, forKey: .frameCount)
            step = try container.decode(Double.self, forKey: .step)
            order = (try? container.decodeIfPresent(BracketOrder.self, forKey: .order)) ?? .darkestFirst
        }

        /// The bracket these values describe.
        public var settings: BracketSettings {
            BracketSettings(frameCount: frameCount, step: step, order: order)
        }

        /// The stored names of the values.
        enum CodingKeys: String, CodingKey {
            /// ``frameCount``.
            case frameCount
            /// ``step``.
            case step
            /// ``order``.
            case order
        }
    }

    /// The camera as a fresh install opens it: the default lens, full auto, single shots, no
    /// bracket, the standard interval series and the astro helper off.
    public static let factory = CameraSetup()

    /// Creates the ``factory`` setup.
    public init() {
        lens = nil
        iso = nil
        shutter = nil
        aperture = nil
        focus = nil
        whiteBalance = nil
        exposureCompensation = 0
        metering = ManualSettings.automatic.metering.rawValue
        nearFocusLimit = false
        drive = Self.driveName(.single)
        bracket = nil
        intervalSeconds = IntervalSettings.standard.interval
        intervalCount = IntervalSettings.standard.count
        astroIsOn = false
        astroFrameCount = AstroModel.defaultFrameCount
        astroStartDelay = SelfTimerDelay.tenSeconds.seconds
    }

    /// Reads a setup, using the ``factory`` value for anything missing, so a preset saved by an
    /// earlier version still opens.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: A `DecodingError` only when the data isn't a keyed container.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let factory = CameraSetup.factory
        lens = try? container.decodeIfPresent(LensChoice.self, forKey: .lens)
        iso = try? container.decodeIfPresent(Double.self, forKey: .iso)
        shutter = try? container.decodeIfPresent(Double.self, forKey: .shutter)
        aperture = try? container.decodeIfPresent(Double.self, forKey: .aperture)
        focus = try? container.decodeIfPresent(Double.self, forKey: .focus)
        whiteBalance = try? container.decodeIfPresent(WhiteBalanceValue.self, forKey: .whiteBalance)
        exposureCompensation =
            (try? container.decodeIfPresent(Double.self, forKey: .exposureCompensation)) ?? factory.exposureCompensation
        metering = (try? container.decodeIfPresent(String.self, forKey: .metering)) ?? factory.metering
        nearFocusLimit = (try? container.decodeIfPresent(Bool.self, forKey: .nearFocusLimit)) ?? factory.nearFocusLimit
        drive = (try? container.decodeIfPresent(String.self, forKey: .drive)) ?? factory.drive
        bracket = try? container.decodeIfPresent(BracketValue.self, forKey: .bracket)
        intervalSeconds = (try? container.decodeIfPresent(Double.self, forKey: .intervalSeconds)) ?? factory.intervalSeconds
        intervalCount = (try? container.decodeIfPresent(Int.self, forKey: .intervalCount)) ?? factory.intervalCount
        astroIsOn = (try? container.decodeIfPresent(Bool.self, forKey: .astroIsOn)) ?? factory.astroIsOn
        astroFrameCount = (try? container.decodeIfPresent(Int.self, forKey: .astroFrameCount)) ?? factory.astroFrameCount
        astroStartDelay = (try? container.decodeIfPresent(Int.self, forKey: .astroStartDelay)) ?? factory.astroStartDelay
    }

    /// The stored names of the values.
    enum CodingKeys: String, CodingKey {
        /// ``CameraSetup/lens``.
        case lens
        /// ``CameraSetup/iso``.
        case iso
        /// ``CameraSetup/shutter``.
        case shutter
        /// ``CameraSetup/aperture``.
        case aperture
        /// ``CameraSetup/focus``.
        case focus
        /// ``CameraSetup/whiteBalance``.
        case whiteBalance
        /// ``CameraSetup/exposureCompensation``.
        case exposureCompensation
        /// ``CameraSetup/metering``.
        case metering
        /// ``CameraSetup/nearFocusLimit``.
        case nearFocusLimit
        /// ``CameraSetup/drive``.
        case drive
        /// ``CameraSetup/bracket``.
        case bracket
        /// ``CameraSetup/intervalSeconds``.
        case intervalSeconds
        /// ``CameraSetup/intervalCount``.
        case intervalCount
        /// ``CameraSetup/astroIsOn``.
        case astroIsOn
        /// ``CameraSetup/astroFrameCount``.
        case astroFrameCount
        /// ``CameraSetup/astroStartDelay``.
        case astroStartDelay
    }

    /// The stored name of a lens kind.
    ///
    /// - Parameter kind: The kind.
    /// - Returns: `ultraWide`, `wide`, `telephoto` or `front`.
    public static func kindName(_ kind: Lens.Kind) -> String {
        switch kind {
        case .ultraWide: "ultraWide"
        case .wide: "wide"
        case .telephoto: "telephoto"
        case .front: "front"
        }
    }

    /// The stored name of a drive mode.
    ///
    /// - Parameter mode: The drive mode.
    /// - Returns: `single`, `timer3`, `timer10`, `burst` or `interval`.
    public static func driveName(_ mode: DriveMode) -> String {
        switch mode {
        case .single: "single"
        case .timer(let delay): "timer\(delay.seconds)"
        case .burst: "burst"
        case .interval: "interval"
        }
    }

    /// The drive mode a stored name stands for.
    ///
    /// - Parameter name: A name from ``driveName(_:)``.
    /// - Returns: The mode, or ``DriveMode/single`` for a name this version doesn't know.
    public static func driveMode(named name: String) -> DriveMode {
        DriveMode.allCases.first { driveName($0) == name } ?? .single
    }

    /// The manual settings this setup holds: every value except the locks, which belong to one
    /// scene.
    public var manualSettings: ManualSettings {
        ManualSettings(
            iso: iso, shutter: shutter, aperture: aperture, exposureCompensation: exposureCompensation, focus: focus,
            whiteBalance: whiteBalance.map { WhiteBalance(temperature: $0.temperature, tint: $0.tint) },
            metering: MeteringMode(rawValue: metering) ?? ManualSettings.automatic.metering)
    }
}

/// Reading and applying a ``CameraSetup`` (issue #72).
extension CameraModel {
    /// The camera's current setup, for saving in a preset.
    public var cameraSetup: CameraSetup {
        var setup = CameraSetup()
        setup.lens = selectedLens.map(CameraSetup.LensChoice.init)
        let settings = manual.settings
        setup.iso = settings.iso
        setup.shutter = settings.shutter
        setup.aperture = settings.aperture
        setup.focus = settings.focus
        setup.whiteBalance = settings.whiteBalance.map(CameraSetup.WhiteBalanceValue.init)
        setup.exposureCompensation = settings.exposureCompensation
        setup.metering = settings.metering.rawValue
        setup.nearFocusLimit = manual.nearFocusLimit
        setup.drive = CameraSetup.driveName(drive.mode)
        setup.bracket = manual.bracket.map(CameraSetup.BracketValue.init)
        setup.intervalSeconds = manual.interval.interval
        setup.intervalCount = manual.interval.count
        setup.astroIsOn = astro.isOn
        setup.astroFrameCount = astro.frameCount
        setup.astroStartDelay = astro.startDelay.seconds
        return setup
    }

    /// Whether the camera is in the middle of something a preset must not change: a photo being
    /// taken or saved, a countdown, a burst, an interval series, an astro run or the comparison
    /// shot.
    public var isBusyForPresets: Bool {
        drive.isBusy || manual.intervalProgress != nil || astro.isRunning || comparison.isPresented
            || captureStatus == .capturing || captureStatus == .saving
    }

    /// Sets the camera up as a preset describes, through the same intents an interface sends.
    ///
    /// The astro helper is turned off first, then the lens is chosen, manual controls are turned
    /// on or off to match the preset's settings, the values are set, and the astro helper is
    /// turned on last, with the preset's values applied after it. Each value goes through the
    /// camera's rules, so a value the lens can't use is moved into its range or left on Auto.
    ///
    /// Side effects: may switch the lens, which restarts the camera.
    ///
    /// - Parameters:
    ///   - setup: The setup to apply.
    ///   - manualControlsOn: Whether manual controls are on in the preset's settings
    ///     (``NopeSettings/showsManualControls``).
    /// - Returns: What couldn't be applied as saved: ``PresetNotice/cameraNotReady`` when the
    ///   camera isn't on, ``PresetNotice/lensUnavailable`` when the device has no such lens, and
    ///   ``PresetNotice/cameraValuesAdjusted`` when any other value differs from the preset's.
    public func applyCameraSetup(_ setup: CameraSetup, manualControlsOn: Bool) async -> [PresetNotice] {
        guard let capabilities else { return [.cameraNotReady] }
        var notices: [PresetNotice] = []
        await send(.astro(.setOn(false)))
        let target = setup.lens.map { $0.match(in: capabilities) } ?? capabilities.defaultLens
        if let target {
            await send(.selectLens(target.id))
        } else {
            notices.append(.lensUnavailable)
        }
        await send(.manual(.setEnabled(manualControlsOn)))
        await send(.manual(.allAuto))
        await send(.manual(.setInterval(IntervalSettings(interval: setup.intervalSeconds, count: setup.intervalCount))))
        await send(.drive(.setMode(CameraSetup.driveMode(named: setup.drive))))
        await send(.astro(.setFrameCount(setup.astroFrameCount)))
        await send(.astro(.setStartDelay(SelfTimerDelay(rawValue: setup.astroStartDelay) ?? .tenSeconds)))
        if setup.astroIsOn { await send(.astro(.setOn(true))) }
        await applyManualValues(setup)
        var applied = cameraSetup
        // A matching lens on another device, or the default lens for a preset without one, counts
        // as the preset's lens.
        if target?.id != setup.lens?.id { applied.lens = setup.lens }
        if applied != setup { notices.append(.cameraValuesAdjusted) }
        return notices
    }

    /// Sets the manual values, Close-Up and the bracket of a setup. Setting the shutter before
    /// ISO means that on a lens without shutter priority the saved ISO replaces the one the
    /// shutter fixed, as the astro helper does.
    ///
    /// - Parameter setup: The setup.
    private func applyManualValues(_ setup: CameraSetup) async {
        let values = setup.manualSettings
        await send(.manual(.setMetering(values.metering)))
        if let shutter = values.shutter { await send(.manual(.setValue(.shutter, shutter))) }
        if let iso = values.iso { await send(.manual(.setValue(.iso, iso))) }
        if let aperture = values.aperture { await send(.manual(.setValue(.aperture, aperture))) }
        if let focus = values.focus { await send(.manual(.setValue(.focus, focus))) }
        if let whiteBalance = values.whiteBalance {
            await send(.manual(.setValue(.whiteBalance, whiteBalance.temperature)))
            await send(.manual(.setTint(whiteBalance.tint)))
        }
        await send(.auto(.setExposureCompensation(values.exposureCompensation)))
        await send(.auto(.setNearFocusLimit(setup.nearFocusLimit)))
        await send(.manual(.setBracket(setup.bracket?.settings)))
    }
}
