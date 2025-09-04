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
            if hostname.contains("laptop") || hostname.contains("macbook") { return .laptop }
            if hostname.contains("desktop") { return .computer }
            if hostname.contains("phone") || hostname.contains("iphone") || hostname.contains("android") { return .phone }
        }
        
        // Rule 2: Check vendor name for strong clues
        if let vendor = vendor?.lowercased() {
            if vendor.contains("netgear") || vendor.contains("tp-link") || vendor.contains("linksys") || vendor.contains("asus") { return .router }
            if vendor.contains("sony") { return .playstation } // Could also be a TV, but console is a good guess
            if vendor.contains("hp") || vendor.contains("brother") || vendor.contains("epson") { return .printer }
            if vendor.contains("google") || vendor.contains("chromecast") { return .tv }
            if vendor.contains("apple") { return .laptop } // Default to laptop for Apple devices
        }
        
        // Rule 3: Check open ports for common signatures
        let portNumbers = Set(openPorts.map { $0.number })
        if portNumbers.contains(53) || portNumbers.contains(67) { return .router } // DNS, DHCP
        if portNumbers.contains(631) || portNumbers.contains(9100) { return .printer } // IPP, JetDirect
        if portNumbers.contains(8008) || portNumbers.contains(8009) { return .tv } // Google Cast
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
        
        return fingerprints
    }
}
