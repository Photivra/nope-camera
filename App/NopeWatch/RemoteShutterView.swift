import NopeCore
import SwiftUI

/// The watch app's only screen (issue #63): the phone camera's status, the result of the last
/// photo, the shutter (or Cancel Timer during a countdown) and the delay.
///
/// The view holds no rules: what is shown and enabled comes from ``WatchRemote``. Haptics
/// confirm the shutter, each countdown second and the result, and VoiceOver announces the
/// countdown and the result, so the watch works without looking at it.
struct RemoteShutterView: View {
    /// The watch app's model.
    @Bindable var remote: WatchRemote

    /// The screen: a scrolling column, so every control stays reachable at the largest text
    /// sizes.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NopeSpace.xs) {
                    StatusLineView(line: WatchText.message(for: remote.display), identifier: "WatchStatus")
                        .accessibilityAddTraits(.updatesFrequently)
                    if let result = remote.lastResult {
                        StatusLineView(line: resultLine(result), identifier: "WatchResult")
                    }
                    if remote.canCancelTimer {
                        cancelButton
                    } else {
                        shutterButton
                    }
                    delayPicker
                }
            }
            // No title: the accessibility audit flags "nope." as a label that isn't
            // human-readable, and the status line already starts the screen.
        }
        .sensoryFeedback(trigger: remote.display) { _, new in
            if case .countingDown = new { return .impact(weight: .light) }
            return nil
        }
        .sensoryFeedback(trigger: remote.lastResult) { _, new in
            guard let new else { return nil }
            return resultLine(new).tone == .warning ? .warning : .success
        }
        .onChange(of: remote.display) { _, new in
            if case .countingDown(let seconds) = new { announce(WatchText.countdown(seconds)) }
        }
        .onChange(of: remote.lastResult) { _, new in
            if let new { announce(resultLine(new).text) }
        }
    }

    /// The smallest height of Take Photo and Cancel Timer: 56 points, the tile minimum
    /// (docs/design/watch.html: "at least 56 pt tall and full width"). A label that wraps, in a
    /// long language or at a large text size, makes the button taller.
    static let buttonMinHeight = NopeSize.tileMin

    /// The line for a result, with the phone's reason when its photos aren't all signed.
    ///
    /// - Parameter result: How the last photo ended.
    /// - Returns: The message.
    private func resultLine(_ result: WatchResult) -> StatusLine {
        WatchText.message(for: result, unsignedReason: remote.lastUnsignedReason)
    }

    /// The shutter: a large round button, enabled only while the phone's camera is ready.
    private var shutterButton: some View {
        Button {
            Task { await remote.takePhoto() }
        } label: {
            Label {
                Text("Take Photo", comment: "Watch button that takes a photo with the phone's camera.")
            } icon: {
                Image(systemName: "camera.circle.fill")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Self.buttonMinHeight)
        }
        // The system's bordered style: white text on gray keeps WCAG contrast; teal is kept for
        // verified facts (issue #68), and white text on a teal fill would fall below 4.5:1.
        .buttonStyle(.bordered)
        .disabled(!remote.canTakePhoto)
        .sensoryFeedback(.start, trigger: remote.isAwaitingResult) { _, isAwaiting in isAwaiting }
        .accessibilityIdentifier("WatchShutter")
    }

    /// Stops the phone's countdown, so no photo is taken.
    private var cancelButton: some View {
        Button(role: .cancel) {
            Task { await remote.cancelTimer() }
        } label: {
            Label {
                Text("Cancel Timer", comment: "Watch button that stops the phone's self-timer countdown, so no photo is taken.")
            } icon: {
                Image(systemName: "xmark.circle.fill")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Self.buttonMinHeight)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("WatchCancelTimer")
    }

    /// The delay before the photo, as a pushed list (a system picker that passes the audits).
    private var delayPicker: some View {
        Picker(selection: $remote.delay) {
            ForEach(WatchDelay.allCases, id: \.self) { delay in
                Text(verbatim: WatchText.name(of: delay)).tag(delay)
            }
        } label: {
            Label {
                Text("Delay", comment: "Watch picker: how long the phone waits before taking the photo.")
            } icon: {
                Image(systemName: "timer")
            }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("WatchDelay")
    }

    /// Asks VoiceOver to speak a message.
    ///
    /// - Parameter text: The message.
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// One status or result line: an SF Symbol and words, teal for a verified fact and amber for a
/// warning. VoiceOver reads it as one element.
struct StatusLineView: View {
    /// The line.
    let line: StatusLine

    /// The accessibility identifier, for the UI tests.
    let identifier: String

    /// The symbol and the words, wrapping at any text size.
    var body: some View {
        Label {
            Text(verbatim: line.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: line.symbol)
        }
        .font(.body)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// Teal for a verified fact, orange (amber) for a warning, the primary color otherwise. Never
    /// yellow (issue #68).
    private var color: Color {
        switch line.tone {
        case .plain: .primary
        case .verified: NopeColor.fact
        case .warning: NopeColor.warning
        }
    }
}
