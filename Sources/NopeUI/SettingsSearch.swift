import NopeCore
import SwiftUI

/// A stable identifier for each group, page and row of Settings (`docs/design/BUILD-SPEC.md`,
/// 3.10).
///
/// The raw value is the row's accessibility identifier, so UI tests and assistive tools find a
/// row whatever the language. Search uses the identifiers as destinations, the Photo Format
/// sheet's All Photo Settings opens ``photos`` and its Look row opens ``copies``, and the
/// Location warning's explanation opens ``details``. They leave room for links into Settings
/// later (issue 82); in 1.0.0 nothing outside the app can open them (there is no URL scheme).
///
/// A raw value never changes once released: rename a case's Swift name if needed, not its raw
/// value.
public enum SettingsID: String, CaseIterable, Hashable, Sendable {
    // The groups of the Settings list, as section headers.

    /// The Photos group: what each photo is saved as.
    case photos = "settings.photos"
    /// The Privacy group: what each photo says.
    case privacy = "settings.privacy"
    /// The Camera group: how the camera focuses and exposes.
    case camera = "settings.camera"
    /// The Screen group: what the screen shows.
    case screen = "settings.screen"
    /// The More group: Accessibility, Honesty, About.
    case more = "settings.more"

    // The Presets row and its page.

    /// The Presets row and page.
    case presets = "settings.presets"
    /// Factory Defaults, on the Presets page.
    case factoryDefaults = "settings.presets.factoryDefaults"
    /// Save Current Settings, on the Presets page.
    case saveCurrentSettings = "settings.presets.saveCurrent"

    // Photos.

    /// The Formats row and page.
    case formats = "settings.formats"
    /// Paired with RAW, on the Formats page.
    case pairedWithRAW = "settings.formats.pairedWithRAW"
    /// The HEIF and JPEG Copies row and page.
    case copies = "settings.copies"
    /// The Look section of HEIF and JPEG Copies.
    case copiesLook = "settings.copies.look"
    /// HEIF Compression, on HEIF and JPEG Copies.
    case heifCompression = "settings.copies.heifCompression"
    /// HEIF Bit Depth, on HEIF and JPEG Copies.
    case heifBitDepth = "settings.copies.heifBitDepth"
    /// JPEG Compression, on HEIF and JPEG Copies.
    case jpegCompression = "settings.copies.jpegCompression"
    /// Color Space, on HEIF and JPEG Copies.
    case colorSpace = "settings.copies.colorSpace"
    /// Copy Size, on HEIF and JPEG Copies.
    case copySize = "settings.copies.copySize"
    /// Restore Defaults, on HEIF and JPEG Copies.
    case copiesRestoreDefaults = "settings.copies.restoreDefaults"
    /// The Photo Size row and page.
    case photoSize = "settings.photoSize"
    /// The Mirror Front Camera switch.
    case mirrorFrontCamera = "settings.mirrorFrontCamera"

    // Privacy.

    /// The Details in Each Photo row and page.
    case details = "settings.details"
    /// Remove All Optional Details, on Details in Each Photo.
    case detailsRemoveAll = "settings.details.removeAll"
    /// The Location switch, on Details in Each Photo.
    case detailsLocation = "settings.details.location"
    /// Date and Time Taken.
    case detailsDateAndTime = "settings.details.dateAndTime"
    /// Sub-Second Time.
    case detailsSubSecondTime = "settings.details.subSecondTime"
    /// Time Zone.
    case detailsTimeZone = "settings.details.timeZone"
    /// Camera Make and Model.
    case detailsCameraMakeAndModel = "settings.details.cameraMakeAndModel"
    /// Lens Make and Model.
    case detailsLensMakeAndModel = "settings.details.lensMakeAndModel"
    /// Exact Model for RAW Editors.
    case detailsExactCameraModel = "settings.details.exactCameraModel"
    /// Lens Correction Instructions.
    case detailsLensCorrections = "settings.details.lensCorrections"
    /// Exposure Settings.
    case detailsExposureSettings = "settings.details.exposureSettings"
    /// iOS Version.
    case detailsSystemVersion = "settings.details.systemVersion"
    /// Maker Notes.
    case detailsMakerNotes = "settings.details.makerNotes"
    /// App Name and Version.
    case detailsAppNameAndVersion = "settings.details.appNameAndVersion"
    /// Standard File Tags.
    case detailsStandardFileTags = "settings.details.standardFileTags"
    /// The Always Saved section.
    case detailsAlwaysSaved = "settings.details.alwaysSaved"
    /// The Sign Each Photo switch.
    case signEachPhoto = "settings.signEachPhoto"
    /// The Assistant Access row and page (issue #82).
    case assistantAccess = "settings.assistantAccess"
    /// The Assistant Access switch, on its page.
    case assistantAccessSwitch = "settings.assistantAccess.switch"
    /// Ask First, on the Assistant Access page.
    case assistantAsk = "settings.assistantAccess.ask"

    // Camera.

    /// The Fast Shutter row and page.
    case fastShutter = "settings.fastShutter"
    /// The Focus on Faces switch.
    case focusOnFaces = "settings.focusOnFaces"
    /// The Pinch menu (issue #95), on devices with two or more rear lenses.
    case pinch = "settings.pinch"

    // Screen.

    /// The Start in Clean View switch.
    case startInCleanView = "settings.startInCleanView"
    /// The Viewfinder Overlays row and page.
    case overlays = "settings.overlays"
    /// Grid, on Viewfinder Overlays.
    case overlaysGrid = "settings.overlays.grid"
    /// Grid Style, on Viewfinder Overlays (shown while the grid is on).
    case overlaysGridStyle = "settings.overlays.gridStyle"
    /// Level, on Viewfinder Overlays.
    case overlaysLevel = "settings.overlays.level"
    /// Focus Peaking, on Viewfinder Overlays.
    case overlaysFocusPeaking = "settings.overlays.focusPeaking"
    /// Histogram, on Viewfinder Overlays.
    case overlaysHistogram = "settings.overlays.histogram"
    /// Live Camera Readout, on Viewfinder Overlays.
    case overlaysLiveReadout = "settings.overlays.liveReadout"
    /// Keep Readout in Clean View, on Viewfinder Overlays (shown while the readout is on).
    case overlaysKeepReadout = "settings.overlays.keepReadout"
    /// The Show Processed Marker switch.
    case showProcessedMarker = "settings.showProcessedMarker"
    /// The Night Mode switch.
    case nightMode = "settings.nightMode"
    /// The Keep Night Mode After Astro switch.
    case keepNightModeAfterAstro = "settings.keepNightModeAfterAstro"
    /// The Red Viewfinder switch.
    case redViewfinder = "settings.redViewfinder"
    /// The Keep Screen On switch.
    case keepScreenOn = "settings.keepScreenOn"
    /// The Dim After menu (issue #119), under Keep Screen On.
    case dimAfter = "settings.dimAfter"
    /// The Live Activity switch.
    case liveActivity = "settings.liveActivity"

    // More.

    /// The Accessibility row and page.
    case accessibility = "settings.accessibility"
    /// The Honesty row and page.
    case honesty = "settings.honesty"
    /// The entry Lenses Never Switch on Their Own, on the Honesty page, which the camera's
    /// close-up hint opens (docs/design/device-feedback-1.0.md, section 3). Search doesn't list
    /// it: the Honesty row has its keywords.
    case honestyCloseUpFocus = "settings.honesty.closeUpFocus"
    /// The About and Licenses row and page.
    case about = "settings.about"
    /// The License page, under About and Licenses.
    case license = "settings.about.license"
    /// The Notices and Trademarks page, under About and Licenses.
    case noticesAndTrademarks = "settings.about.notices"
    /// The Rate or Review link, last on About and Licenses, shown only once the app has an App
    /// Store ID (`docs/store/STORE-PAGE-PLAN.md`, section 12).
    case rateOrReview = "settings.about.rateOrReview"

