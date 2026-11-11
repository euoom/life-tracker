import ActivityKit
import Foundation

struct RecordingActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }
    var sessionID: String
}
