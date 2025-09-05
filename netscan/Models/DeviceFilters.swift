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
    // DEBUG: log incoming devices and filter options when running tests
    #if DEBUG
    print("[DeviceFilterOptions] apply called with onlineOnly=\(onlineOnly), deviceType=\(String(describing: deviceType)), source=\(String(describing: source)), searchText='\(searchText)'")
    print("[DeviceFilterOptions] incoming device ids=\(devices.map { $0.id }) types=\(devices.map { $0.deviceType.rawValue })")
    #endif
        if onlineOnly { list = list.filter { $0.isOnline } }
        if let t = deviceType { list = list.filter { $0.deviceType == t } }
        if let s = source { list = list.filter { $0.discoverySource == s } }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let lower = q.lowercased()
            // If the query looks like an IPv4 address (digits and dots only), do an exact equality
            let isIPAddressQuery = q.range(of: "^[0-9.]+$", options: .regularExpression) != nil
            list = list.filter { d in
                if d.name.lowercased().contains(lower) { return true }
                if isIPAddressQuery {
                    if d.ipAddress == q { return true }
                } else {
                    if d.ipAddress.lowercased().contains(lower) { return true }
                }
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