    /// The identifier of an optional detail's switch on Details in Each Photo, or `nil` for an
    /// item Settings doesn't offer (`MetadataItem/isOfferedInSettings`).
    ///
    /// - Parameter item: The detail.
    /// - Returns: Its row's identifier.
    static func details(_ item: MetadataItem) -> SettingsID? {
        switch item {
        case .location: .detailsLocation
        case .dateAndTime: .detailsDateAndTime
        case .subSecondTime: .detailsSubSecondTime
        case .timeZone: .detailsTimeZone
        case .cameraMakeAndModel: .detailsCameraMakeAndModel
        case .lensMakeAndModel: .detailsLensMakeAndModel
        case .exactCameraModel: .detailsExactCameraModel
        case .lensCorrections: .detailsLensCorrections
        case .exposureSettings: .detailsExposureSettings
        case .systemVersion: .detailsSystemVersion
        case .makerNotes: .detailsMakerNotes
        case .nameAndCopyright: nil
        case .appNameAndVersion: .detailsAppNameAndVersion
        }
    }

    /// The page this item is on, or `nil` for the Settings list itself.
    var page: SettingsPage? {
        switch self {
        case .photos, .privacy, .camera, .screen, .more, .presets, .formats, .copies, .photoSize, .mirrorFrontCamera,
            .details, .signEachPhoto, .assistantAccess, .fastShutter, .focusOnFaces, .pinch, .startInCleanView,
            .overlays, .showProcessedMarker, .nightMode, .keepNightModeAfterAstro, .redViewfinder, .keepScreenOn,
            .dimAfter, .liveActivity, .accessibility, .honesty, .about:
            nil
        case .assistantAccessSwitch, .assistantAsk: .assistantAccess
        case .honestyCloseUpFocus: .honesty
        case .factoryDefaults, .saveCurrentSettings: .presets
        case .pairedWithRAW: .formats
        case .copiesLook, .heifCompression, .heifBitDepth, .jpegCompression, .colorSpace, .copySize, .copiesRestoreDefaults:
            .copies
        case .detailsRemoveAll, .detailsLocation, .detailsDateAndTime, .detailsSubSecondTime, .detailsTimeZone,
            .detailsCameraMakeAndModel, .detailsLensMakeAndModel, .detailsExactCameraModel, .detailsLensCorrections,
            .detailsExposureSettings, .detailsSystemVersion, .detailsMakerNotes, .detailsAppNameAndVersion,
            .detailsStandardFileTags, .detailsAlwaysSaved:
            .details
        case .overlaysGrid, .overlaysGridStyle, .overlaysLevel, .overlaysFocusPeaking, .overlaysHistogram,
            .overlaysLiveReadout, .overlaysKeepReadout:
            .overlays
        case .license, .noticesAndTrademarks, .rateOrReview: .about
        }
    }

    /// The page this row opens, or `nil` for a switch, a group or a row on a page.
    var opensPage: SettingsPage? {
        SettingsPage(rawValue: rawValue)
    }

    /// The group this item belongs to, or `nil` for Presets, which has none.
    var group: SettingsID? {
        switch self {
        case .photos, .formats, .pairedWithRAW, .copies, .copiesLook, .heifCompression, .heifBitDepth,
            .jpegCompression, .colorSpace, .copySize, .copiesRestoreDefaults, .photoSize, .mirrorFrontCamera:
            .photos
        case .privacy, .details, .detailsRemoveAll, .detailsLocation, .detailsDateAndTime, .detailsSubSecondTime,
            .detailsTimeZone, .detailsCameraMakeAndModel, .detailsLensMakeAndModel, .detailsExactCameraModel,
            .detailsLensCorrections, .detailsExposureSettings, .detailsSystemVersion, .detailsMakerNotes,
            .detailsAppNameAndVersion, .detailsStandardFileTags, .detailsAlwaysSaved, .signEachPhoto, .assistantAccess,
            .assistantAccessSwitch, .assistantAsk:
            .privacy
        case .camera, .fastShutter, .focusOnFaces, .pinch: .camera
        case .screen, .startInCleanView, .overlays, .overlaysGrid, .overlaysGridStyle, .overlaysLevel,
            .overlaysFocusPeaking, .overlaysHistogram, .overlaysLiveReadout, .overlaysKeepReadout,
            .showProcessedMarker, .nightMode, .keepNightModeAfterAstro, .redViewfinder, .keepScreenOn, .dimAfter,
            .liveActivity:
            .screen
        case .more, .accessibility, .honesty, .honestyCloseUpFocus, .about, .license, .noticesAndTrademarks, .rateOrReview:
            .more
        case .presets, .factoryDefaults, .saveCurrentSettings: nil
        }
    }

    /// The pages to push to show this item: its page, or the page it opens; none for a row on
    /// the Settings list.
    var navigationPath: [SettingsPage] {
        if let page { return [page] }
        if let opensPage { return [opensPage] }
        return []
    }

    /// The row to scroll to once the item's page is shown: a group's first row, the item's own
    /// row, or `nil` when the item is a page, which opens at its top.
    var scrollTarget: SettingsID? {
        switch self {
        case .photos: .formats
        case .privacy: .details
        case .camera: .fastShutter
        case .screen: .startInCleanView
        case .more: .accessibility
        default: opensPage == nil ? self : nil
        }
    }
}

/// A page one level below Settings, pushed onto its navigation stack. Its raw value is the
/// identifier of the row that opens it (``SettingsID``).
enum SettingsPage: String, Hashable, CaseIterable {
    /// Presets.
    case presets = "settings.presets"
    /// Formats.
    case formats = "settings.formats"
    /// HEIF and JPEG Copies.
    case copies = "settings.copies"
    /// Photo Size.
    case photoSize = "settings.photoSize"
    /// Details in Each Photo.
    case details = "settings.details"
    /// Assistant Access.
    case assistantAccess = "settings.assistantAccess"
    /// Fast Shutter.
    case fastShutter = "settings.fastShutter"
    /// Viewfinder Overlays.
    case overlays = "settings.overlays"
    /// Accessibility.
    case accessibility = "settings.accessibility"
    /// Honesty.
    case honesty = "settings.honesty"
    /// About and Licenses.
    case about = "settings.about"

    /// The row that opens the page.
    var id: SettingsID {
        // Every page's raw value is a row identifier (tested).
        SettingsID(rawValue: rawValue) ?? .more
    }
}

/// Where Settings is and what it shows: the pushed pages, the search text and the row to scroll
/// to.
///
/// The camera screen keeps one for as long as Settings is open, outside the presentation, so
/// Settings stays on the same page when its presentation changes: from a popover to the night
/// mode sheet on iPad, or across a fold on the iPhone Duo. It is reset when Settings closes, so
/// Settings opens at its list again, as before.
@MainActor @Observable
final class SettingsNavigation {
    /// The pages pushed above the Settings list.
    var path: [SettingsPage] = []

    /// The search text.
    var searchText = ""

    /// The row to scroll to when its page shows, or `nil`.
    var scrollTarget: SettingsID?

    /// The Honesty entry that takes VoiceOver's focus when the Honesty page shows, once, or
    /// `nil`: set when the close-up hint opens Settings at its entry.
    var focusTarget: SettingsID?

    /// Creates a navigation at the Settings list.
    init() {}

    /// Shows an item: pushes its page and asks for its row to be scrolled into view. Ends a
    /// search.
    ///
    /// - Parameter id: The item.
    func open(_ id: SettingsID) {
        searchText = ""
        openSearchResult(id)
        focusTarget = id.page == .honesty ? id : nil
    }

    /// Shows a search result: pushes its page and asks for its row to be scrolled into view.
    /// The search stays, so going back shows the same text and results
    /// (`docs/design/night-search-field.md`, section 3, "Choose a result"). A row on the
    /// Settings list itself has no page to go back from: the search ends, so the list shows,
    /// scrolled to the row.
    ///
    /// - Parameter id: The result's item.
    func openSearchResult(_ id: SettingsID) {
        if id.navigationPath.isEmpty { searchText = "" }
        path = id.navigationPath
        scrollTarget = id.scrollTarget
    }

