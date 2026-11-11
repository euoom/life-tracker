import CallKit
import Foundation

final class CallMonitor: NSObject, CXCallObserverDelegate {
    static let shared = CallMonitor()
    private let observer = CXCallObserver()
    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }
    func start() { _ = observer.calls }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let payload: [String: JSONValue] = ["call_id": .string(call.uuid.uuidString.lowercased()),
            "outgoing": .bool(call.isOutgoing), "connected": .bool(call.hasConnected),
            "ended": .bool(call.hasEnded), "on_hold": .bool(call.isOnHold)]
        Task { @MainActor in
            do { try TrackerStore.shared.enqueue(kind: "call", payload: payload) }
            catch { TrackerStore.shared.lastMessage = error.localizedDescription }
        }
    }
}
