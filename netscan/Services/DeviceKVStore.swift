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
    public var discoverySource: String?
}

public enum DeviceKVStore {
    private static let rootPrefix = "netscan"

    public static func networkKey(info: NetworkInfo) -> String {
        // Use IPv4 network CIDR as a stable key
        return "\(rootPrefix):net:\(info.network)/\(info.cidr)"
    }

    public static func loadSnapshots(for key: String) -> [DeviceSnapshot] {
        let store = UserDefaults.standard
        guard let data = store.data(forKey: key) else {
            print("[DeviceKVStore] No data found for key: \(key)")
            return []
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshots = try decoder.decode([DeviceSnapshot].self, from: data)
            print("[DeviceKVStore] Loaded \(snapshots.count) snapshots for key: \(key)")
            for snap in snapshots {
                print("[DeviceKVStore] Loaded device: \(snap.ip) discoverySource: \(snap.discoverySource ?? "nil")")
            }
            return snapshots
        } catch {
            print("[DeviceKVStore] Failed to decode snapshots: \(error)")
            return []
        }
    }

    public static func saveSnapshots(_ snapshots: [DeviceSnapshot], for key: String) {
        let store = UserDefaults.standard
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) {
            print("[DeviceKVStore] Saving \(snapshots.count) snapshots for key: \(key)")
            for snap in snapshots {
                print("[DeviceKVStore] Saving device: \(snap.ip) discoverySource: \(snap.discoverySource ?? "nil")")
            }
            store.set(data, forKey: key)
            store.synchronize()
            print("[DeviceKVStore] Snapshots saved successfully")
        } else {
            print("[DeviceKVStore] Failed to encode snapshots")
        }
    }

    public static func clearAll() {
        let store = UserDefaults.standard
        let allKeys = store.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix(DeviceKVStore.rootPrefix) {
                store.removeObject(forKey: key)
            }
        }
        store.synchronize()
    }
}
