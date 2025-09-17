import Foundation
import CloudKit

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
        // Try ubiquitous (iCloud) store first, then fall back to UserDefaults
        let ubi = NSUbiquitousKeyValueStore.default
        if let obj = ubi.object(forKey: key) {
            if let data = obj as? Data {
                return decodeSnapshots(data: data, source: "iCloud")
            }
            if let str = obj as? String, let data = Data(base64Encoded: str) {
                return decodeSnapshots(data: data, source: "iCloud(base64)")
            }
        }

        let store = UserDefaults.standard
        if let data = store.data(forKey: key) {
            return decodeSnapshots(data: data, source: "UserDefaults")
        }

        print("[DeviceKVStore] No data found for key: \(key)")
        return []
    }

    private static func decodeSnapshots(data: Data, source: String) -> [DeviceSnapshot] {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshots = try decoder.decode([DeviceSnapshot].self, from: data)
            print("[DeviceKVStore] Loaded \(snapshots.count) snapshots for key from \(source)")
            for snap in snapshots {
                print("[DeviceKVStore] Loaded device: \(snap.ip) discoverySource: \(snap.discoverySource ?? "nil")")
            }
            return snapshots
        } catch {
            print("[DeviceKVStore] Failed to decode snapshots from \(source): \(error)")
            return []
        }
    }

    public static func saveSnapshots(_ snapshots: [DeviceSnapshot], for key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else {
            print("[DeviceKVStore] Failed to encode snapshots")
            return
        }

        // Save to UserDefaults
        let store = UserDefaults.standard
        print("[DeviceKVStore] Saving \(snapshots.count) snapshots for key: \(key) to UserDefaults")
        for snap in snapshots {
            print("[DeviceKVStore] Saving device: \(snap.ip) discoverySource: \(snap.discoverySource ?? "nil")")
        }
        store.set(data, forKey: key)
        store.synchronize()

        // Also save to iCloud KVS (if available) for cross-device sync
        let ubi = NSUbiquitousKeyValueStore.default
        ubi.set(data, forKey: key)
        ubi.synchronize()
        print("[DeviceKVStore] Snapshots saved to iCloud and UserDefaults successfully")
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

        let ubi = NSUbiquitousKeyValueStore.default
        for key in ubi.dictionaryRepresentation.keys where key.hasPrefix(DeviceKVStore.rootPrefix) {
            ubi.removeObject(forKey: key)
        }
        ubi.synchronize()
    }
}
