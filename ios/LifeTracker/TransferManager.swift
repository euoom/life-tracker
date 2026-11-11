import CryptoKit
import Foundation

final class TransferManager: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    static let shared = TransferManager()
    var backgroundCompletion: (() -> Void)?
    private var responses: [Int: Data] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "local.euoom.lifetracker.upload")
        configuration.allowsCellularAccess = false
        configuration.waitsForConnectivity = true
        configuration.sessionSendsLaunchEvents = true
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func reconnect() { _ = session }

    @MainActor
    func synchronize() async throws {
        let store = TrackerStore.shared
        try store.saveSettings()
        guard let base = URL(string: store.settings.serverURL),
              ["http", "https"].contains(base.scheme ?? ""), base.host != nil,
              base.user == nil, base.query == nil, base.fragment == nil,
              store.token.count >= 24 else {
            throw TrackerFailure.message("서버 주소와 24자 이상의 토큰을 입력하세요.")
        }
        guard !["localhost", "127.0.0.1", "::1"].contains(base.host?.lowercased() ?? "") else {
            throw TrackerFailure.message("아이폰 localhost 대신 PC의 LAN 또는 VPN 주소를 입력하세요.")
        }
        let tasks = await session.allTasks
        var scheduled = Set(tasks.compactMap(\.taskDescription))
        let eventURLs = try FileManager.default.contentsOfDirectory(at: store.root.appendingPathComponent("events"), includingPropertiesForKeys: nil)
        for file in eventURLs where file.pathExtension == "json" {
            let identifier = file.deletingPathExtension().lastPathComponent
            guard !scheduled.contains(identifier), !FileManager.default.fileExists(atPath: store.receiptURL(identifier).path) else { continue }
            var request = URLRequest(url: base.appendingPathComponent("api/v1/events"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(store.token)", forHTTPHeaderField: "Authorization")
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = identifier
            scheduled.insert(identifier)
            task.resume()
        }
        let audioURLs = try FileManager.default.contentsOfDirectory(at: store.root.appendingPathComponent("audio"), includingPropertiesForKeys: nil)
        for metadata in audioURLs where metadata.pathExtension == "json" {
            let segment = try JSONDecoder().decode(AudioSegment.self, from: Data(contentsOf: metadata))
            guard segment.finished, !scheduled.contains(segment.id), !FileManager.default.fileExists(atPath: store.receiptURL(segment.id).path) else { continue }
            let file = metadata.deletingPathExtension().appendingPathExtension("m4a")
            let handle = try FileHandle(forReadingFrom: file)
            var hasher = SHA256()
            do {
                while let chunk = try handle.read(upToCount: 1048576), !chunk.isEmpty { hasher.update(data: chunk) }
                try handle.close()
            } catch { try? handle.close(); throw error }
            let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            var request = URLRequest(url: base.appendingPathComponent("api/v1/audio/\(segment.id)"))
            request.httpMethod = "PUT"
            request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(store.token)", forHTTPHeaderField: "Authorization")
            request.setValue(segment.deviceID, forHTTPHeaderField: "X-Device-ID")
            request.setValue(segment.startedAt, forHTTPHeaderField: "X-Recorded-At")
            request.setValue(checksum, forHTTPHeaderField: "X-Content-SHA256")
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = segment.id
            scheduled.insert(segment.id)
            task.resume()
        }
        store.lastMessage = "Wi-Fi 전송을 예약했습니다. 원본은 삭제하지 않습니다."
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responses[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let data = responses.removeValue(forKey: task.taskIdentifier) ?? Data()
        let identifier = task.taskDescription ?? ""
        let response = task.response as? HTTPURLResponse
        let receipt = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        var confirmed = error == nil && response.map { (200..<300).contains($0.statusCode) } == true
        confirmed = confirmed && receipt?["stored"] as? Bool == true
        confirmed = confirmed && ((receipt?["event_id"] as? String ?? receipt?["recording_id"] as? String) == identifier)
        if let checksum = task.originalRequest?.value(forHTTPHeaderField: "X-Content-SHA256") {
            confirmed = confirmed && receipt?["sha256"] as? String == checksum
        }
        let success = confirmed
        DispatchQueue.main.async {
            let store = TrackerStore.shared
            do {
                if success {
                    try data.write(to: store.receiptURL(identifier), options: .atomic)
                    store.lastMessage = "PC 수신 확인: \(identifier.prefix(8))"
                } else {
                    store.lastMessage = "전송 미확인. 원본 보관, 동기화로 재시도: \(error?.localizedDescription ?? "HTTP \(response?.statusCode ?? 0)")"
                }
            } catch { store.lastMessage = error.localizedDescription }
            store.refreshPending()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}
