import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TrackerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivity.self) { context in
            HStack {
                Image(systemName: "mic.fill").foregroundStyle(.red)
                Text("Life Tracker 녹음 중")
                Spacer()
                Text(context.state.startedAt, style: .timer)
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("녹음 중") }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.startedAt, style: .timer) }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundStyle(.red)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
            } minimal: {
                Image(systemName: "mic.fill")
            }
        }
    }
}
