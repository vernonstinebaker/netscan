import Foundation
import SwiftUI

// Canonical metadata for well-known network services & ports.
public struct ServiceCatalogEntry: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String              // canonical key e.g. "http"
    public let displayName: String      // Human readable e.g. "HTTP"
    public let description: String      // Short description
    public let defaultPorts: [UInt16]   // Common ports
    public let category: Category
    public let icon: String             // SF Symbol
    public let color: ServiceCatalogEntryColor
    
    public enum Category: String, CaseIterable, Sendable { case web, remoteAccess, nameResolution, fileShare, infrastructure, media, other }
}

public enum ServiceCatalogEntryColor: String, Sendable { case accentPrimary, accentWarn, accentDanger, none }

public enum ServiceCatalog: Sendable {
    private static let entries: [ServiceCatalogEntry] = [
        ServiceCatalogEntry(
            key: "http",
            displayName: "HTTP",
            description: "Web Server",
            defaultPorts: [80, 8080, 8008],
            category: .web,
            icon: "globe",
            color: .accentPrimary
        ),
        ServiceCatalogEntry(
            key: "https",
            displayName: "HTTPS",
            description: "Secure Web Server",
            defaultPorts: [443, 8443],
            category: .web,
            icon: "lock.shield",
            color: .accentPrimary
        ),
        ServiceCatalogEntry(
            key: "ssh",
            displayName: "SSH",
            description: "Secure Shell",
            defaultPorts: [22],
            category: .remoteAccess,
            icon: "terminal",
            color: .accentDanger
        ),
        ServiceCatalogEntry(
            key: "dns",
            displayName: "DNS",
            description: "Domain Name Service",
            defaultPorts: [53],
            category: .nameResolution,
            icon: "network",
            color: .none
        ),
        ServiceCatalogEntry(
            key: "smb",
            displayName: "SMB",
            description: "File Sharing",
            defaultPorts: [445, 139],
            category: .fileShare,
            icon: "externaldrive.connected.to.line.below",
            color: .accentPrimary
        ),
        ServiceCatalogEntry(
            key: "dhcp",
            displayName: "DHCP",
            description: "Address Assignment",
            defaultPorts: [67, 68],
            category: .infrastructure,
            icon: "arrow.triangle.2.circlepath",
            color: .none
        ),
        ServiceCatalogEntry(
            key: "cast",
            displayName: "Chromecast",
            description: "Media Cast",
            defaultPorts: [8009, 8008],
            category: .media,
            icon: "tv.badge.wifi",
            color: .accentPrimary
        ),
        ServiceCatalogEntry(
            key: "ftp",
            displayName: "FTP",
            description: "File Transfer Protocol",
            defaultPorts: [21],
            category: .fileShare,
            icon: "tray.and.arrow.down",
            color: .accentPrimary
        )
    ]
    
    public static func entry(forPort port: UInt16) -> ServiceCatalogEntry? {
        entries.first { $0.defaultPorts.contains(port) }
    }
    
    public static func entry(forKey key: String) -> ServiceCatalogEntry? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }
    
    public static func all() -> [ServiceCatalogEntry] { entries }
}
