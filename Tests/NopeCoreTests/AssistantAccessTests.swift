import Foundation
import Testing

@testable import NopeCore

/// The Assistant Access check (issue #82; `docs/design/assistant-access.md`, sections 3, 4, 7,
/// 10 and 17): the decision in every state, the session's runner and record, the stored
/// settings, preset names, and presets that leave the Privacy settings and Assistant Access as
/// they are.
@MainActor
struct AssistantAccessTests {
    /// Every gated action.
    static let gated = AssistantAction.allCases.filter(\.isGated)

    // MARK: The decision

    @Test func offRefusesEveryGatedKindAndRunsTheOthers() {
        for ask in AssistantAskLevel.allCases {
            for locked in [false, true] {
                let access = AssistantAccess(isOn: false, ask: ask, deviceIsLocked: locked)
                #expect(access.decision(for: .takesPhotos) == .refuse)
                #expect(access.decision(for: .changes) == .refuse)
                #expect(access.decision(for: .opensScreen) == .run)
                #expect(access.decision(for: .pressedByPerson) == .run)
            }
        }
    }

    @Test func onFollowsAskFirst() {
        let table: [(AssistantAskLevel, photos: AssistantDecision, changes: AssistantDecision)] = [
            (.everyAction, .ask, .ask), (.beforePhoto, .ask, .run), (.never, .run, .run),
        ]
        for (ask, photos, changes) in table {
            let access = AssistantAccess(isOn: true, ask: ask)
            #expect(access.decision(for: .takesPhotos) == photos)
            #expect(access.decision(for: .changes) == changes)
            #expect(access.decision(for: .opensScreen) == .run)
            #expect(access.decision(for: .pressedByPerson) == .run)
        }
    }

    @Test func aLockedDeviceRefusesEveryGatedKindWhileOn() {
        for ask in AssistantAskLevel.allCases {
            let access = AssistantAccess(isOn: true, ask: ask, deviceIsLocked: true)
            #expect(access.decision(for: .takesPhotos) == .requiresUnlock)
            #expect(access.decision(for: .changes) == .requiresUnlock)
            #expect(access.decision(for: .opensScreen) == .run)
            #expect(access.decision(for: .pressedByPerson) == .run)
        }
    }

    @Test func everyActionHasItsKind() {
        let photos: Set<AssistantAction> = [.takePhoto, .takeBracket, .startInterval]
        let screens: Set<AssistantAction> = [.openCamera, .openAssistantAccess]
        let pressed: Set<AssistantAction> = [.nightModeControl, .liveActivityStop]
        for action in AssistantAction.allCases {
            let expected: AssistantActionKind =
                photos.contains(action) ? .takesPhotos
                : screens.contains(action) ? .opensScreen : pressed.contains(action) ? .pressedByPerson : .changes
            #expect(action.kind == expected, "\(action)")
            #expect(action.isGated == (expected == .takesPhotos || expected == .changes))
        }
        // Thirteen gated actions: the fourteen of 1.0.0 except Open the Camera.
        #expect(Self.gated.count == 13)
        // Every Action has no exceptions: stopping and turning off ask too.
        let everyAction = AssistantAccess(isOn: true, ask: .everyAction)
        for action in Self.gated { #expect(everyAction.decision(for: action) == .ask, "\(action)") }
        let beforePhoto = AssistantAccess(isOn: true, ask: .beforePhoto)
        #expect(beforePhoto.decision(for: .stopInterval) == .run)
        #expect(beforePhoto.decision(for: .takeBracket) == .ask)
    }

    @Test func presetNamesAreOfferedOnlyWhileAccessIsOn() {
        let preset = SettingsPreset(name: "Street", settings: SettingsPreset.factorySettings, camera: .factory)
        let off = AssistantAccess(isOn: false, ask: .never)
        #expect(!off.offersPresetNames)
        #expect(off.offeredPresets([preset]).isEmpty)
        let on = AssistantAccess(isOn: true, ask: .everyAction)
        #expect(on.offersPresetNames)
        #expect(on.offeredPresets([preset]) == [preset])
    }

    // MARK: The settings

    @Test func defaultsAreOffAndEveryAction() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(!settings.assistantAccess)
        #expect(settings.assistantAsk == .everyAction)
        #expect(settings.assistantAccess(deviceIsLocked: false) == AssistantAccess(isOn: false, ask: .everyAction))
    }

