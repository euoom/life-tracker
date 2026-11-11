import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        TransferManager.shared.backgroundCompletion = completionHandler
        TransferManager.shared.reconnect()
    }
}

@main
@MainActor
struct LifeTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = TrackerStore.shared
    init() { TransferManager.shared.reconnect(); CallMonitor.shared.start() }
    var body: some Scene { WindowGroup { TrackerView().environmentObject(store) } }
}

@MainActor
struct TrackerView: View {
    @EnvironmentObject var store: TrackerStore
    @State private var syncing = false
    var body: some View {
        NavigationStack {
            Form {
                Section("기록 상태") {
                    LabeledContent("녹음", value: store.isRecording ? "진행 중" : "중지")
                    LabeledContent("위치", value: store.isTracking ? "기록 중" : "중지")
                    LabeledContent("미전송", value: "\(store.pendingCount)개")
                    Text(store.lastMessage).font(.footnote)
                }
                Section("기록 제어") {
                    Button("마이크·위치 권한 요청") { store.requestPermissions() }
                    Button("위치 항상 허용 요청") { store.requestAlwaysLocation() }
                    Button(store.isRecording ? "녹음 종료" : "녹음 시작") {
                        run { if store.isRecording { store.stopRecording() } else { try store.startRecording() } }
                    }
                    Button(store.isTracking ? "위치 종료" : "위치 시작") {
                        run { if store.isTracking { store.stopLocation() } else { try store.startLocation() } }
                    }
                    Button(syncing ? "전송 예약 중" : "PC 동기화") {
                        syncing = true
                        Task { @MainActor in
                            defer { syncing = false }
                            do { try await TransferManager.shared.synchronize() }
                            catch { store.lastMessage = error.localizedDescription }
                        }
                    }.disabled(syncing)
                }
                Section("서버 설정") {
                    TextField("http://PC주소:18765", text: $store.settings.serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("서버 토큰", text: $store.token)
                    Text("전송은 Wi-Fi에서만 진행합니다. PC 원본과 아이폰 원본 모두 자동 삭제하지 않습니다.").font(.footnote)
                }
                Section("단축어 설정용 Wi-Fi 목록") {
                    TextField("집 SSID", text: $store.settings.homeSSID).autocorrectionDisabled()
                    TextField("위치 제외 SSID 목록", text: $store.settings.excludedSSIDs, axis: .vertical).autocorrectionDisabled()
                    Text("이 목록은 참고 설정입니다. Wi-Fi별 자동화는 단축어에서 직접 구성하세요. 회사에서는 위치만 멈추고 녹음은 계속합니다.").font(.footnote)
                }
                Section("수집 설정") {
                    Picker("위치 로그 간격", selection: $store.settings.locationMinutes) {
                        Text("5분").tag(5)
                        Text("10분").tag(10)
                    }
                    Picker("마이크", selection: $store.settings.preferredInputUID) {
                        Text("시스템 기본").tag("")
                        ForEach(store.inputs, id: \.uid) { input in Text(input.portName).tag(input.uid) }
                    }
                    Text("마이크 목록은 녹음 시작 시 갱신됩니다. 변경은 다음 녹음 시작부터 적용됩니다. 위치 간격은 OS 업데이트에 따라 길어질 수 있습니다.").font(.footnote)
                    Button("설정 저장") { run { try store.saveSettings() } }
                }
            }.navigationTitle("Life Tracker")
        }
    }
    private func run(_ action: () throws -> Void) {
        do { try action() } catch { store.lastMessage = error.localizedDescription }
    }
}
