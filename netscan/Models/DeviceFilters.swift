import Foundation

public struct DeviceFilterOptions: Sendable, Equatable {
    public var searchText: String = ""
    public var onlineOnly: Bool = false
    public var deviceType: DeviceType? = nil
    public var source: DiscoverySource? = nil

    public init(searchText: String = "", onlineOnly: Bool = false, deviceType: DeviceType? = nil, source: DiscoverySource? = nil) {
        self.searchText = searchText
        self.onlineOnly = onlineOnly
        self.deviceType = deviceType
        self.source = source
    }

    public func apply(to devices: [Device]) -> [Device] {
        var list = devices
        if onlineOnly { list = list.filter { $0.isOnline } }
        if let t = deviceType { list = list.filter { $0.deviceType == t } }
        if let s = source { list = list.filter { $0.discoverySource == s } }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let lower = q.lowercased()
            list = list.filter { d in
                if d.name.lowercased().contains(lower) { return true }
                if d.ipAddress.lowercased().contains(lower) { return true }
                if (d.manufacturer ?? "").lowercased().contains(lower) { return true }
                if (d.hostname ?? "").lowercased().contains(lower) { return true }
                if (d.macAddress ?? "").lowercased().contains(lower) { return true }
                if d.displayServices.contains(where: { $0.type.rawValue.lowercased().contains(lower) || $0.name.lowercased().contains(lower) || (String($0.port ?? -1).contains(lower) && $0.port != nil) }) { return true }
                return false
            }
        }
        return list
    }
}

