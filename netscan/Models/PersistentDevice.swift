import Foundation

final class PersistentDevice {
    var id: String
    var ipAddress: String
    var macAddress: String?
    var vendor: String?
    var deviceType: String?
    var firstSeen: Date
    var lastSeen: Date
    var hostname: String?

    init(id: String, ipAddress: String, macAddress: String?, vendor: String?, deviceType: String?, firstSeen: Date, lastSeen: Date, hostname: String? = nil) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.vendor = vendor
        self.deviceType = deviceType
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.hostname = hostname
    }
}
