import ActivityKit
import AVFoundation
import Combine
import CoreLocation
import Foundation

@MainActor
final class TrackerStore: NSObject, ObservableObject, CLLocationManagerDelegate, AVAudioRecorderDelegate {
    static let shared = TrackerStore()
    @Published var settings = TrackerSettings()
    @Published var token = TokenStore.read()
    @Published var isRecording = false
    @Published var isTracking = false
    @Published var pendingCount = 0
    @Published var lastMessage = "설정을 입력하고 권한을 허용한 뒤 시작하세요."
    @Published var inputs: [AVAudioSessionPortDescription] = []
    let root: URL
    private let location = CLLocationManager()
    private var recorder: AVAudioRecorder?
    private var segment: AudioSegment?
    private var rotation: Timer?
    private var lastLocationDate: Date?
    private var activity: Activity<RecordingActivity>?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LifeTracker", isDirectory: true)
        super.init()
        do {
            for folder in ["events", "audio", "receipts"] {
                let directory = root.appendingPathComponent(folder)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            }
            let settingsURL = root.appendingPathComponent("settings.json")
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                settings = try JSONDecoder().decode(TrackerSettings.self, from: Data(contentsOf: settingsURL))
            } else {
                try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
            }
            // Incomplete segments are preserved for manual inspection, never silently uploaded.
            let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("audio"), includingPropertiesForKeys: nil)
            if files.contains(where: { $0.pathExtension == "json" && ((try? JSONDecoder().decode(AudioSegment.self, from: Data(contentsOf: $0)))?.finished == false) }) {
                lastMessage = "이전 실행의 미완료 녹음이 있습니다. 원본은 보관되어 있습니다."
            }
        } catch { lastMessage = error.localizedDescription }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        location.distanceFilter = kCLDistanceFilterNone
        location.pausesLocationUpdatesAutomatically = true
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            Task { @MainActor in
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self?.stopRecording()
                    self?.lastMessage = "전화 또는 다른 오디오로 녹음이 중단됐습니다. 다시 시작해 주세요."
                }
            }
        }
        refreshPending()
    }

    func saveSettings() throws {
        guard [5, 10].contains(settings.locationMinutes) else { throw TrackerFailure.message("위치 간격은 5분 또는 10분입니다.") }
        try TokenStore.write(token)
        try JSONEncoder().encode(settings).write(to: root.appendingPathComponent("settings.json"), options: .atomic)
        lastMessage = "설정을 저장했습니다."
    }

    func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        location.requestWhenInUseAuthorization()
    }

    func requestAlwaysLocation() { location.requestAlwaysAuthorization() }

    func startRecording() throws {
        guard !isRecording else { return }
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            throw TrackerFailure.message("앱에서 마이크 권한을 먼저 허용하세요.")
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw TrackerFailure.message("녹음 상태 표시를 위해 Live Activities를 허용하세요.")
        }
        for previous in Activity<RecordingActivity>.activities {
            Task { await previous.end(nil, dismissalPolicy: .immediate) }
        }
        activity = try Activity.request(attributes: RecordingActivity(sessionID: UUID().uuidString),
            content: ActivityContent(state: RecordingActivity.ContentState(startedAt: Date()), staleDate: nil))
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
            inputs = session.availableInputs ?? []
            if !settings.preferredInputUID.isEmpty {
                guard let selected = inputs.first(where: { $0.uid == settings.preferredInputUID }) else {
                    throw TrackerFailure.message("선택한 마이크가 연결되어 있지 않습니다.")
                }
                try session.setPreferredInput(selected)
            }
            try beginSegment()
            isRecording = true
            rotation = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.rotateSegment() }
            }
            lastMessage = "녹음 시작. 실제 입력: \(session.currentRoute.inputs.map(\.portName).joined(separator: ", "))"
            try enqueue(kind: "recording", payload: ["state": .string("started")])
        } catch {
            stopRecording()
            throw error
        }
    }

    private func beginSegment() throws {
        let next = AudioSegment(deviceID: settings.deviceID)
        try writeSegment(next)
        let url = root.appendingPathComponent("audio/\(next.id).m4a")
        let nextRecorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ])
        nextRecorder.delegate = self
        guard nextRecorder.record() else { throw TrackerFailure.message("녹음을 시작할 수 없습니다.") }
        segment = next
        recorder = nextRecorder
    }

    private func writeSegment(_ value: AudioSegment) throws {
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("audio/\(value.id).json"), options: .atomic)
    }

    private func finishSegment() {
        recorder?.stop()
        recorder = nil
        if var value = segment {
            value.finished = true
            do { try writeSegment(value) } catch { lastMessage = error.localizedDescription }
        }
        segment = nil
        refreshPending()
    }

    private func rotateSegment() {
        guard isRecording else { return }
        finishSegment()
        do { try beginSegment() }
        catch { stopRecording(); lastMessage = error.localizedDescription }
    }

    func stopRecording() {
        rotation?.invalidate()
        rotation = nil
        let wasRecording = isRecording
        isRecording = false
        finishSegment()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let activity { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        activity = nil
        if wasRecording {
            do { try enqueue(kind: "recording", payload: ["state": .string("stopped")]) }
            catch { lastMessage = error.localizedDescription }
        }
    }

    func startLocation() throws {
        guard [.authorizedAlways, .authorizedWhenInUse].contains(location.authorizationStatus) else {
            throw TrackerFailure.message("앱에서 위치 권한을 먼저 허용하세요.")
        }
        guard !isTracking else { return }
        lastLocationDate = nil
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
        location.startUpdatingLocation()
        isTracking = true
    }

    func stopLocation() {
        location.stopUpdatingLocation()
        isTracking = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking, let value = locations.last, value.horizontalAccuracy >= 0,
              abs(value.timestamp.timeIntervalSinceNow) < 120 else { return }
        if let previous = lastLocationDate,
           value.timestamp.timeIntervalSince(previous) < Double(settings.locationMinutes * 60) { return }
        do {
            try enqueue(kind: "location", payload: ["latitude": .number(value.coordinate.latitude),
                "longitude": .number(value.coordinate.longitude), "accuracy_meters": .number(value.horizontalAccuracy)],
                date: value.timestamp)
            lastLocationDate = value.timestamp
        } catch { lastMessage = error.localizedDescription }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { lastMessage = error.localizedDescription }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.denied, .restricted].contains(manager.authorizationStatus) { stopLocation() }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        // Keep damaged segment metadata unfinished so synchronization excludes it.
        segment = nil
        stopRecording()
        lastMessage = error?.localizedDescription ?? "녹음 인코딩 오류"
    }

    func recordMessage(text: String, sender: String) throws {
        try enqueue(kind: "message", payload: ["text": .string(text), "sender": .string(sender),
            "source": .string("shortcuts"), "timestamp_source": .string("app_received")])
        lastMessage = "메시지를 기기에 저장했습니다."
    }

    func enqueue(kind: String, payload: [String: JSONValue], date: Date = Date()) throws {
        var event = TrackerEvent(device_id: settings.deviceID, kind: kind, payload: payload)
        event.recorded_at = ISO8601DateFormatter().string(from: date)
        try JSONEncoder().encode(event).write(to: root.appendingPathComponent("events/\(event.event_id).json"), options: .atomic)
        refreshPending()
    }

    func refreshPending() {
        let events = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("events"), includingPropertiesForKeys: nil)) ?? []
        let audio = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("audio"), includingPropertiesForKeys: nil)) ?? []
        let readyAudio = audio.filter { $0.pathExtension == "json" && ((try? JSONDecoder().decode(AudioSegment.self, from: Data(contentsOf: $0)))?.finished == true) }
        pendingCount = (events + readyAudio).filter { !FileManager.default.fileExists(atPath: receiptURL($0.deletingPathExtension().lastPathComponent).path) }.count
    }

    func receiptURL(_ identifier: String) -> URL { root.appendingPathComponent("receipts/\(identifier).json") }
}