    /// Returns to the Settings list, with no search.
    func reset() {
        path = []
        searchText = ""
        scrollTarget = nil
        focusTarget = nil
    }
}

/// Opens Settings at an item. Call it like a function with a ``SettingsID``.
struct OpenSettingsAction {
    /// Opens Settings.
    private let handler: @MainActor (SettingsID) -> Void

    /// Creates the action.
    ///
    /// - Parameter handler: Opens Settings at the item, on the main actor.
    init(_ handler: @escaping @MainActor (SettingsID) -> Void) {
        self.handler = handler
    }

    /// Opens Settings at the item.
    ///
    /// - Parameter id: The page or row to show.
    @MainActor func callAsFunction(_ id: SettingsID) {
        handler(id)
    }
}

extension EnvironmentValues {
    /// Opens Settings at an item, or `nil` where Settings can't be opened. The camera screen
    /// sets it; the Photo Format sheet's All Photo Settings and Look rows and the Location
    /// warning's explanation use it, for example `openSettingsAt?(.photos)`.
    @Entry var openSettingsAt: OpenSettingsAction?
}

/// Scrolls a Settings page to the row ``SettingsNavigation/scrollTarget`` names when it shows,
/// once.
struct SettingsScrollTarget: ViewModifier {
    /// The navigation, or `nil` outside Settings.
    let navigation: SettingsNavigation?

    /// The page this is, or `nil` for the Settings list.
    let page: SettingsPage?

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - navigation: The navigation, or `nil`.
    ///   - page: The page, or `nil` for the Settings list.
    init(navigation: SettingsNavigation?, page: SettingsPage?) {
        self.navigation = navigation
        self.page = page
    }

    /// The page, scrolled to its target row.
    ///
    /// - Parameter content: The page's form.
    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { scroll(proxy) }
                .onChange(of: navigation?.scrollTarget) { _, _ in scroll(proxy) }
        }
    }

    /// Scrolls to the target when it is on this page, then clears it.
    ///
    /// - Parameter proxy: The scroll proxy.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let navigation, let target = navigation.scrollTarget, target.page == page else { return }
        navigation.scrollTarget = nil
        // After the push finishes, or the row isn't laid out yet.
        Task { @MainActor in
            // Centered, so the row and its section header are clear of the navigation bar.
            proxy.scrollTo(target, anchor: .center)
        }
    }
}

extension View {
    /// Gives a Settings row its stable identifier: the scroll identity search uses and the
    /// accessibility identifier.
    ///
    /// - Parameter id: The row's identifier.
    func settingsRow(_ id: SettingsID) -> some View {
        self.id(id).accessibilityIdentifier(id.rawValue)
    }

    /// Gives a Settings row that holds a control of its own, such as a menu picker, its stable
    /// identifier on a container element, so the control inside keeps its own element.
    ///
    /// - Parameter id: The row's identifier.
    func settingsContainerRow(_ id: SettingsID) -> some View {
        accessibilityElement(children: .contain).settingsRow(id)
    }
}

/// The names Settings shows and searches, as resources, so a row and its search entry always
/// use the same localized words.
enum SettingsText {
    /// The module's bundle, for the resources.
    static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    // Groups.

    /// "Photos", the group header (its own key: "Photos" alone is a count).
    static let photos = LocalizedStringResource("Settings section: Photos", defaultValue: "Photos", bundle: bundle, comment: "Settings section header for the formats and look each photo is saved with (a heading, not a count).")
    /// "Privacy".
    static let privacy = LocalizedStringResource("Privacy", bundle: bundle, comment: "Settings row and screen title: which details are saved in each photo, and signing.")
    /// "Camera".
    static let camera = LocalizedStringResource("Camera", bundle: bundle, comment: "Settings section header for how the camera screen looks and works. Also the name of the menu with camera commands in the iPad menu bar.")
    /// "Screen".
    static let screen = LocalizedStringResource("Screen", bundle: bundle, comment: "Settings section header above the switches for what the camera screen shows: clean view, overlays, the Processed marker, night mode, Red Viewfinder and the Live Activity.")
    /// "More".
    static let more = LocalizedStringResource("More", bundle: bundle, comment: "Settings section header above Accessibility, Honesty and About.")

    // Rows and pages.