    @Test func choicesAreStoredAndSurviveARelaunch() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setAssistantAccess(true)
        settings.setAssistantAsk(.beforePhoto)
        let relaunched = NopeSettings(defaults: scratch.defaults)
        #expect(relaunched.assistantAccess)
        #expect(relaunched.assistantAsk == .beforePhoto)
        #expect(relaunched.assistantAccess(deviceIsLocked: true) == AssistantAccess(isOn: true, ask: .beforePhoto, deviceIsLocked: true))
    }

    @Test func anUnknownChoiceFallsBackToEveryAction() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("sometimes", forKey: NopeSettings.Key.assistantAsk)
        #expect(NopeSettings(defaults: scratch.defaults).assistantAsk == .everyAction)
    }

    @Test func reloadFollowsAChangeInTheStore() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        NopeSettings(defaults: scratch.defaults).setAssistantAccess(true)
        NopeSettings(defaults: scratch.defaults).setAssistantAsk(.never)
        #expect(settings.reload())
        #expect(settings.assistantAccess)
        #expect(settings.assistantAsk == .never)
    }

    @Test func theLockScreenSnapshotCarriesBothValuesWithinItsLimit() throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setAssistantAccess(true)
        settings.setAssistantAsk(.never)
        let snapshot = try settings.makeSnapshot()
        #expect(try snapshot.encodedSize() <= NopeSettingsSnapshot.appContextLimit)
        let lockScreen = ScratchDefaults()
        let copy = NopeSettings(defaults: lockScreen.defaults)
        #expect(copy.apply(snapshot))
        #expect(copy.assistantAccess)
        #expect(copy.assistantAsk == .never)
    }

    // MARK: Presets

    @Test func aPresetNeverStoresAssistantAccess() throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        settings.setAssistantAccess(true)
        settings.setAssistantAsk(.never)
        let preset = try presets.saveCurrent(named: "Street", camera: nil)
        let values = try #require(
            PropertyListSerialization.propertyList(from: preset.settings.values, format: nil) as? [String: Any])
        #expect(values[NopeSettings.Key.assistantAccess] == nil)
        #expect(values[NopeSettings.Key.assistantAsk] == nil)
    }

    @Test func applyingASavedPresetInTheAppLeavesAssistantAccess() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let preset = try presets.saveCurrent(named: "Street", camera: nil)
        settings.setAssistantAccess(true)
        settings.setAssistantAsk(.beforePhoto)
        await presets.apply(.saved(preset.id), camera: nil, location: nil)
        #expect(settings.assistantAccess)
        #expect(settings.assistantAsk == .beforePhoto)
        // Undo never changes it either.
        settings.setAssistantAsk(.never)
        #expect(await presets.undo(camera: nil, location: nil))
        #expect(settings.assistantAccess)
        #expect(settings.assistantAsk == .never)
    }

    @Test func factoryDefaultsInTheAppResetsAssistantAccess() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        settings.setAssistantAccess(true)
        settings.setAssistantAsk(.never)
        let result = await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(!result.keptPrivacySettings)
        #expect(!settings.assistantAccess)
        #expect(settings.assistantAsk == .everyAction)
        // Undo leaves it off: it is turned on on its own page only.
        #expect(await presets.undo(camera: nil, location: nil))
        #expect(!settings.assistantAccess)
    }

    @Test func factoryDefaultsInTheAppRemovesTheTipCounter() async {
        // docs/SECURITY_AUDIT.md, "Local data": the counter is removed by Factory Defaults.
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let session = AssistantSession(settings: settings)
        scratch.defaults.set(AssistantSession.tipThreshold + 1, forKey: AssistantSession.tipCounterKey)
        session.reloadTipCounter()
        #expect(session.tipCounter == AssistantSession.tipThreshold + 1)
        _ = await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(scratch.defaults.object(forKey: AssistantSession.tipCounterKey) == nil)
        // The session reads it again, as the Presets page asks it to: from 0.
        session.reloadTipCounter()
        #expect(session.tipCounter == 0)
        // Undo doesn't bring it back.
        #expect(await presets.undo(camera: nil, location: nil))
        #expect(scratch.defaults.object(forKey: AssistantSession.tipCounterKey) == nil)
    }

    @Test func otherPresetsAndAssistantsKeepTheTipCounter() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        scratch.defaults.set(3, forKey: AssistantSession.tipCounterKey)
        _ = await presets.apply(.factoryDefaults, camera: nil, location: nil, keepsPrivacySettings: true)
        #expect(scratch.defaults.integer(forKey: AssistantSession.tipCounterKey) == 3)
        let saved = try presets.saveCurrent(named: "Mine", camera: nil)
        _ = await presets.apply(.saved(saved.id), camera: nil, location: nil)
        #expect(scratch.defaults.integer(forKey: AssistantSession.tipCounterKey) == 3)
    }

    @Test func factoryDefaultsThroughAnAssistantKeepsPrivacyAndAccess() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        settings.setAssistantAccess(true)
        settings.setAssistantAsk(.never)
        settings.setSignsPhotos(true)
        settings.setMetadataItem(.dateAndTime, isIncluded: true)
        settings.setNightMode(true)
        let metadata = settings.metadata

        let result = await presets.apply(.factoryDefaults, camera: nil, location: nil, keepsPrivacySettings: true)

        #expect(result.keptPrivacySettings)
        #expect(result.isApplied)
        #expect(settings.metadata == metadata)
        #expect(settings.signsPhotos)
        #expect(settings.assistantAccess)
        #expect(settings.assistantAsk == .never)
        // Everything else applied.
        #expect(!settings.isNightModeOn)
    }

    @Test func aSavedPresetThroughAnAssistantLeavesEveryPrivacySetting() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        // The preset has Location, signing and details on, and night mode on.
        settings.setMetadataItem(.location, isIncluded: true)
        settings.setSignsPhotos(true)
        settings.setMetadataItem(.cameraMakeAndModel, isIncluded: true)
        settings.setNightMode(true)
        let preset = try presets.saveCurrent(named: "Street", camera: nil)
        // Now: everything private, night mode off.
        settings.setRemovesAllOptionalDetails(true)
        settings.setSignsPhotos(false)
        settings.setNightMode(false)
        let metadata = settings.metadata
        let provider = FakeLocationProvider(access: .notDetermined, afterRequest: .allowed)

        let result = await presets.apply(
            .saved(preset.id), camera: nil, location: LocationTagging(provider: provider), keepsPrivacySettings: true)

        #expect(result.keptPrivacySettings)
        #expect(settings.metadata == metadata)
        #expect(!settings.metadata.isOn(.location))
        #expect(!settings.signsPhotos)
        // Location's prompt is never shown: Location isn't applied.
        #expect(await provider.requests == 0)
        #expect(result.notices == [.cameraNotReady])
        #expect(settings.isNightModeOn)
        // Undo restores as it does from the Presets list.
        #expect(await presets.undo(camera: nil, location: nil))
        #expect(!settings.isNightModeOn)
        #expect(settings.metadata == metadata)
    }

    @Test func noShortcutRequestChangesAPrivacySetting() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        settings.setMetadataItem(.location, isIncluded: true)
        settings.setSignsPhotos(true)
        let preset = try presets.saveCurrent(named: "Open", camera: nil)
        settings.setRemovesAllOptionalDetails(true)
        settings.setSignsPhotos(false)
        settings.setAssistantAccess(true)
        settings.setAssistantAsk(.never)
        let metadata = settings.metadata
        let model = await PresetShortcutTests().makeModel()
        let requests: [ShortcutRequest] = [
            .takePhoto(PhotoShortcut()), .takePhoto(PhotoShortcut(count: 2)),
            .takeBracket(BracketShortcut(frameCount: 3, step: 1)), .selectLens(.telephoto), .selectLens(.wide),
            .setLight(isOn: true), .setLight(isOn: false), .startInterval(IntervalShortcut()), .stopInterval,
            .setFocusRange(.closeUp), .setFocusRange(.unlimited),
            .setPhotoSize(PhotoSizeShortcut(lensKind: nil, size: .largest)), .applyPreset(.saved(preset.id)),
            .applyPreset(.factoryDefaults),
        ]
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox, settings: settings, presets: presets) }
        defer { server.cancel() }
        await waitUntil { inbox.isServed }
        for request in requests {
            _ = await inbox.submit(request)
            #expect(settings.metadata == metadata, "\(request)")
            #expect(settings.assistantAccess, "\(request)")
            #expect(settings.assistantAsk == .never, "\(request)")
        }
    }

    // MARK: The session

    /// A session with a fresh store, and the store.
    func makeSession() -> (AssistantSession, ScratchDefaults) {
        let scratch = ScratchDefaults()
        return (AssistantSession(settings: NopeSettings(defaults: scratch.defaults)), scratch)
    }

    @Test func offRefusesWithoutAskingOrRunning() async {
        let (session, _) = makeSession()
        for action in Self.gated {
            var ran = false
            var asked = false
            let outcome = await session.perform(
                action, access: { AssistantAccess(isOn: false, ask: .everyAction) },
                confirm: {
                    asked = true
                    return true
                }, run: { ran = true })
            guard case .refused = outcome else {
                Issue.record("\(action) wasn't refused")
                continue
            }
            #expect(!ran)
            #expect(!asked)
        }
        #expect(session.refusedCount == Self.gated.count)
        #expect(session.showsRefusalCard)
        #expect(session.records.count == Self.gated.count)
        #expect(session.records.allSatisfy { $0.result == .refused })
    }

    @Test func aLockedDeviceIsRefusedWithoutTheCard() async {
        let (session, _) = makeSession()
        var ran = false
        let outcome = await session.perform(
            .takePhoto, access: { AssistantAccess(isOn: true, ask: .never, deviceIsLocked: true) }, confirm: { true },
            run: { ran = true })
        guard case .requiresUnlock = outcome else {
            Issue.record("not refused")
            return
        }
        #expect(!ran)
        #expect(!session.showsRefusalCard)
        #expect(session.records.map(\.result) == [.refused])
    }

    @Test func eachAskFirstChoiceAsksOrRuns() async {
        for ask in AssistantAskLevel.allCases {
            for action in Self.gated {
                let (session, _) = makeSession()
                var asked = 0
                var ran = 0
                let outcome = await session.perform(
                    action, access: { AssistantAccess(isOn: true, ask: ask) },
                    confirm: {
                        asked += 1
                        return true
                    }, run: { () -> Int in
                        ran += 1
                        return 7
                    })
                guard case .ran(let value) = outcome else {
                    Issue.record("\(action) didn't run with \(ask)")
                    continue
                }
                let expectsQuestion = AssistantAccess(isOn: true, ask: ask).decision(for: action) == .ask
                #expect(value == 7)
                #expect(ran == 1)
                #expect(asked == (expectsQuestion ? 1 : 0))
                #expect(session.records.map(\.result) == [expectsQuestion ? .askedAllowed : .ranWithoutAsking])
                #expect(session.records.first?.action == action)
            }
        }
    }

    @Test func aCancelledQuestionChangesNothing() async {
        let (session, _) = makeSession()
        var ran = false
        let outcome = await session.perform(
            .applyPreset, access: { AssistantAccess(isOn: true, ask: .everyAction) }, confirm: { false },
            run: { ran = true })
        guard case .cancelled = outcome else {
            Issue.record("not cancelled")
            return
        }
        #expect(!ran)
        #expect(session.records.map(\.result) == [.askedCancelled])
        #expect(session.tipCounter == 0)
        #expect(!session.showsRefusalCard)
    }

    @Test func accessTurnedOffWhileTheQuestionShowsRefuses() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let session = AssistantSession(settings: settings)
        settings.setAssistantAccess(true)
        var ran = false
        let outcome = await session.perform(
            .takePhoto, access: { settings.assistantAccess(deviceIsLocked: false) },
            confirm: {
                settings.setAssistantAccess(false)
                return true
            }, run: { ran = true })
        guard case .refused = outcome else {
            Issue.record("not refused")
            return
        }
        #expect(!ran)
        #expect(session.refusedCount == 1)
    }

    @Test func aDeviceLockedWhileTheQuestionShowsRefuses() async {
        let (session, _) = makeSession()
        var locked = false
        var ran = false
        let outcome = await session.perform(
            .takePhoto, access: { AssistantAccess(isOn: true, ask: .everyAction, deviceIsLocked: locked) },
            confirm: {
                locked = true
                return true
            }, run: { ran = true })
        guard case .requiresUnlock = outcome else {
            Issue.record("not refused")
            return
        }
        #expect(!ran)
    }

    @Test func entryPointsThatArentGatedRunWithoutARecord() async {
        let (session, _) = makeSession()
        for action in AssistantAction.allCases where !action.isGated {
            var ran = false
            let outcome = await session.perform(
                action, access: { AssistantAccess(isOn: false, ask: .everyAction) }, confirm: { false },
                run: { ran = true })
            guard case .ran = outcome else {
            Issue.record("\(action) didn't run")
            return
        }
            #expect(ran)
        }
        #expect(session.records.isEmpty)
        #expect(session.refusedCount == 0)
    }

    @Test func theRecordKeepsTheNewestTwenty() async {
        let (session, _) = makeSession()
        for index in 0..<25 {
            let action = Self.gated[index % Self.gated.count]
            _ = await session.perform(action, access: { AssistantAccess(isOn: true, ask: .never) }, confirm: { true }, run: {})
        }
        #expect(session.records.count == AssistantSession.maximumRecords)
        #expect(session.records.first?.action == Self.gated[24 % Self.gated.count])
        #expect(Set(session.records.map(\.id)).count == AssistantSession.maximumRecords)
        // Newest first.
        #expect(session.records.map(\.id) == session.records.map(\.id).sorted(by: >))
    }

    @Test func theRecordIsInMemoryOnly() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let before = Set(scratch.defaults.dictionaryRepresentation().keys)
        let session = AssistantSession(settings: settings)
        _ = await session.perform(.takePhoto, access: { AssistantAccess(isOn: false, ask: .never) }, confirm: { true }, run: {})
        _ = await session.perform(.switchLens, access: { AssistantAccess(isOn: true, ask: .never) }, confirm: { true }, run: {})
        session.announce("Now using the telephoto camera.")
        // Nothing new is stored; a new session (a relaunch) starts empty.
        #expect(Set(scratch.defaults.dictionaryRepresentation().keys) == before)
        let relaunched = AssistantSession(settings: settings)
        #expect(relaunched.records.isEmpty)
        #expect(relaunched.refusedCount == 0)
        #expect(relaunched.notice == nil)
    }

    @Test func theRefusalCardComesBackWithANewRefusal() async {
        let (session, _) = makeSession()
        let off = { AssistantAccess(isOn: false, ask: .everyAction) }
        _ = await session.perform(.takePhoto, access: off, confirm: { true }, run: {})
        _ = await session.perform(.switchLens, access: off, confirm: { true }, run: {})
        #expect(session.refusedCount == 2)
        #expect(session.showsRefusalCard)
        session.dismissRefusalCard()
        #expect(!session.showsRefusalCard)
        _ = await session.perform(.takePhoto, access: off, confirm: { true }, run: {})
        #expect(session.showsRefusalCard)
        #expect(session.refusedCount == 3)
    }

    @Test func theTipShowsOnceAfterFiveConfirmations() async {
        let (session, scratch) = makeSession()
        let on = { AssistantAccess(isOn: true, ask: .everyAction) }
        for _ in 0..<4 { _ = await session.perform(.takePhoto, access: on, confirm: { true }, run: {}) }
        #expect(!session.showsTip)
        _ = await session.perform(.takePhoto, access: on, confirm: { true }, run: {})
        #expect(session.showsTip)
        // It stops at five.
        _ = await session.perform(.takePhoto, access: on, confirm: { true }, run: {})
        #expect(session.tipCounter == AssistantSession.tipThreshold)
        // The counter is the one stored value, and survives a relaunch.
        #expect(AssistantSession(defaults: scratch.defaults).showsTip)
        session.dismissTip()
        #expect(!session.showsTip)
        session.dismissTip()
        _ = await session.perform(.takePhoto, access: on, confirm: { true }, run: {})
        #expect(!session.showsTip)
        #expect(!AssistantSession(defaults: scratch.defaults).showsTip)
        #expect(scratch.defaults.integer(forKey: AssistantSession.tipCounterKey) == AssistantSession.tipThreshold + 1)
    }

    @Test func aStoredCounterOutOfRangeIsClamped() {
        let scratch = ScratchDefaults()
        scratch.defaults.set(99, forKey: AssistantSession.tipCounterKey)
        #expect(AssistantSession(defaults: scratch.defaults).tipCounter == AssistantSession.tipThreshold + 1)
        scratch.defaults.set(-3, forKey: AssistantSession.tipCounterKey)
        #expect(AssistantSession(defaults: scratch.defaults).tipCounter == 0)
    }

    @Test func theTipCounterIsNotInPresetsOrTheSnapshot() throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        scratch.defaults.set(3, forKey: AssistantSession.tipCounterKey)
        #expect(!SharedSettingsStore.isSettingsKey(AssistantSession.tipCounterKey))
        let values = try #require(
            PropertyListSerialization.propertyList(from: try settings.makeSnapshot().values, format: nil) as? [String: Any])
        #expect(values[AssistantSession.tipCounterKey] == nil)
    }

    @Test func theHintShowsTheLatestSentence() {
        let (session, _) = makeSession()
        session.announce("Now using the telephoto camera.")
        let first = session.notice
        #expect(first?.sentence == "Now using the telephoto camera.")
        session.announce("The light is on.")
        // An old hint's end leaves the new one.
        session.clearNotice(first?.id ?? 0)
        #expect(session.notice?.sentence == "The light is on.")
        session.clearNotice(session.notice?.id ?? 0)
        #expect(session.notice == nil)
    }

    @Test func openAssistantAccessAsksForThePage() {
        let (session, _) = makeSession()
        #expect(!session.opensSettingsPage)
        session.requestSettingsPage()
        #expect(session.opensSettingsPage)
        session.settingsPageOpened()
        #expect(!session.opensSettingsPage)
    }

    // MARK: Results

    @Test func photosSavedCountsOnlySavedPhotos() {
        #expect(ShortcutOutcome.saved(isSigned: true).photosSaved == 1)
        #expect(ShortcutOutcome.savedSeveral(count: 5, allSigned: false).photosSaved == 5)
        #expect(ShortcutOutcome.focusBracketStopped(saved: 4, total: 10).photosSaved == 4)
        #expect(ShortcutOutcome.cancelled.photosSaved == 0)
        #expect(ShortcutOutcome.intervalStarted.photosSaved == 0)
        #expect(ShortcutOutcome.notSaved(.notRunning).photosSaved == 0)
    }
}
