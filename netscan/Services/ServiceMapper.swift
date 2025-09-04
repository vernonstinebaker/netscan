import Foundation

public enum ServiceMapper {
    public static func type(forPort port: Int) -> ServiceType {
        if let entry = ServiceCatalog.entry(forPort: UInt16(port)) {
            switch entry.key.lowercased() {
            case "http": return .http
            case "https": return .https
            case "ssh": return .ssh
            case "dns": return .dns
            case "smb": return .smb
            case "dhcp": return .dhcp
            case "cast": return .chromecast
            default: return .unknown
            }
        }
        return .unknown
    }

    public static func type(forBonjour netServiceType: String) -> ServiceType {
        let t = netServiceType.lowercased()
        if t.contains("_http._tcp") { return .http }
        if t.contains("_https._tcp") { return .https }
        if t.contains("_ssh._tcp") { return .ssh }
        if t.contains("_smb._tcp") || t.contains("_afpovertcp._tcp") { return .smb }
        if t.contains("_googlecast._tcp") || t.contains("_raop._tcp") { return .chromecast }
        if t.contains("_ipp._tcp") || t.contains("_printer._tcp") { return .http }
        if t.contains("_dns") { return .dns }
        return .unknown
    }
}

