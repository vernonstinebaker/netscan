import Foundation

public struct DeviceSnapshot: Codable, Sendable, Hashable {
    public let id: String
    public var ip: String
    public var mac: String?
    public var hostname: String?
    public var vendor: String?
    public var deviceType: String?
    public var name: String?
    public var firstSeen: Date
    public var lastSeen: Date
    public var services: [NetworkService]
}

public enum DeviceKVStore {
    private static let rootPrefix = "netscan"

    public static func networkKey(info: NetworkInfo) -> String {
        // Use IPv4 network CIDR as a stable key
        return "\(rootPrefix):net:\(info.network)/\(info.cidr)"
    }

    public static func loadSnapshots(for key: String) -> [DeviceSnapshot] {
        let store = NSUbiquitousKeyValueStore.default
        guard let data = store.data(forKey: key) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([DeviceSnapshot].self, from: data)
        } catch {
            return []
        }
    }

    public static func saveSnapshots(_ snapshots: [DeviceSnapshot], for key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) {
            let store = NSUbiquitousKeyValueStore.default
            store.set(data, forKey: key)
            store.synchronize()
        }
    }
}