    /// "Presets".
    static let presets = LocalizedStringResource("Settings presets: title", defaultValue: "Presets", bundle: bundle, comment: "Settings row, screen title and camera tray item: named sets of every setting that can be applied at once.")
    /// "Factory Defaults".
    static let factoryDefaults = LocalizedStringResource("Factory Defaults", bundle: bundle, comment: "Built-in settings preset that returns every setting to what a fresh install has.")
    /// "Save Current Settings".
    static let saveCurrentSettings = LocalizedStringResource("Save Current Settings", bundle: bundle, comment: "Link that saves every current setting as a new named preset.")
    /// "Formats".
    static let formats = LocalizedStringResource("Formats", bundle: bundle, comment: "Settings row and screen title: the file formats each photo is saved in.")
    /// "Paired with RAW".
    static let pairedWithRAW = LocalizedStringResource("Paired with RAW", bundle: bundle, comment: "Picker: which processed copy (HEIF or JPEG) Photos keeps together with the RAW. RAW is a file format name.")
    /// "HEIF and JPEG Copies".
    static let copies = LocalizedStringResource("HEIF and JPEG Copies", bundle: bundle, comment: "Settings row and screen title: the look and the file options of the HEIF and JPEG copies developed from the RAW. HEIF and JPEG are file format names.")
    /// "Look".
    static let look = LocalizedStringResource("Look", bundle: bundle, comment: "Settings row and screen title: how the HEIF and JPEG copies are developed from the RAW (Standard or Flat).")
    /// "HEIF Compression".
    static let heifCompression = LocalizedStringResource("HEIF Compression", bundle: bundle, comment: "Picker: how much the HEIF copy is compressed. HEIF is a file format name.")
    /// "HEIF Bit Depth".
    static let heifBitDepth = LocalizedStringResource("HEIF Bit Depth", bundle: bundle, comment: "Picker: bits per color channel of the HEIF copy. HEIF is a file format name.")
    /// "JPEG Compression".
    static let jpegCompression = LocalizedStringResource("JPEG Compression", bundle: bundle, comment: "Picker: how much the JPEG copy is compressed. JPEG is a file format name.")
    /// "Color Space".
    static let colorSpace = LocalizedStringResource("Color Space", bundle: bundle, comment: "Picker: the color space of the HEIF and JPEG copies (Display P3 or sRGB).")
    /// "Copy Size".
    static let copySize = LocalizedStringResource("Copy Size", bundle: bundle, comment: "Picker: the width and height of the HEIF and JPEG copies, compared with the RAW.")
    /// "Restore Defaults".
    static let restoreDefaults = LocalizedStringResource("Restore Defaults", bundle: bundle, comment: "Button that sets every file option back to its default.")
    /// "Photo Size".
    static let photoSize = LocalizedStringResource("Photo Size", bundle: bundle, comment: "Settings row and screen title: the size of photos from lenses that offer more than one.")
    /// "Mirror Front Camera".
    static let mirrorFrontCamera = LocalizedStringResource("Mirror Front Camera", bundle: bundle, comment: "Switch: front camera photos are saved mirrored, as the viewfinder shows them.")
    /// "Details in Each Photo".
    static let details = LocalizedStringResource("Details in Each Photo", table: "Honesty", bundle: bundle, comment: "Settings row and screen title: which optional details, such as the location, date or camera model, are saved in each photo. Replaces Choose Details.")
    /// "Remove All Optional Details".
    static let removeAll = LocalizedStringResource("Remove All Optional Details", table: "Honesty", bundle: bundle, comment: "Master switch: when on, photos keep only the details they need to open.")
    /// "Standard File Tags".
    static let standardFileTags = LocalizedStringResource("Standard File Tags", table: "Honesty", bundle: bundle, comment: "Switch: files carry the fixed tags the photo file standard (Exif) asks for, such as version numbers and the color space.")
    /// "Always Saved".
    static let alwaysSaved = LocalizedStringResource("Always Saved", table: "Honesty", bundle: bundle, comment: "Section header above the details every photo keeps.")
    /// "Sign Each Photo".
    static let signEachPhoto = LocalizedStringResource("Sign Each Photo", table: "Honesty", bundle: bundle, comment: "Switch that adds a Content Credentials signature to each photo.")
    /// "Assistant Access" (issue #82).
    static let assistantAccess = LocalizedStringResource("Assistant Access", table: "Honesty", bundle: bundle, comment: "Settings row, page title and switch: whether Siri, Shortcuts and other assistants can use nope.'s actions. A name in nope.'s Settings.")
    /// "Ask First", on the Assistant Access page.
    static let askFirst = LocalizedStringResource("Ask First", table: "Honesty", bundle: bundle, comment: "Section header and setting on nope.'s Assistant Access page: when nope. asks before an assistant's action runs. A name in nope.'s Settings.")
    /// "Fast Shutter".
    static let fastShutter = LocalizedStringResource("Fast Shutter", bundle: bundle, comment: "Setting and quick control: how fast a shutter full auto prefers, to avoid blur.")
    /// "Focus on Faces".
    static let focusOnFaces = LocalizedStringResource("Focus on Faces", bundle: bundle, comment: "Switch: autofocus and auto exposure follow faces the camera finds. Replaces Face Detection; also the name of the Shortcuts action Set Focus on Faces.")
    /// "Pinch".
    static let pinch = LocalizedStringResource("Pinch", bundle: bundle, comment: "Setting in Settings › Camera: what a pinch on the camera picture does (Switch Lenses or Off). The gesture of two fingers moving apart or together; not zoom.")
    /// "Start in Clean View".
    static let startInCleanView = LocalizedStringResource("Start in Clean View", bundle: bundle, comment: "Switch: the camera opens with only the viewfinder and the shutter.")
    /// "Viewfinder Overlays".
    static let overlays = LocalizedStringResource("Viewfinder Overlays", bundle: bundle, comment: "Settings row and screen title: the grid, level, focus peaking, histogram and live readout drawn over the viewfinder.")
    /// "Grid".
    static let grid = LocalizedStringResource("Grid", bundle: bundle, comment: "Name of the switch and quick control that draws guide lines over the viewfinder.")
    /// "Grid Style".
    static let gridStyle = LocalizedStringResource("Grid Style", bundle: bundle, comment: "Picker for which guide lines the grid draws.")
    /// "Level".
    static let level = LocalizedStringResource("Level", bundle: bundle, comment: "Name of the horizon level shown over the viewfinder, and of its switch.")
    /// "Focus Peaking".
    static let focusPeaking = LocalizedStringResource("Focus Peaking", bundle: bundle, comment: "Name of the switch that highlights in-focus edges over the viewfinder.")
    /// "Histogram".
    static let histogram = LocalizedStringResource("Histogram", bundle: bundle, comment: "Name of the live brightness histogram shown with the manual controls, and of its switch.")
    /// "Live Camera Readout".
    static let liveReadout = LocalizedStringResource("Live Camera Readout", bundle: bundle, comment: "Name of the optional overlay that lists the camera's live technical values (shutter, ISO, focus, white balance, and so on), and of its switch.")
    /// "Keep Readout in Clean View".
    static let keepReadout = LocalizedStringResource("Keep Readout in Clean View", bundle: bundle, comment: "Switch, and choice in the quick-controls tray: the live camera readout stays on screen when clean view hides the other controls.")
    /// "Show Processed Marker".
    static let showProcessedMarker = LocalizedStringResource("Show Processed Marker", bundle: bundle, comment: "Switch and its Voice Control name: shows the Processed marker on the camera before taking a photo with a lens that can't save RAW.")
    /// "Night Mode".
    static let nightMode = LocalizedStringResource("Night Mode", bundle: bundle, comment: "Switch and its Voice Control name: shows nope.'s screens in red on black for working in the dark. Keep \"nope.\" unchanged.")
    /// "Keep Night Mode After Astro".
    static let keepNightModeAfterAstro = LocalizedStringResource("Keep Night Mode After Astro", bundle: bundle, comment: "Switch and its Voice Control name: night mode stays on after leaving Astro, the night sky drive mode, instead of going back off. Night Mode and Astro are names of nope.'s features; use their translations.")
    /// "Red Viewfinder".
    static let redViewfinder = LocalizedStringResource("Red Viewfinder", bundle: bundle, comment: "Switch: in night mode, the live camera picture on screen is shown in red too.")
    /// "Keep Screen On".
    static let keepScreenOn = LocalizedStringResource("Keep Screen On", bundle: bundle, comment: "Switch and its Voice Control name: while the camera is showing, the screen doesn't lock by itself for up to 30 minutes after the last touch or photo. Draft wording for the Honesty review.")
    /// "Dim After" (issue #119).
    static let dimAfter = LocalizedStringResource("Dim After", bundle: bundle, comment: "Menu in Settings › Screen, under Keep Screen On, and its Voice Control name: how long the screen waits without a touch or photo before it dims (1, 2 or 5 minutes, or Never). Draft wording for the Honesty review (issue #119).")
    /// "Live Activity".
    static let liveActivity = LocalizedStringResource("Live Activity", bundle: bundle, comment: "Switch and its Voice Control name: shows interval shooting, astro frames, a burst or the self-timer on the Lock Screen and in the Dynamic Island. Live Activity is the name of the iOS feature: use its name in the language's iOS.")
    /// "Accessibility".
    static let accessibility = LocalizedStringResource("Accessibility", bundle: bundle, comment: "Settings row and screen title: taking photos without looking at the screen (hardware buttons, haptics, spoken feedback).")
    /// "Honesty".
    static let honesty = LocalizedStringResource("Honesty", table: "Honesty", bundle: bundle, comment: "Settings row and screen title: what nope. does and doesn't do, and what it can't control.")
    /// "Lenses Never Switch on Their Own": the Honesty entry on close-up focus, its heading and
    /// its name in Settings (docs/design/device-feedback-1.0.md, section 3).
    static let honestyCloseUpFocus = LocalizedStringResource(
        "Lenses Never Switch on Their Own", table: "Honesty", bundle: bundle,
        comment: "Honesty heading: the app never changes lenses by itself, not even for a close-up. Draft for the Honesty review.")
    /// "About and Licenses".
    static let about = LocalizedStringResource("About and Licenses", bundle: bundle, comment: "Settings row and screen title: version, license and third-party notices.")
    /// "License".
    static let license = LocalizedStringResource("License", bundle: bundle, comment: "Title of the screen showing the full license text.")
    /// "Notices and Trademarks".
    static let noticesAndTrademarks = LocalizedStringResource("Notices and Trademarks", bundle: bundle, comment: "Row and screen title for the copyright, trademark and third-party notices.")
    /// "Rate or Review".
    static let rateOrReview = LocalizedStringResource("Rate or Review", bundle: bundle, comment: "Link on the About screen that opens the App Store's page for writing a rating or review of the app. A label, not a request: it names what the page offers.")

