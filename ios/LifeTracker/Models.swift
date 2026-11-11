import Foundation
import Security

struct TrackerSettings: Codable {
    var serverURL = ""
    var deviceID = UUID().uuidString.lowercased()
    var homeSSID = ""
    var excludedSSIDs = ""
    var locationMinutes = 10
    var preferredInputUID = ""
}

enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

struct TrackerEvent: Codable {
    var event_id: String = UUID().uuidString.lowercased()
    var device_id: String
    var kind: String
    var recorded_at: String = ISO8601DateFormatter().string(from: Date())
    var payload: [String: JSONValue]
}

struct AudioSegment: Codable, Identifiable {
    var id = UUID().uuidString.lowercased()
    var deviceID: String
    var startedAt = ISO8601DateFormatter().string(from: Date())
    var finished = false
}

enum TrackerFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum TokenStore {
    static let service = "local.euoom.lifetracker"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server-token",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server-token"]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw TrackerFailure.message("토큰을 Keychain에 저장하지 못했습니다.")
            }
        } else if status != errSecSuccess {
            throw TrackerFailure.message("토큰 갱신 실패: \(status)")
        }
    }
}
