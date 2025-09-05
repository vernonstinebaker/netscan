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
            if vendor.contains("sony") { return .playstation } // Could also be a TV, but console is a good guess
            if vendor.contains("hp") || vendor.contains("brother") || vendor.contains("epson") || vendor.contains("canon") || vendor.contains("kyocera") || vendor.contains("xerox") || vendor.contains("ricoh") || vendor.contains("lexmark") || vendor.contains("sharp") || vendor.contains("konica") { return .printer }
            if vendor.contains("google") || vendor.contains("chromecast") { return .tv }
            if vendor.contains("samsung") || vendor.contains("lg") || vendor.contains("vizio") { return .tv }
            if vendor.contains("roku") || vendor.contains("philips hue") || vendor.contains("hue") || vendor.contains("sonos") || vendor.contains("amazon") { return .tv }
            if vendor.contains("synology") || vendor.contains("qnap") { return .computer } // NAS as computer
            if vendor.contains("microsoft") || vendor.contains("dell") || vendor.contains("lenovo") || vendor.contains("hp inc") { return .computer }
            if vendor.contains("roku") { return .tv }
            if vendor.contains("hikvision") || vendor.contains("dahua") || vendor.contains("reolink") { return .computer }
            if vendor.contains("tplinkwifi") { return .router }
            if vendor.contains("apple") { return .laptop } // Default to laptop for Apple devices
        }
        
        // Rule 3: Check open ports for common signatures
        let portNumbers = Set(openPorts.map { $0.number })
        // Media servers / TVs
        if portNumbers.contains(32400) || portNumbers.contains(8200) { return .tv } // Plex, DLNA
        if portNumbers.contains(53) || portNumbers.contains(67) { return .router } // DNS, DHCP
        if portNumbers.contains(631) || portNumbers.contains(9100) { return .printer } // IPP, JetDirect
        if portNumbers.contains(8008) || portNumbers.contains(8009) { return .tv } // Google Cast
        if portNumbers.contains(5000) || portNumbers.contains(5001) { return .computer } // Synology DSM ports
        if portNumbers.contains(445) { return .computer } // SMB, likely a desktop/laptop
        
        return .unknown
    }
    
    /// Enhanced classification with confidence scoring
    public func classifyWithConfidence(hostname: String?, vendor: String?, openPorts: [Port], services: [NetworkService]) -> (DeviceType, Double) {
        let baseClassification = classify(hostname: hostname, vendor: vendor, openPorts: openPorts)
        
        // Calculate confidence based on evidence strength
        var confidence = 0.0
        var evidenceCount = 0
        
        if hostname != nil && hostname!.contains(baseClassification.rawValue.lowercased()) {
            confidence += 0.4
            evidenceCount += 1
        }
        
        if vendor != nil {
            let vendorLower = vendor!.lowercased()
            switch baseClassification {
            case .router:
                if ["netgear", "tp-link", "linksys", "asus", "cisco"].contains(where: vendorLower.contains) {
                    confidence += 0.3
                    evidenceCount += 1
                }
            case .printer:
                if ["hp", "brother", "epson", "canon"].contains(where: vendorLower.contains) {
                    confidence += 0.3
                    evidenceCount += 1
                }
            case .tv:
                if ["samsung", "lg", "sony", "vizio"].contains(where: vendorLower.contains) {
                    confidence += 0.3
                    evidenceCount += 1
                }
            default:
                break
            }
        }
        
        // Port-based confidence
        let portNumbers = Set(openPorts.map { $0.number })
        switch baseClassification {
        case .router:
            if portNumbers.contains(53) || portNumbers.contains(67) {
                confidence += 0.2
                evidenceCount += 1
            }
        case .printer:
            if portNumbers.contains(631) || portNumbers.contains(9100) {
                confidence += 0.2
                evidenceCount += 1
            }
        case .tv:
            if portNumbers.contains(8008) || portNumbers.contains(8009) || portNumbers.contains(32400) || portNumbers.contains(8200) {
                confidence += 0.2
                evidenceCount += 1
            }
        default:
            break
        }
        
        // Service-based confidence
        let serviceTypes = Set(services.map { $0.type })
        if serviceTypes.contains(.dhcp) || serviceTypes.contains(.dns) {
            if baseClassification == .router { confidence += 0.1 }
        }
        
        // Normalize confidence
        if evidenceCount > 0 {
            confidence = min(confidence, 1.0)
        } else {
            confidence = 0.1 // Low confidence for unknown devices
        }
        
        return (baseClassification, confidence)
    }
    
    /// Advanced service fingerprinting for better device identification
    public func fingerprintServices(services: [NetworkService], openPorts: [Port]) -> [String: String] {
        var fingerprints: [String: String] = [:]
        
        // HTTP fingerprinting
        if services.contains(where: { $0.type == .http }) {
            fingerprints["http_ports"] = openPorts.filter { $0.number == 80 }.map { String($0.number) }.joined(separator: ",")
        }
        
        // HTTPS fingerprinting
        if services.contains(where: { $0.type == .https }) {
            fingerprints["https_ports"] = openPorts.filter { $0.number == 443 }.map { String($0.number) }.joined(separator: ",")
        }
        
        // SMB detection
        if services.contains(where: { $0.type == .smb }) {
            fingerprints["smb_present"] = "true"
        }
        
        // SSH detection
        if services.contains(where: { $0.type == .ssh }) {
            fingerprints["ssh_present"] = "true"
        }
        
        // Media fingerprints (Plex/DLNA)
        if openPorts.contains(where: { $0.number == 32400 }) {
            fingerprints["plex_present"] = "true"
        }
        if openPorts.contains(where: { $0.number == 8200 }) {
            fingerprints["dlna_present"] = "true"
        }
        
        return fingerprints
    }
}