    /// An item's name, as its row shows it.
    ///
    /// - Parameter id: The item.
    /// - Returns: The localized name.
    static func title(of id: SettingsID) -> LocalizedStringResource {
        switch id {
        case .photos: photos
        case .privacy: privacy
        case .camera: camera
        case .screen: screen
        case .more: more
        case .presets: presets
        case .factoryDefaults: factoryDefaults
        case .saveCurrentSettings: saveCurrentSettings
        case .formats: formats
        case .pairedWithRAW: pairedWithRAW
        case .copies: copies
        case .copiesLook: look
        case .heifCompression: heifCompression
        case .heifBitDepth: heifBitDepth
        case .jpegCompression: jpegCompression
        case .colorSpace: colorSpace
        case .copySize: copySize
        case .copiesRestoreDefaults: restoreDefaults
        case .photoSize: photoSize
        case .mirrorFrontCamera: mirrorFrontCamera
        case .details: details
        case .detailsRemoveAll: removeAll
        case .detailsLocation: PrivacySettingsView.title(of: .location)
        case .detailsDateAndTime: PrivacySettingsView.title(of: .dateAndTime)
        case .detailsSubSecondTime: PrivacySettingsView.title(of: .subSecondTime)
        case .detailsTimeZone: PrivacySettingsView.title(of: .timeZone)
        case .detailsCameraMakeAndModel: PrivacySettingsView.title(of: .cameraMakeAndModel)
        case .detailsLensMakeAndModel: PrivacySettingsView.title(of: .lensMakeAndModel)
        case .detailsExactCameraModel: PrivacySettingsView.title(of: .exactCameraModel)
        case .detailsLensCorrections: PrivacySettingsView.title(of: .lensCorrections)
        case .detailsExposureSettings: PrivacySettingsView.title(of: .exposureSettings)
        case .detailsSystemVersion: PrivacySettingsView.title(of: .systemVersion)
        case .detailsMakerNotes: PrivacySettingsView.title(of: .makerNotes)
        case .detailsAppNameAndVersion: PrivacySettingsView.title(of: .appNameAndVersion)
        case .detailsStandardFileTags: standardFileTags
        case .detailsAlwaysSaved: alwaysSaved
        case .signEachPhoto: signEachPhoto
        case .assistantAccess, .assistantAccessSwitch: assistantAccess
        case .assistantAsk: askFirst
        case .fastShutter: fastShutter
        case .focusOnFaces: focusOnFaces
        case .pinch: pinch
        case .startInCleanView: startInCleanView
        case .overlays: overlays
        case .overlaysGrid: grid
        case .overlaysGridStyle: gridStyle
        case .overlaysLevel: level
        case .overlaysFocusPeaking: focusPeaking
        case .overlaysHistogram: histogram
        case .overlaysLiveReadout: liveReadout
        case .overlaysKeepReadout: keepReadout
        case .showProcessedMarker: showProcessedMarker
        case .nightMode: nightMode
        case .keepNightModeAfterAstro: keepNightModeAfterAstro
        case .redViewfinder: redViewfinder
        case .keepScreenOn: keepScreenOn
        case .dimAfter: dimAfter
        case .liveActivity: liveActivity
        case .accessibility: accessibility
        case .honesty: honesty
        case .honestyCloseUpFocus: honestyCloseUpFocus
        case .about: about
        case .license: license
        case .noticesAndTrademarks: noticesAndTrademarks
        case .rateOrReview: rateOrReview
        }
    }

    /// Other words people use for an item, as one localized list separated by commas, or `nil`.
    /// Not shown on screen; translators list the words people use in their language.
    ///
    /// - Parameter id: The item.
    /// - Returns: The keywords, or `nil` when the item has none beyond its name.
    static func keywords(of id: SettingsID) -> LocalizedStringResource? {
        switch id {
        case .presets, .factoryDefaults:
            LocalizedStringResource("Search keywords: Presets", defaultValue: "reset, restore, defaults, factory", bundle: bundle, comment: "Settings search keywords for Presets and Factory Defaults, separated by commas. Not shown on screen: list the words people in your language would type to find where every setting is reset.")
        case .copiesRestoreDefaults:
            LocalizedStringResource("Search keywords: Restore Defaults", defaultValue: "reset, restore, defaults", bundle: bundle, comment: "Settings search keywords for Restore Defaults on HEIF and JPEG Copies, separated by commas. Not shown on screen.")
        case .formats:
            LocalizedStringResource("Search keywords: Formats", defaultValue: "RAW, DNG, HEIF, HEIC, JPEG, file type", bundle: bundle, comment: "Settings search keywords for Formats, separated by commas. Not shown on screen. RAW, DNG, HEIF, HEIC and JPEG are file format names.")
        case .copies:
            LocalizedStringResource("Search keywords: HEIF and JPEG Copies", defaultValue: "quality, compression, resize, look, JPG", bundle: bundle, comment: "Settings search keywords for HEIF and JPEG Copies, separated by commas. Not shown on screen.")
        case .copySize:
            LocalizedStringResource("Search keywords: Copy Size", defaultValue: "resize, resolution, smaller", bundle: bundle, comment: "Settings search keywords for Copy Size, separated by commas. Not shown on screen.")
        case .heifCompression, .jpegCompression:
            LocalizedStringResource("Search keywords: Compression", defaultValue: "quality, file size", bundle: bundle, comment: "Settings search keywords for HEIF Compression and JPEG Compression, separated by commas. Not shown on screen.")
        case .photoSize:
            LocalizedStringResource("Search keywords: Photo Size", defaultValue: "resolution, megapixels, MP", bundle: bundle, comment: "Settings search keywords for Photo Size, separated by commas. Not shown on screen.")
        case .mirrorFrontCamera:
            LocalizedStringResource("Search keywords: Mirror Front Camera", defaultValue: "selfie, flip", bundle: bundle, comment: "Settings search keywords for Mirror Front Camera, separated by commas. Not shown on screen.")
        case .details:
            LocalizedStringResource("Search keywords: Details in Each Photo", defaultValue: "metadata, EXIF, GPS, privacy", bundle: bundle, comment: "Settings search keywords for Details in Each Photo, separated by commas. Not shown on screen. EXIF and GPS are standard names.")
        case .detailsLocation:
            LocalizedStringResource("Search keywords: Location", defaultValue: "GPS, place, geotag, metadata", bundle: bundle, comment: "Settings search keywords for the Location switch, separated by commas. Not shown on screen. GPS is a standard name.")
        case .detailsRemoveAll:
            LocalizedStringResource("Search keywords: Remove All Optional Details", defaultValue: "metadata, EXIF, strip", bundle: bundle, comment: "Settings search keywords for Remove All Optional Details, separated by commas. Not shown on screen.")
        case .signEachPhoto:
            LocalizedStringResource("Search keywords: Sign Each Photo", defaultValue: "Content Credentials, C2PA, signature", bundle: bundle, comment: "Settings search keywords for Sign Each Photo, separated by commas. Not shown on screen. Content Credentials and C2PA are names; keep them unchanged.")
        case .assistantAccess, .assistantAccessSwitch, .assistantAsk:
            LocalizedStringResource("Search keywords: Assistant Access", defaultValue: "siri, shortcuts, assistant, voice, automation, AI, intelligence, ask, confirm", bundle: bundle, comment: "Settings search keywords for Assistant Access, separated by commas. Not shown on screen. Siri and Shortcuts are Apple's names.")
        case .fastShutter:
            LocalizedStringResource("Search keywords: Fast Shutter", defaultValue: "blur, motion, freeze, action, sports", bundle: bundle, comment: "Settings search keywords for Fast Shutter, separated by commas. Not shown on screen.")
        case .focusOnFaces:
            LocalizedStringResource("Search keywords: Focus on Faces", defaultValue: "face detection, people, portrait", bundle: bundle, comment: "Settings search keywords for Focus on Faces, separated by commas. Not shown on screen.")
        case .pinch:
            LocalizedStringResource("Search keywords: Pinch", defaultValue: "zoom, lens, lenses, gesture, two fingers", bundle: bundle, comment: "Settings search keywords for the Pinch setting, separated by commas. Not shown on screen. Zoom is listed so people who look for it find the setting and read that nope. has no zoom; keep a word for zoom.")
        case .nightMode, .redViewfinder:
            LocalizedStringResource("Search keywords: Night Mode", defaultValue: "red, dark", bundle: bundle, comment: "Settings search keywords for Night Mode and Red Viewfinder, separated by commas. Not shown on screen.")
        case .keepNightModeAfterAstro:
            LocalizedStringResource("Search keywords: Keep Night Mode After Astro", defaultValue: "red, dark, night sky, stars", bundle: bundle, comment: "Settings search keywords for Keep Night Mode After Astro, separated by commas. Not shown on screen.")
        case .startInCleanView:
            LocalizedStringResource("Search keywords: Start in Clean View", defaultValue: "hide controls, minimal", bundle: bundle, comment: "Settings search keywords for Start in Clean View, separated by commas. Not shown on screen.")
        case .keepScreenOn:
            LocalizedStringResource("Search keywords: Keep Screen On", defaultValue: "awake, auto-lock, sleep, lock, dim, tripod, battery", bundle: bundle, comment: "Settings search keywords for Keep Screen On, separated by commas. Not shown on screen: list the words people in your language would type to keep the screen from locking or sleeping. Auto-Lock is the name of the iOS setting: use its name in the language's iOS.")
        case .dimAfter:
            LocalizedStringResource("Search keywords: Dim After", defaultValue: "dim, brightness, bright, never, battery, heat, warm", bundle: bundle, comment: "Settings search keywords for Dim After, separated by commas. Not shown on screen: list the words people in your language would type to stop the screen from dimming, or to find what it costs in battery and heat.")
        case .liveActivity:
            LocalizedStringResource("Search keywords: Live Activity", defaultValue: "Lock Screen, Dynamic Island", bundle: bundle, comment: "Settings search keywords for Live Activity, separated by commas. Not shown on screen. Lock Screen and Dynamic Island are iOS names: use the names iOS shows in this language.")
        case .honesty:
            LocalizedStringResource("Search keywords: Honesty", defaultValue: "close-up, macro, close, near, blurry, soft, lens", bundle: bundle, comment: "Settings search keywords for the Honesty page, separated by commas. Not shown on screen: the page explains why nope. never changes lenses for a close-up. Keep nope. unchanged if it appears.")
        case .rateOrReview:
            LocalizedStringResource("Search keywords: Rate or Review", defaultValue: "rate, review, rating, feedback, App Store", bundle: bundle, comment: "Settings search keywords for the Rate or Review link on the About screen, separated by commas. Not shown on screen. App Store is Apple's name: use its name in the language's iOS.")
        case .showProcessedMarker:
            LocalizedStringResource("Search keywords: Show Processed Marker", defaultValue: "no RAW, processing", bundle: bundle, comment: "Settings search keywords for Show Processed Marker, separated by commas. Not shown on screen. RAW is a file format name.")
        default:
            nil
        }
    }

