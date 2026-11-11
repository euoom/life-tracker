import AppIntents

struct StartRecordingIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "녹음 시작"
    // First prototype opens the app; locked unattended invocation must be tested on device.
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        try TrackerStore.shared.startRecording()
        return .result()
    }
}

struct StopRecordingIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "녹음 종료"
    @MainActor func perform() async throws -> some IntentResult {
        TrackerStore.shared.stopRecording()
        return .result()
    }
}

struct StartLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "위치 기록 시작"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        try TrackerStore.shared.startLocation()
        return .result()
    }
}

struct StopLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "위치 기록 종료"
    @MainActor func perform() async throws -> some IntentResult {
        TrackerStore.shared.stopLocation()
        return .result()
    }
}

struct SyncIntent: AppIntent {
    static var title: LocalizedStringResource = "PC 동기화"
    @MainActor func perform() async throws -> some IntentResult {
        try await TransferManager.shared.synchronize()
        return .result()
    }
}

struct RecordMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "메시지 기록"
    @Parameter(title: "본문") var text: String
    @Parameter(title: "발신자") var sender: String?
    @MainActor func perform() async throws -> some IntentResult {
        try TrackerStore.shared.recordMessage(text: text, sender: sender ?? "")
        return .result()
    }
}

struct StatusIntent: AppIntent {
    static var title: LocalizedStringResource = "기록 상태 조회"
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = TrackerStore.shared
        store.refreshPending()
        return .result(value: "녹음 \(store.isRecording), 위치 \(store.isTracking), 미전송 \(store.pendingCount)개")
    }
}

struct TrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(), phrases: ["\(.applicationName) 녹음 시작"], shortTitle: "녹음 시작", systemImageName: "mic")
        AppShortcut(intent: StopRecordingIntent(), phrases: ["\(.applicationName) 녹음 종료"], shortTitle: "녹음 종료", systemImageName: "stop.circle")
        AppShortcut(intent: StartLocationIntent(), phrases: ["\(.applicationName) 위치 기록 시작"], shortTitle: "위치 시작", systemImageName: "location")
        AppShortcut(intent: StopLocationIntent(), phrases: ["\(.applicationName) 위치 기록 종료"], shortTitle: "위치 종료", systemImageName: "location.slash")
        AppShortcut(intent: SyncIntent(), phrases: ["\(.applicationName) PC 동기화"], shortTitle: "PC 동기화", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: StatusIntent(), phrases: ["\(.applicationName) 기록 상태"], shortTitle: "기록 상태", systemImageName: "info.circle")
    }
}
