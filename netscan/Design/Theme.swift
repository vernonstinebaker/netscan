import SwiftUI

// Central design system tokens & helpers
public enum Theme {
    // Color palette (dark-first). Light variants can be added later.
    public enum ColorToken: String {
        case accentPrimary, accentSecondary, accentWarn, accentDanger, accentMuted
        case bgRoot, bgCard, bgElevated
        case separator
        case textPrimary, textSecondary, textTertiary
        case statusOnline, statusOffline
    }
    
    public static func color(_ token: ColorToken) -> Color {
        switch token {
        // Accents
        case .accentPrimary: return Color(hex: "#1FF0A6") // Bright mint green
        case .accentSecondary: return Color(hex: "#4A90E2") // Soft blue for tags
        case .accentWarn: return Color.orange
        case .accentDanger: return Color.red
        case .accentMuted: return Color.gray.opacity(0.4)

        // Backgrounds
        case .bgRoot: return Color(hex: "#1A1C2A") // Dark navy
        case .bgCard: return Color(hex: "#2C2E43") // Slightly lighter navy/purple
        case .bgElevated: return Color(hex: "#3A3C5A")

        // Text & Separators
        case .separator: return Color.white.opacity(0.1)
        case .textPrimary: return Color.white
        case .textSecondary: return Color.white.opacity(0.7)
        case .textTertiary: return Color.white.opacity(0.5)

        // Status
        case .statusOnline: return Color(hex: "#1FF0A6")
        case .statusOffline: return Color.red.opacity(0.7)
        }
    }
    
    // Spacing scale
    public enum Spacing: CGFloat { case xxs=2, xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=32, jumbo=48 }
    public static func space(_ s: Spacing) -> CGFloat { s.rawValue }
    
    // Corner radii
    public enum Radius: CGFloat { case xs=4, sm=8, md=12, lg=16, xl=24 }
    public static func radius(_ r: Radius) -> CGFloat { r.rawValue }
    
    // Typography shortcuts
    public struct Typography {
        public static var largeTitle: Font { .system(size: 34, weight: .bold, design: .rounded) }
        public static var title: Font { .system(size: 24, weight: .bold, design: .rounded) }
        public static var headline: Font { .system(size: 18, weight: .semibold, design: .rounded) }
        public static var body: Font { .system(size: 16, weight: .regular, design: .default) }
        public static var subheadline: Font { .system(size: 14, weight: .medium, design: .rounded) }
        public static var mono: Font { .system(size: 14, design: .monospaced) }
        public static var caption: Font { .system(size: 12, weight: .medium, design: .rounded) }
        public static var tag: Font { .system(size: 10, weight: .bold, design: .rounded) }
    }
    
    // Service style descriptor
    public struct ServiceStyle { public let color: Color; public let icon: String; public let label: String }
    
    // Registry mapping service types to style
    public static func style(for service: ServiceType) -> ServiceStyle {
        switch service {
        case .http: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "globe", label: "HTTP")
        case .https: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "lock.shield", label: "HTTPS")
        case .ssh: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "terminal", label: "SSH")
        case .dns: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "network", label: "DNS")
        case .dhcp: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "arrow.triangle.2.circlepath", label: "DHCP")
        case .smb: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "externaldrive.connected.to.line.below", label: "SMB")
    case .chromecast: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "tv.badge.wifi", label: "Cast")
    case .ssdp: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "antenna.radiowaves.left.and.right", label: "SSDP")
    case .mdns: return ServiceStyle(color: Theme.color(.accentSecondary), icon: "dot.radiowaves.left.and.right", label: "mDNS")
    case .unknown: return ServiceStyle(color: Theme.color(.accentMuted), icon: "questionmark", label: "Unknown")
        }
    }
}

// Shared view modifiers
public struct CardBackground: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(Theme.space(.lg))
            .background(Theme.color(.bgCard))
            .cornerRadius(Theme.radius(.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius(.lg), style: .continuous)
                    .stroke(Theme.color(.separator), lineWidth: 1)
            )
    }
}

public extension View {
    func cardStyle() -> some View {
        modifier(CardBackground())
    }
}

// Helper for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
