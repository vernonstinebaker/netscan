
import Foundation
import SwiftData

@Model
final class PersistentDevice {
	@Attribute(.unique) var id: String
	var ipAddress: String
	var hostname: String?
	var macAddress: String?
	var vendor: String?
	var deviceType: String?
	var firstSeen: Date
	var lastSeen: Date

	init(id: String, ipAddress: String, macAddress: String? = nil, vendor: String? = nil, deviceType: String? = nil, hostname: String? = nil, firstSeen: Date = Date(), lastSeen: Date = Date()) {
		self.id = id
		self.ipAddress = ipAddress
		self.macAddress = macAddress
		self.vendor = vendor
		self.deviceType = deviceType
		self.hostname = hostname
		self.firstSeen = firstSeen
		self.lastSeen = lastSeen
	}
}
