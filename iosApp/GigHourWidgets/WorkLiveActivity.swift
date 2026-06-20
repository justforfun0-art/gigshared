import ActivityKit
import WidgetKit
import SwiftUI

/// The live work-progress Live Activity — Lock Screen banner + Dynamic Island
/// (compact / minimal / expanded). Renders a live timer (relative to
/// `startedAt`) and the earned-so-far. iOS equivalent of Android's WORKING
/// notification + status-bar chip.
@available(iOS 16.1, *)
struct WorkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.20, green: 0.13, blue: 0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Working", systemImage: "timer").font(.caption).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(earned(context)).font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.jobTitle).font(.caption2).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    timer(context).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.green)
            } compactTrailing: {
                timer(context).font(.caption2.monospacedDigit()).foregroundStyle(.white)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }

    @ViewBuilder
    private func timer(_ context: ActivityViewContext<WorkActivityAttributes>) -> some View {
        // A self-updating relative timer from the shift start — no push needed.
        Text(context.attributes.startedAt, style: .timer)
    }

    private func earned(_ context: ActivityViewContext<WorkActivityAttributes>) -> String {
        "₹" + String(format: "%.0f", context.state.earned)
    }
}

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<WorkActivityAttributes>
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.jobTitle).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white).lineLimit(1)
                Text(context.attributes.startedAt, style: .timer)
                    .font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Earned").font(.caption2).foregroundStyle(.white.opacity(0.8))
                Text("₹" + String(format: "%.2f", context.state.earned))
                    .font(.headline.monospacedDigit()).foregroundStyle(.green)
            }
        }
        .padding()
    }
}
