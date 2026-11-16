import NopeCore
import SwiftUI

/// The interval and photo count of interval shooting (issue #48), with Start or Stop: one
/// section, shown in the Interval sheet of the Drive menu and in Pro Tools, so both offer the
/// same thing.
///
/// A series works in full auto and with manual controls on; `NopeCore` holds the series
/// (`ManualControlsModel.interval` and `ManualControlIntent.startInterval`).
struct IntervalSection: View {
    /// The intervals offered, in seconds: 1 second to 1 hour.
    static let intervals: [Double] = [1, 2, 3, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// The photo counts offered for a series, from 2 to the 999 the app allows.
    static let photoCounts = [2, 3, 5, 10, 20, 30, 50, 100, 200, 500, 999]

    /// The camera model.
    let model: CameraModel

    /// Runs after Start, such as closing the sheet so the series can be seen.
    let didStart: () -> Void

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - didStart: Runs after Start.
    init(model: CameraModel, didStart: @escaping () -> Void) {
        self.model = model
        self.didStart = didStart
    }

    /// The manual controls model, which holds the series.
    private var manual: ManualControlsModel { model.manual }

    /// The pickers and the button, with the honesty footer.
    var body: some View {
        Section {
            Text("Interval Shooting", bundle: .module, comment: "Section title: a series of photos taken at a fixed interval.")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker(
                selection: Binding(
                    get: { manual.interval.interval },
                    set: { send(.setInterval(IntervalSettings(interval: $0, count: manual.interval.count))) })
            ) {
                ForEach(Self.intervals, id: \.self) { seconds in
                    Text(verbatim: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                        .tag(seconds)
                }
            } label: {
                Text("Interval", bundle: .module, comment: "Picker for the time between photos in interval shooting.")
            }
            Picker(
                selection: Binding(
                    get: { manual.interval.count },
                    set: { send(.setInterval(IntervalSettings(interval: manual.interval.interval, count: $0))) })
            ) {
                ForEach(Self.photoCounts, id: \.self) { count in
                    Text(verbatim: count.formatted()).tag(count)
                }
            } label: {
                Text("Photos", bundle: .module, comment: "Picker for how many photos an interval series takes.")
            }
            if manual.intervalProgress == nil {
                Button {
                    send(.startInterval)
                    didStart()
                } label: {
                    Text("Start", bundle: .module, comment: "Button that starts interval shooting.")
                }
                .disabled(!model.canCapture)
            } else {
                Button(role: .destructive) {
                    send(.stopInterval)
                } label: {
                    Text("Stop", bundle: .module, comment: "Button that stops interval shooting.")
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Each photo is separate. Nothing is combined. Keep nope. open while the series runs.", tableName: "Honesty",
                    bundle: .module,
                    comment: "Explains interval shooting. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English.")
                Text(
                    "Each photo is taken in full auto, or with your manual settings while Manual Controls are on.",
                    bundle: .module,
                    comment: "Explains which exposure the photos of an interval series use. \"Manual Controls\" is the option's name in Settings.")
            }
        }
    }

    /// Sends a manual intent.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: ManualControlIntent) {
        Task { await model.send(.manual(intent)) }
    }
}

/// The Interval sheet, opened from the Drive menu and the Interval pill: the series' interval
/// and photo count, and Start. In the Interval drive mode the shutter starts the series too.
struct IntervalSheet: View {
    /// The camera model.
    let model: CameraModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The form.
    var body: some View {
        NavigationStack {
            Form {
                IntervalSection(model: model) { dismiss() }
                // Done is a row of the form, not a bar button, as in Pro Tools: the audit can't
                // measure the contrast of the glass bar button.
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module, comment: "Button that closes a sheet, such as Settings or Pro Tools.")
                    }
                }
            }
            .navigationTitle(Text("Interval Shooting", bundle: .module, comment: "Section title: a series of photos taken at a fixed interval."))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
