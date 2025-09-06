import Foundation

public struct Device: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var ipAddress: String
    public var discoverySource: DiscoverySource
    public let rttMillis: Double?
    public var hostname: String?
    public var macAddress: String?
    public var deviceType: DeviceType
    public var manufacturer: String?
    public var isOnline: Bool
    public var services: [NetworkService]
    public var firstSeen: Date?
    public var lastSeen: Date?
    public var openPorts: [Port]
    public var confidence: Double?
    public var fingerprints: [String: String]?

    public init(
        id: String,
        name: String,
        ipAddress: String,
    discoverySource: DiscoverySource = .unknown,
        rttMillis: Double?,
        hostname: String? = nil,
        macAddress: String? = nil,
        deviceType: DeviceType = .unknown,
        manufacturer: String? = nil,
        isOnline: Bool = true,
        services: [NetworkService] = [],
        firstSeen: Date? = nil,
        lastSeen: Date? = nil,
        openPorts: [Port] = [],
        confidence: Double? = nil,
        fingerprints: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
    self.discoverySource = discoverySource
        self.rttMillis = rttMillis
        self.hostname = hostname
        self.macAddress = macAddress
        self.deviceType = deviceType
        self.manufacturer = manufacturer
        self.isOnline = isOnline
        self.services = services
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.openPorts = openPorts
        self.confidence = confidence
        self.fingerprints = fingerprints
    }

    // Return services deduplicated by type (and prefer longer/more descriptive names)
    public var uniqueServices: [NetworkService] {
        var map: [ServiceType: NetworkService] = [:]
        for svc in services {
            if let existing = map[svc.type] {
                if svc.name.count > existing.name.count {
                    map[svc.type] = svc
                }
            } else {
                map[svc.type] = svc
            }
        }
        return Array(map.values)
    }

    // A canonical list of services to display in the UI.
    // Combines deduped discovery services with port-derived services and returns a deterministic order.
    public var displayServices: [NetworkService] {
        // Map openPorts to network services (well-known ports only)
        let portDerived: [NetworkService] = openPorts.map { port in
            let t = ServiceMapper.type(forPort: port.number)
            return NetworkService(name: port.serviceName, type: t, port: port.number)
        }.filter { $0.type != .unknown }

        // Merge discovery services and port-derived services; dedupe by (type, port)
        var map: [String: NetworkService] = [:]
        for svc in services + portDerived {
            let key = "\(svc.type.rawValue)-\(svc.port ?? -1)"
            if let existing = map[key] {
                // prefer the one with longer name
                if svc.name.count > existing.name.count { map[key] = svc }
            } else {
                map[key] = svc
            }
        }

        // Return a deterministic, sorted array by type then port
        return Array(map.values).sorted { a, b in
            if a.type == b.type { return (a.port ?? 0) < (b.port ?? 0) }
            return a.type.rawValue < b.type.rawValue
        }
    }

    public init(ip: String, rttMillis: Double?, openPorts: [Port] = []) {
        self.init(
            id: ip,
            name: ip,
            ipAddress: ip,
            rttMillis: rttMillis,
            openPorts: openPorts
        )
    }
}

public enum DeviceType: String, CaseIterable, Sendable {
    case router = "router"
    case computer = "computer"
    case laptop = "laptop"
    case tv = "tv"
    case printer = "printer"
    case gameConsole = "gameConsole"
    case playstation = "playstation"
    case phone = "phone"
    case tablet = "tablet"
    case unknown = "unknown"
    
    var systemImage: String {
        switch self {
        case .router: return "wifi.router"
        case .computer: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .tv: return "tv"
        case .printer: return "printer"
        case .gameConsole: return "gamecontroller"
        case .playstation: return "gamecontroller.fill"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .unknown: return "questionmark.circle"
        }
    }
}

public enum DiscoverySource: String, Sendable {
    case mdns = "mDNS"
    case arp = "ARP"
    case nio = "NIO"
    case ping = "Ping"
    case ssdp = "SSDP"
    case unknown = "?"
}

public struct NetworkService: Identifiable, Hashable, Sendable, Codable {
    public var id = UUID()
    public let name: String
    public let type: ServiceType
    public let port: Int?
    
    public init(name: String, type: ServiceType, port: Int? = nil) {
        self.name = name
        self.type = type
        self.port = port
    }
}

public enum ServiceType: String, CaseIterable, Sendable, Codable {
    case http = "HTTP"
    case https = "HTTPS"
    case ssh = "SSH"
    case dns = "DNS"
    case dhcp = "DHCP"
    case smb = "SMB"
    case chromecast = "Chromecast"
    case ssdp = "SSDP"
    case mdns = "mDNS"
    case unknown = "Unknown"
}

public struct Port: Identifiable, Hashable, Sendable, Codable {
    public var id = UUID()
    public let number: Int
    public let serviceName: String
    public let description: String
    public let status: Status

    public enum Status: String, Sendable, Codable {
        case open, closed, filtered
    }
    
    public init(number: Int, serviceName: String, description: String, status: Status) {
        self.number = number
        self.serviceName = serviceName
        self.description = description
        self.status = status
    }
}

// MARK: - Mock Data
public extension Device {
    static var mock: Device {
        Device(
            id: "27:98:F4:DE:36:1F",
            name: "Home Router",
            ipAddress: "192.168.1.1",
            rttMillis: 2.5,
            hostname: "router.local",
            macAddress: "27:98:F4:DE:36:1F",
            deviceType: .router,
            manufacturer: "Netgear",
            isOnline: true,
            services: [
                NetworkService(name: "HTTP", type: .http),
                NetworkService(name: "HTTPS", type: .https),
                NetworkService(name: "SSH", type: .ssh),
                NetworkService(name: "DNS", type: .dns),
                NetworkService(name: "DHCP", type: .dhcp)
            ],
            firstSeen: Date(timeIntervalSince1970: 1704096000),
            lastSeen: Date(timeIntervalSince1970: 1725357745),
            openPorts: [
                Port(number: 22, serviceName: "SSH", description: "Secure Shell", status: .open),
                Port(number: 80, serviceName: "HTTP", description: "Web Server", status: .open),
                Port(number: 443, serviceName: "HTTPS", description: "Secure Web Server", status: .open)
            ],
            confidence: 0.9,
            fingerprints: ["http_ports": "80", "https_ports": "443", "ssh_present": "true"]
        )
    }
    
    static var mocks: [Device] {
        [
            .mock,
            Device(id: "63:35:6D:E1:E5:9B", name: "Living Room TV", ipAddress: "192.168.1.192", rttMillis: 15.2, macAddress: "63:35:6D:E1:E5:9B", deviceType: .tv, manufacturer: "Chromecast"),
            Device(id: "EA:03:1E:93:C9:4B", name: "Smart Printer", ipAddress: "192.168.1.195", rttMillis: 25.0, macAddress: "EA:03:1E:93:C9:4B", deviceType: .printer, manufacturer: "HP"),
            Device(id: "F0:72:76:EC:7A:94", name: "Playstation 5", ipAddress: "192.168.1.28", rttMillis: 5.1, macAddress: "F0:72:76:EC:7A:94", deviceType: .playstation, manufacturer: "Sony"),
            Device(id: "FB:CD:78:D0:97:A5", name: "Work Laptop", ipAddress: "192.168.1.32", rttMillis: 1.2, macAddress: "FB:CD:78:D0:97:A5", deviceType: .laptop, manufacturer: "Apple")
        ]
    }
}
