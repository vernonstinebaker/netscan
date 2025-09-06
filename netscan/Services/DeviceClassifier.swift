import Foundation

public actor DeviceClassifier {
    public init() {}

    /// Classifies a device type based on its properties.
    /// The order of checks is important: hostname is often most specific, followed by vendor, then open ports.
    public func classify(hostname: String?, vendor: String?, openPorts: [Port]) -> DeviceType {
        // Rule 1: Check hostname for explicit clues
        if let hostname = hostname?.lowercased() {
            if hostname.contains("router") || hostname.contains("gateway") { return .router }
            if hostname.contains("tv") || hostname.contains("chromecast") { return .tv }
            if hostname.contains("printer") { return .printer }
            if hostname.contains("playstation") || hostname.contains("ps4") || hostname.contains("ps5") { return .playstation }
            if hostname.contains("xbox") { return .gameConsole }
            if hostname.contains("nintendo") || hostname.contains("switch") { return .gameConsole }
            if hostname.contains("laptop") || hostname.contains("macbook") { return .laptop }
            if hostname.contains("desktop") { return .computer }
            if hostname.contains("phone") || hostname.contains("iphone") || hostname.contains("android") { return .phone }
            if hostname.contains("ipad") { return .tablet }
            if hostname.contains("raspberrypi") || hostname.contains("raspberry") { return .computer }
            if hostname.contains("synology") || hostname.contains("qnap") || hostname.contains("nas") { return .computer }
            if hostname.contains("roku") { return .tv }
            if hostname.contains("nvr") || hostname.contains("dvr") || hostname.contains("hikvision") || hostname.contains("camera") { return .computer }
            if hostname.contains("appletv") || hostname.contains("apple-tv") { return .tv }
            if hostname.contains("firetv") || hostname.contains("fire-tv") { return .tv }
            if hostname.contains("sonos") { return .tv }
            if hostname.contains("fritz") { return .router }
            if hostname.contains("unifi") || hostname.contains("ubnt") { return .router }
        }

        // Rule 2: Check vendor name for strong clues
        if let vendor = vendor?.lowercased() {
            if vendor.contains("netgear") || vendor.contains("tp-link") || vendor.contains("linksys") || vendor.contains("asus") { return .router }
            if vendor.contains("mikrotik") || vendor.contains("zyxel") || vendor.contains("huawei") || vendor.contains("fritz") || vendor.contains("eero") { return .router }
            if vendor.contains("ubiquiti") || vendor.contains("unifi") || vendor.contains("ubnt") { return .router }
            if vendor.contains("sony") { return .playstation }
            if vendor.contains("hp") || vendor.contains("brother") || vendor.contains("epson") || vendor.contains("canon") || vendor.contains("kyocera") || vendor.contains("xerox") || vendor.contains("ricoh") || vendor.contains("lexmark") || vendor.contains("sharp") || vendor.contains("konica") { return .printer }
            if vendor.contains("google") || vendor.contains("chromecast") { return .tv }
            if vendor.contains("samsung") || vendor.contains("lg") || vendor.contains("vizio") { return .tv }
            if vendor.contains("roku") || vendor.contains("philips hue") || vendor.contains("hue") || vendor.contains("sonos") || vendor.contains("amazon") { return .tv }
            if vendor.contains("synology") || vendor.contains("qnap") { return .computer }
            if vendor.contains("microsoft") || vendor.contains("dell") || vendor.contains("lenovo") || vendor.contains("hp inc") { return .computer }
            if vendor.contains("rok u") { return .tv }
            if vendor.contains("hikvision") || vendor.contains("dahua") || vendor.contains("reolink") { return .computer }
            if vendor.contains("tplinkwifi") { return .router }
            if vendor.contains("apple") { return .laptop }
        }

        // Rule 3: Check open ports for common signatures
        let portNumbers = Set(openPorts.map { $0.number })
        if portNumbers.contains(53) || portNumbers.contains(67) { return .router }
        if portNumbers.contains(631) || portNumbers.contains(9100) { return .printer }
        if portNumbers.contains(8008) || portNumbers.contains(8009) { return .tv }
        if portNumbers.contains(5000) || portNumbers.contains(5001) { return .computer }
        if portNumbers.contains(445) { return .computer }

        return .unknown
    }

    /// Classify with a simple confidence score (0.0-1.0).
    public func classifyWithConfidence(hostname: String?, vendor: String?, openPorts: [Port]) async -> (DeviceType, Double) {
        let type = classify(hostname: hostname, vendor: vendor, openPorts: openPorts)
        var score: Double = 0.0
        if let hn = hostname?.lowercased(), !hn.isEmpty {
            if type != .unknown { score = max(score, 0.8) }
            else { score = max(score, 0.3) }
        }
        if let v = vendor?.lowercased(), !v.isEmpty {
            if type != .unknown { score = max(score, 0.6) }
            else { score = max(score, 0.25) }
        }
        let portNumbers = Set(openPorts.map { $0.number })
        if !portNumbers.isEmpty {
            if type != .unknown { score = max(score, 0.5) }
            else { score = max(score, 0.2) }
        }
        if score == 0.0 { score = type == .unknown ? 0.0 : 0.4 }
        return (type, score)
    }

    /// Overload that accepts services as additional evidence. Delegates to the existing classifier and computes confidence.
    public func classifyWithConfidence(hostname: String?, vendor: String?, openPorts: [Port], services: [NetworkService]) async -> (DeviceType, Double) {
        var combinedPorts = openPorts
        for svc in services {
            if let p = svc.port {
                if !combinedPorts.contains(where: { $0.number == p }) {
                    combinedPorts.append(Port(number: p, serviceName: svc.name, description: svc.name, status: .open))
                }
            }
        }
        return await classifyWithConfidence(hostname: hostname, vendor: vendor, openPorts: combinedPorts)
    }

    /// Fingerprint services -> simple map of service name to a short signature used by UI.
    public func fingerprintServices(services: [NetworkService], openPorts: [Port]) async -> [String: String] {
        var map: [String: String] = [:]
        for svc in services {
            if let p = svc.port {
                map[svc.name] = "port:\(p)"
            } else {
                map[svc.name] = "service"
            }
        }
        for p in openPorts where map["port:\(p.number)"] == nil {
            map["port:\(p.number)"] = "open"
        }
        return map
    }
}