    /// "Settings", where the Presets row is, which has no group.
    static var settingsList: String {
        String(localized: "Settings", bundle: .module, comment: "Title of the settings screen, and the camera button that opens it.")
    }

    /// A page path in search results: a group, then a page, as one whole localized format.
    ///
    /// - Parameters:
    ///   - group: The group's name.
    ///   - page: The page's name.
    /// - Returns: For example "Privacy › Details in Each Photo".
    static func path(_ group: String, _ page: String) -> String {
        String(localized: "\(group) › \(page)", bundle: .module, comment: "Settings search result: where a setting is, a group name, then a page name. Keep the order and separator that read naturally in the language.")
    }

    /// What VoiceOver reads for a search result: the setting, then where it is.
    ///
    /// - Parameters:
    ///   - title: The setting's name.
    ///   - place: Where it is, from ``spokenPath(_:_:)`` or a group name.
    /// - Returns: For example "Location, in Privacy, Details in Each Photo".
    static func spokenResult(_ title: String, _ place: String) -> String {
        String(localized: "\(title), in \(place)", bundle: .module, comment: "VoiceOver: a Settings search result, the setting's name, then where it is.")
    }

    /// A page path as VoiceOver reads it, without the separator symbol.
    ///
    /// - Parameters:
    ///   - group: The group's name.
    ///   - page: The page's name.
    /// - Returns: For example "Privacy, Details in Each Photo".
    static func spokenPath(_ group: String, _ page: String) -> String {
        // The same two-item format as the Viewfinder Overlays row's value ("Grid, Level").
        String(localized: "\(group), \(page)", bundle: .module, comment: "Two names joined, as a list of two: the two overlays that are on (the Viewfinder Overlays row's value, such as Grid, Level), and where a Settings search result is (a group, then a page) as VoiceOver reads it.")
    }
}

/// A control on the camera that isn't in Settings, which search answers with where it is
/// (`docs/design/SETTINGS-PLAN.md`, 3.6).
struct CameraPointer: Identifiable, Equatable {
    /// Where a control is on the camera, in words.
    enum Place: Equatable {
        /// The Manual Controls button, beside the lenses.
        case besideLenses
        /// The drive strip, above the shutter.
        case aboveShutter
        /// A tile of Q.
        case inQ

        /// The place, as one whole sentence.
        var text: LocalizedStringResource {
            switch self {
            case .besideLenses:
                LocalizedStringResource("On the camera, beside the lenses", bundle: SettingsText.bundle, comment: "Settings search: where a camera control is. The Manual Controls button sits beside the lens buttons.")
            case .aboveShutter:
                LocalizedStringResource("On the camera, above the shutter", bundle: SettingsText.bundle, comment: "Settings search: where a camera control is. The drive modes (Timer, Burst, Interval, Astro) are in a row above the shutter.")
            case .inQ:
                LocalizedStringResource("In Q", bundle: SettingsText.bundle, comment: "Settings search: the control is a tile of the Q panel on the camera, opened with the Q button. Keep the letter Q.")
            }
        }
    }

    /// A stable identifier.
    let id: String

    /// The control's name, the one the camera shows.
    let title: LocalizedStringResource

    /// Other words for it, separated by commas, or `nil`.
    let keywords: LocalizedStringResource?

    /// Where it is.
    let place: Place

