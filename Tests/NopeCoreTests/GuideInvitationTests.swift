import Foundation
import Testing

@testable import NopeCore

/// The how-to-use guide's invitation card (issue #117; `docs/design/finish-1.0.md`, 2.1): when
/// it shows, what puts it away, and that the answer is kept on the device, across a relaunch
/// and Factory Defaults.
@MainActor
struct GuideInvitationTests {
    /// The camera live, nothing else showing: the card's own conditions.
    static let live = GuideCardContext(isCameraLive: true)

    @Test func aNewInstallShowsTheCardOnTheLiveCamera() {
        let invitation = GuideInvitation(defaults: ScratchDefaults().defaults)
        #expect(!invitation.isAnswered)
        #expect(invitation.showsCard(Self.live))
    }

    @Test func theCardWaitsForTheLiveCamera() {
        let invitation = GuideInvitation(defaults: ScratchDefaults().defaults)
        #expect(!invitation.showsCard(GuideCardContext(isCameraLive: false)))
    }

    @Test func cleanViewHidesTheCard() {
        let invitation = GuideInvitation(defaults: ScratchDefaults().defaults)
        #expect(!invitation.showsCard(GuideCardContext(isCameraLive: true, isCleanView: true)))
    }

    @Test func aCountdownOrSeriesHidesTheCard() {
        let invitation = GuideInvitation(defaults: ScratchDefaults().defaults)
        #expect(!invitation.showsCard(GuideCardContext(isCameraLive: true, isRunning: true)))
    }

    @Test func anotherCardTakesItsPlaceAndItComesBack() {
        let invitation = GuideInvitation(defaults: ScratchDefaults().defaults)
        #expect(!invitation.showsCard(GuideCardContext(isCameraLive: true, showsOtherCard: true)))
        #expect(invitation.showsCard(Self.live))
        #expect(!invitation.isAnswered)
    }

    @Test func dismissIsFinal() {
        let invitation = GuideInvitation(defaults: ScratchDefaults().defaults)
        invitation.dismiss()
        #expect(invitation.isAnswered)
        #expect(!invitation.showsCard(Self.live))
    }

    @Test func openingTheGuideIsFinal() {
        let invitation = GuideInvitation(defaults: ScratchDefaults().defaults)
        invitation.guideOpened()
        #expect(invitation.isAnswered)
        #expect(!invitation.showsCard(Self.live))
    }

    @Test func theAnswerSurvivesARelaunch() {
        let scratch = ScratchDefaults()
        GuideInvitation(defaults: scratch.defaults).dismiss()
        #expect(GuideInvitation(defaults: scratch.defaults).isAnswered)
        #expect(!GuideInvitation(defaults: scratch.defaults).showsCard(Self.live))
    }

    @Test func theAnswerIsOneBooleanOutsideTheSettingsKeys() {
        let scratch = ScratchDefaults()
        GuideInvitation(defaults: scratch.defaults).guideOpened()
        #expect(scratch.defaults.object(forKey: GuideInvitation.answeredKey) as? Bool == true)
        #expect(!GuideInvitation.answeredKey.hasPrefix(SharedSettingsStore.keyPrefix))
        #expect(!SharedSettingsStore.isSettingsKey(GuideInvitation.answeredKey))
    }

    @Test func theSettingsStoreKeepsTheAnswer() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        GuideInvitation(settings: settings).dismiss()
        #expect(GuideInvitation(defaults: scratch.defaults).isAnswered)
    }

    @Test func factoryDefaultsKeepsTheCardAway() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let invitation = GuideInvitation(settings: settings)
        invitation.dismiss()
        let result = await SettingsPresets(settings: settings).apply(.factoryDefaults, camera: nil, location: nil)
        #expect(result.isApplied)
        #expect(invitation.isAnswered)
        #expect(GuideInvitation(settings: settings).isAnswered)
        #expect(!GuideInvitation(settings: settings).showsCard(Self.live))
    }

    @Test func factoryDefaultsDoesntAnswerAnUnansweredInvitation() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        _ = await SettingsPresets(settings: settings).apply(.factoryDefaults, camera: nil, location: nil)
        #expect(!GuideInvitation(settings: settings).isAnswered)
    }

    @Test func theCameraIsLiveOnceItsFirstStartEndsAndItRuns() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: FirstStartTests.oneLens))
        let before = GuideCardContext(camera: model, showsOtherCard: false)
        #expect(before == GuideCardContext(isCameraLive: false))
        await model.send(.start)
        #expect(GuideCardContext(camera: model, showsOtherCard: false) == Self.live)
        #expect(GuideCardContext(camera: model, showsOtherCard: true) == GuideCardContext(isCameraLive: true, showsOtherCard: true))
    }

    @Test func theCameraReportsCleanView() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: FirstStartTests.oneLens))
        await model.send(.start)
        await model.send(.setCleanView(true))
        #expect(GuideCardContext(camera: model, showsOtherCard: false) == GuideCardContext(isCameraLive: true, isCleanView: true))
    }

    @Test func aCameraThatIsntAllowedIsntLive() async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .denied, capabilities: FirstStartTests.oneLens))
        await model.send(.start)
        #expect(!model.isFirstStart)
        #expect(!GuideCardContext(camera: model, showsOtherCard: false).isCameraLive)
    }
}
