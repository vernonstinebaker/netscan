import Foundation
import SwiftData

@Model
final class PersistentDevice {
    @Attribute(.unique) var id: String // MAC Address or IP Address
    var ipAddress: String
    var macAddress: String?
    var hostname: String?
    var vendor: String?
    var deviceType: String?
    var firstSeen: Date
    var lastSeen: Date
    
    init(id: String, ipAddress: String, macAddress: String? = nil, hostname: String? = nil, vendor: String? = nil, deviceType: String? = nil, firstSeen: Date, lastSeen: Date) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}