    /// Creates a pointer.
    ///
    /// - Parameters:
    ///   - id: A stable identifier.
    ///   - title: The control's name, the one the camera shows.
    ///   - keywords: Other words for it, separated by commas, or `nil`.
    ///   - place: Where it is.
    init(id: String, title: LocalizedStringResource, keywords: LocalizedStringResource?, place: Place) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.place = place
    }

    /// Equal when the identifiers are.
    ///
    /// - Parameters:
    ///   - lhs: A pointer.
    ///   - rhs: Another pointer.
    static func == (lhs: CameraPointer, rhs: CameraPointer) -> Bool {
        lhs.id == rhs.id
    }

    /// Every pointer, in the order results list them.
    static let all: [CameraPointer] = {
        let bundle = SettingsText.bundle
        return [
            CameraPointer(
                id: "manualControls",
                title: LocalizedStringResource("Manual Controls", bundle: bundle, comment: "Switch that shows manual exposure controls on the camera screen."),
                keywords: LocalizedStringResource("Search keywords: Manual Controls", defaultValue: "manual, ISO, shutter speed, white balance, focus, exposure", bundle: bundle, comment: "Settings search keywords for the camera's Manual Controls button, separated by commas. Not shown on screen."),
                place: .besideLenses),
            CameraPointer(
                id: "selfTimer",
                title: LocalizedStringResource("Self-Timer", bundle: bundle, comment: "VoiceOver and Voice Control name of the pill on the camera that shows the self-timer is on."),
                keywords: LocalizedStringResource("Search keywords: Self-Timer", defaultValue: "timer, delay, countdown, shutter", bundle: bundle, comment: "Settings search keywords for the camera's self-timer, separated by commas. Not shown on screen."),
                place: .aboveShutter),
            CameraPointer(
                id: "burst",
                title: LocalizedStringResource("Burst", bundle: bundle, comment: "Drive menu option on the camera: holding the shutter takes a rapid run of separate photos."),
                keywords: LocalizedStringResource("Search keywords: Burst", defaultValue: "continuous, speed", bundle: bundle, comment: "Settings search keywords for the camera's burst, separated by commas. Not shown on screen: holding the shutter takes photos continuously, at a speed chosen from the Burst word."),
                place: .aboveShutter),
            CameraPointer(
                id: "interval",
                title: LocalizedStringResource("Interval Shooting", bundle: bundle, comment: "Section title: a series of photos taken at a fixed interval."),
                keywords: LocalizedStringResource("Search keywords: Interval Shooting", defaultValue: "time-lapse, intervalometer, series", bundle: bundle, comment: "Settings search keywords for the camera's interval shooting, separated by commas. Not shown on screen."),
                place: .aboveShutter),
            CameraPointer(
                id: "astro",
                title: LocalizedStringResource("Astro", bundle: bundle, comment: "Quick control, pill and its Voice Control name on the camera: the helper for night sky photos, which takes a series of single RAW frames for stacking in other software."),
                keywords: LocalizedStringResource("Search keywords: Astro", defaultValue: "stars, night sky, stacking", bundle: bundle, comment: "Settings search keywords for the camera's Astro mode, separated by commas. Not shown on screen."),
                place: .aboveShutter),
            CameraPointer(
                id: "flash",
                title: LocalizedStringResource("Flash", bundle: bundle, comment: "Camera menu and its Voice Control name: when the flash fires (Off, Auto, On)."),
                keywords: nil, place: .inQ),
            CameraPointer(
                id: "light",
                title: LocalizedStringResource("Light", bundle: bundle, comment: "Camera switch and its Voice Control name: turns on the phone's light (torch) and keeps it on while taking photos."),
                keywords: LocalizedStringResource("Search keywords: Light", defaultValue: "torch, flashlight", bundle: bundle, comment: "Settings search keywords for the camera's Light, separated by commas. Not shown on screen."),
                place: .inQ),
            CameraPointer(
                id: "exposure",
                title: LocalizedStringResource("Exposure", bundle: bundle, comment: "Name of the exposure compensation control in full auto, in the quick-controls tray and on its dial."),
                keywords: LocalizedStringResource("Search keywords: Exposure", defaultValue: "brightness, compensation, EV", bundle: bundle, comment: "Settings search keywords for the camera's exposure compensation, separated by commas. Not shown on screen."),
                place: .inQ),
            CameraPointer(
                id: "closeUp",
                title: LocalizedStringResource("Close-Up", bundle: bundle, comment: "Quick control and pill on the camera: limits autofocus to near subjects, for small things close to the lens."),
                keywords: LocalizedStringResource("Search keywords: Close-Up", defaultValue: "macro, near", bundle: bundle, comment: "Settings search keywords for the camera's Close-Up control, separated by commas. Not shown on screen."),
                place: .inQ),
            CameraPointer(
                id: "farFocus",
                title: LocalizedStringResource("Far Focus", bundle: bundle, comment: "Quick control and pill on the camera: limits autofocus to far subjects, such as a landscape seen past near branches."),
                keywords: LocalizedStringResource("Search keywords: Far Focus", defaultValue: "landscape, infinity", bundle: bundle, comment: "Settings search keywords for the camera's Far Focus control, separated by commas. Not shown on screen."),
                place: .inQ),
            CameraPointer(
                id: "magnify",
                title: LocalizedStringResource("Magnify", bundle: bundle, comment: "Quick control and pill on the camera: shows the viewfinder enlarged around the focus point, to check focus. The photo is not zoomed."),
                keywords: LocalizedStringResource("Search keywords: Magnify", defaultValue: "zoom, loupe, focus check", bundle: bundle, comment: "Settings search keywords for the camera's Magnify control, separated by commas. Not shown on screen."),
                place: .inQ),
            CameraPointer(id: "grid", title: SettingsText.grid, keywords: nil, place: .inQ),
            CameraPointer(id: "level", title: SettingsText.level, keywords: LocalizedStringResource("Search keywords: Level", defaultValue: "horizon, straight, tap, haptic, vibration", bundle: bundle, comment: "Settings search keywords for the Level, separated by commas. Not shown on screen."), place: .inQ),
            CameraPointer(
                id: "compare",
                title: LocalizedStringResource("Compare", bundle: bundle, comment: "Title of the compare view, and the camera switch and its Voice Control name that turns the comparison shot on: nope.'s photo next to the phone-processed version, which isn't saved."),
                keywords: LocalizedStringResource("Search keywords: Compare", defaultValue: "comparison, side by side, phone processing", bundle: bundle, comment: "Settings search keywords for the camera's Compare switch, separated by commas. Not shown on screen."),
                place: .inQ),
        ]
    }()
}

/// The Settings search index and its matching (`docs/design/BUILD-SPEC.md`, 3.10, "Search").
///
/// The index has one entry for each setting on any page, with its title, its keywords and its
/// page path, and the pointers to camera controls that aren't in Settings
/// (``CameraPointer``). Entries that this device or this camera screen doesn't show are left
/// out, so no result opens a page that isn't there. Matching is plain text, ignoring case and
/// diacritics: a result has every word of the search in its title or keywords, or, when none
/// has, any word.
enum SettingsSearch {
    /// What this device and this camera screen offer, which decides which entries exist.
    struct Availability: Equatable {
        /// Whether presets exist (not in the Lock Screen camera).
        var hasPresets = true
        /// Whether a lens offers a choice of photo size.
        var offersPhotoSize = false
        /// Whether the device has a front camera.
        var hasFrontCamera = true
        /// Whether the app can tag a location.
        var offersLocation = true
        /// Whether a lens has no Bayer RAW, so the Processed marker applies.
        var offersProcessedMarker = false
        /// Whether the Live Activity switch is offered.
        var offersLiveActivity = false
        /// Whether the device offers Astro (`CameraModel/deviceOffersAstro`), so the Keep Night
        /// Mode After Astro switch applies.
        var offersAstro = false
        /// Whether Keep Screen On is offered: not in the Lock Screen camera, which leaves the
        /// screen to iOS (``SwiftUICore/EnvironmentValues/offersKeepScreenOn``).
        var offersKeepScreenOn = true
        /// Whether the device has two or more rear lenses (`LensPinch/isOffered(on:)`), so the
        /// Pinch setting applies.
        var offersPinch = false
        /// Whether the Assistant Access page can be opened: everywhere but the Lock Screen
        /// camera, where the row is read only.
        var offersAssistantAccessPage = true
        /// Whether About shows the Rate or Review link: only once the app has an App Store ID
        /// (``AboutScreen/rateURL(appStoreID:)``).
        var offersRateOrReview = false

        /// Creates the availability.
        ///
        /// - Parameters:
        ///   - hasPresets: Whether presets exist.
        ///   - offersPhotoSize: Whether a lens offers a choice of photo size.
        ///   - hasFrontCamera: Whether the device has a front camera.
        ///   - offersLocation: Whether the app can tag a location.
        ///   - offersProcessedMarker: Whether a lens has no Bayer RAW.
        ///   - offersLiveActivity: Whether the Live Activity switch is offered.
        ///   - offersAstro: Whether the device offers Astro, so Keep Night Mode After Astro applies.
        ///   - offersKeepScreenOn: Whether Keep Screen On is offered.
        ///   - offersPinch: Whether the device has two or more rear lenses, so Pinch applies.
        ///   - offersAssistantAccessPage: Whether the Assistant Access page can be opened.
        ///   - offersRateOrReview: Whether About shows the Rate or Review link.
        init(
            hasPresets: Bool = true, offersPhotoSize: Bool = false, hasFrontCamera: Bool = true,
            offersLocation: Bool = true, offersProcessedMarker: Bool = false, offersLiveActivity: Bool = false,
            offersAstro: Bool = false, offersKeepScreenOn: Bool = true,
            offersPinch: Bool = false, offersAssistantAccessPage: Bool = true, offersRateOrReview: Bool = false
        ) {
            self.hasPresets = hasPresets
            self.offersPhotoSize = offersPhotoSize
            self.hasFrontCamera = hasFrontCamera
            self.offersLocation = offersLocation
            self.offersProcessedMarker = offersProcessedMarker
            self.offersLiveActivity = offersLiveActivity
            self.offersAstro = offersAstro
            self.offersKeepScreenOn = offersKeepScreenOn
            self.offersPinch = offersPinch
            self.offersAssistantAccessPage = offersAssistantAccessPage
            self.offersRateOrReview = offersRateOrReview
        }

        /// Whether the item exists here.
        ///
        /// - Parameter id: The item.
        /// - Returns: `false` for an item this device or screen doesn't show.
        func offers(_ id: SettingsID) -> Bool {
            switch id {
            case .presets, .factoryDefaults, .saveCurrentSettings: hasPresets
            case .photoSize: offersPhotoSize
            case .mirrorFrontCamera: hasFrontCamera
            case .detailsLocation: offersLocation
            case .showProcessedMarker: offersProcessedMarker
            case .liveActivity: offersLiveActivity
            case .keepNightModeAfterAstro: offersAstro
            case .keepScreenOn, .dimAfter: offersKeepScreenOn
            case .pinch: offersPinch
            case .assistantAccess, .assistantAccessSwitch, .assistantAsk: offersAssistantAccessPage
            case .rateOrReview: offersRateOrReview
            default: true
            }
        }
    }

    /// The items search lists: every row and page, without the group headers.
    static let searchable: [SettingsID] = SettingsID.allCases.filter {
        ![.photos, .privacy, .camera, .screen, .more, .honestyCloseUpFocus].contains($0)
    }

    /// The words of a search, split at white space.
    ///
    /// - Parameter query: The search text.
    /// - Returns: Its words; none for empty or blank text.
    static func words(of query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// A localized keyword list split into keywords: at commas, including the full-width and
    /// ideographic commas of Chinese and Japanese, and at semicolons.
    ///
    /// - Parameter list: The list, such as "metadata, EXIF, GPS".
    /// - Returns: The trimmed, non-empty keywords.
    static func keywords(from list: String) -> [String] {
        list.split(whereSeparator: { ",，、;；".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whether a search's words are in a title or its keywords, ignoring case and diacritics, as
    /// the system's standard search does: each word (`requiresAll`) or any word.
    ///
    /// - Parameters:
    ///   - words: The words of the search.
    ///   - title: The localized title.
    ///   - keywords: The localized keywords.
    ///   - requiresAll: Whether every word must be found; otherwise any one is enough.
    /// - Returns: `true` on a match; `false` with no words.
    static func matches(_ words: [String], title: String, keywords: [String], requiresAll: Bool = false) -> Bool {
        guard !words.isEmpty else { return false }
        let found = { (word: String) in
            title.localizedStandardContains(word) || keywords.contains { $0.localizedStandardContains(word) }
        }
        return requiresAll ? words.allSatisfy(found) : words.contains(where: found)
    }

    /// What a search finds: the camera pointers and the Settings items, in the order of the
    /// Settings list.
    ///
    /// An item matches when it has every word of the search, so "focus on faces" finds Focus on
    /// Faces alone. When nothing has every word, an item that has any word matches, so a search
    /// for several things at once ("shutter flash manual") lists each of them.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - availability: What this device and screen offer.
    /// - Returns: The matching pointers and items.
    static func results(for query: String, availability: Availability) -> (pointers: [CameraPointer], settings: [SettingsID]) {
        let words = words(of: query)
        guard !words.isEmpty else { return ([], []) }
        let items = searchable.filter(availability.offers).map { id in
            (id, String(localized: SettingsText.title(of: id)), SettingsText.keywords(of: id).map { keywords(from: String(localized: $0)) } ?? [])
        }
        let pointers = CameraPointer.all.map { pointer in
            (pointer, String(localized: pointer.title), pointer.keywords.map { keywords(from: String(localized: $0)) } ?? [])
        }
        for requiresAll in [true, false] {
            let foundItems = items.filter { matches(words, title: $0.1, keywords: $0.2, requiresAll: requiresAll) }.map(\.0)
            let foundPointers = pointers.filter { matches(words, title: $0.1, keywords: $0.2, requiresAll: requiresAll) }.map(\.0)
            if !foundItems.isEmpty || !foundPointers.isEmpty { return (foundPointers, foundItems) }
        }
        return ([], [])
    }

    /// The Settings items a search finds (``results(for:availability:)``).
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - availability: What this device and screen offer.
    /// - Returns: The matching items.
    static func settings(matching query: String, availability: Availability) -> [SettingsID] {
        results(for: query, availability: availability).settings
    }

    /// The camera controls a search finds (``results(for:availability:)``).
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - availability: What this device and screen offer.
    /// - Returns: The matching pointers.
    static func pointers(matching query: String, availability: Availability = Availability()) -> [CameraPointer] {
        results(for: query, availability: availability).pointers
    }

    /// Where an item is, as a search result shows it: its group for a row of the Settings list,
    /// "Group › Page" for a row on a page, "Presets" for a row on the Presets page, and
    /// "Settings" for the Presets row, which has no group.
    ///
    /// - Parameter id: The item.
    /// - Returns: The localized place.
    static func place(of id: SettingsID) -> String {
        let group = id.group.map { String(localized: SettingsText.title(of: $0)) }
        guard let page = id.page else { return group ?? SettingsText.settingsList }
        let pageName = String(localized: SettingsText.title(of: page.id))
        guard let group else { return pageName }
        return SettingsText.path(group, pageName)
    }

    /// Where an item is, as VoiceOver reads it, without the separator symbol.
    ///
    /// - Parameter id: The item.
    /// - Returns: The localized place.
    static func spokenPlace(of id: SettingsID) -> String {
        let group = id.group.map { String(localized: SettingsText.title(of: $0)) }
        guard let page = id.page else { return group ?? SettingsText.settingsList }
        let pageName = String(localized: SettingsText.title(of: page.id))
        guard let group else { return pageName }
        return SettingsText.spokenPath(group, pageName)
    }
}

/// The search results that replace the Settings list while searching: the pointers to the
/// camera under "On the Camera", then the settings under "In Settings". Choosing a setting opens
/// its page; a pointer doesn't navigate. With no match, the system's empty search state.
struct SettingsSearchResults: View {
    /// The search text.
    let query: String

    /// What this device and screen offer.
    let availability: SettingsSearch.Availability

    /// Opens an item.
    let open: (SettingsID) -> Void

    /// Creates the results.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - availability: What this device and screen offer.
    ///   - open: Opens an item.
    init(query: String, availability: SettingsSearch.Availability, open: @escaping (SettingsID) -> Void) {
        self.query = query
        self.availability = availability
        self.open = open
    }

    /// The results, or the empty state.
    var body: some View {
        let (pointers, settings) = SettingsSearch.results(for: query, availability: availability)
        if pointers.isEmpty && settings.isEmpty {
            ContentUnavailableView.search(text: query)
                // Its own background, so the sheet's, which night mode's red can't reach, doesn't
                // show through in Night Mode (issue #88).
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else {
            NopeForm {
                if !pointers.isEmpty {
                    Section {
                        ForEach(pointers) { pointer in
                            pointerRow(pointer)
                        }
                    } header: {
                        Text("On the Camera", bundle: .module, comment: "Settings search: header above results that are controls on the camera, not settings.")
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                if !settings.isEmpty {
                    Section {
                        ForEach(settings, id: \.self) { id in
                            settingRow(id)
                        }
                    } header: {
                        // Only named when pointers are listed too, as drawn.
                        if !pointers.isEmpty {
                            Text("In Settings", bundle: .module, comment: "Settings search: header above results that are settings.")
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
        }
    }

    /// A camera control and where it is; not a button.
    ///
    /// - Parameter pointer: The pointer.
    private func pointerRow(_ pointer: CameraPointer) -> some View {
        Label {
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                Text(pointer.title)
                Text(pointer.place.text)
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "camera")
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(String(localized: pointer.title)). \(String(localized: pointer.place.text))."))
        .accessibilityIdentifier("settings.search.camera.\(pointer.id)")
    }

    /// A setting and where it is; opens it.
    ///
    /// - Parameter id: The setting.
    private func settingRow(_ id: SettingsID) -> some View {
        Button {
            open(id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                    Text(SettingsText.title(of: id))
                    Text(verbatim: SettingsSearch.place(of: id))
                        .font(.footnote)
                        .foregroundStyle(CameraStyle.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: NopeSpace.xs)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CameraStyle.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: SettingsText.spokenResult(String(localized: SettingsText.title(of: id)), SettingsSearch.spokenPlace(of: id))))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings.search.\(id.rawValue)")
    }
}
