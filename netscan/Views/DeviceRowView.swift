import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct DeviceRowView: View {
    let device: Device
    
    public var body: some View {
        HStack(spacing: Theme.space(.lg)) {
            deviceIcon
            deviceInfo
            Spacer()
            // Discovery source pill (small colored badge) shown before the online indicator
            if device.discoverySource != .unknown {
                Text(device.discoverySource.rawValue)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(discoveryPillColor(for: device.discoverySource))
                    .cornerRadius(8)
                    .padding(.trailing, 6)
            }
            onlineIndicator
        }
        .padding(Theme.space(.lg))
        .background(Theme.color(.bgCard))
        .cornerRadius(Theme.radius(.xl))
    }
    
    private var deviceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radius(.lg))
                .fill(Theme.color(.bgElevated))
                .frame(width: 48, height: 48)
            
            Image(systemName: device.deviceType.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Theme.color(.accentPrimary))
        }
    }
    
    private var deviceInfo: some View {
        VStack(alignment: .leading, spacing: Theme.space(.sm)) {
            Text(device.manufacturer ?? device.name)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.color(.textPrimary))
                .lineLimit(1)
                .truncationMode(.tail)
            
            // Show IP and MAC on separate rows so long addresses don't wrap horizontally
            VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                // IP should be prominent and use the accent color (matches master screenshot)
                Text(device.ipAddress)
                    .font(Theme.Typography.mono)
                    .foregroundColor(Theme.color(.accentPrimary))

                // MAC/address metadata should be smaller and muted to avoid wrapping
                if let mac = device.macAddress {
                    Text(mac.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.color(.textTertiary))
                }
            }
            
            // Subtitle removed to avoid redundancy; manufacturer/type info is available in the detail view.

            if !device.displayServices.isEmpty {
                clickableServiceTags
            }
        }
    }
    
    private var serviceTags: some View {
            HStack(spacing: Theme.space(.sm)) {
                // Make service tags clickable for common protocols
            ForEach(device.uniqueServices) { service in
                let s = Theme.style(for: service.type)
                HStack(spacing: Theme.space(.xs)) {
                    Image(systemName: s.icon)
                    Text(s.label.uppercased())
                }
                .font(Theme.Typography.tag)
                .padding(.horizontal, Theme.space(.sm))
                .padding(.vertical, Theme.space(.xs))
                .background(s.color.opacity(0.2))
                .foregroundColor(s.color)
                .cornerRadius(Theme.radius(.xs))
            }
        }
    }
    
        private var clickableServiceTags: some View {
            HStack(spacing: Theme.space(.sm)) {
                // Use uniqueServices for master list - shows one pill per service type regardless of ports
                let uniqueServices = device.uniqueServices.filter { $0.type != .unknown }
                
                // Debug: Compare what master list sees vs detail view
                //                let _ = print("=== DEBUG DEVICE ROW VIEW ===")
                //                let _ = print("Device: \(device.ipAddress)")
                //                let _ = print("Raw services count: \(device.services.count)")
                //                let _ = device.services.forEach { svc in
                //                    print("  Raw service: \(svc.type.rawValue) port:\(svc.port ?? -1) name:\(svc.name)")
                //                }
                //                let _ = print("UniqueServices count: \(device.uniqueServices.count)")
                //                let _ = device.uniqueServices.forEach { svc in
                //                    print("  Unique service: \(svc.type.rawValue) port:\(svc.port ?? -1) name:\(svc.name)")
                //                }
                //                let _ = print("=== END DEBUG ROW ===")
                // Debug logging removed; production view should use uniqueServices for consolidated tags
                 
                ForEach(uniqueServices) { svc in
                    if svc.type == .http || svc.type == .https {
                        Button(action: {
                            var comps = URLComponents()
                            comps.scheme = (svc.type == .https) ? "https" : "http"
                            comps.host = device.ipAddress
                            if let p = svc.port, !([80,443].contains(p) && ((svc.type == .http && p == 80) || (svc.type == .https && p == 443))) {
                                comps.port = p
                            }
                            guard let url = comps.url else { return }
                            #if os(macOS)
                            NSWorkspace.shared.open(url)
                            #elseif canImport(UIKit)
                            UIApplication.shared.open(url)
                            #endif
                        }) {
                            ServiceTag(service: svc)
                        }.buttonStyle(.plain)
                    } else if svc.type == .ssh {
                        Button(action: {
                            #if os(macOS)
                            var comps = URLComponents()
                            comps.scheme = "ssh"
                            comps.host = device.ipAddress
                            if let p = svc.port { comps.port = p }
                            if let url = comps.url, NSWorkspace.shared.open(url) {
                                return
                            }
                            let cmd = "ssh \(device.ipAddress)"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                            #elseif canImport(UIKit)
                            let cmd = "ssh \(device.ipAddress)"
                            UIPasteboard.general.string = cmd
                            #endif
                        }) {
                            ServiceTag(service: svc)
                        }.buttonStyle(.plain)
                    } else {
                        ServiceTag(service: svc)
                    }
                }
            }
        }
    private var onlineIndicator: some View {
        Circle()
            .fill(device.isOnline ? Theme.color(.statusOnline) : Theme.color(.statusOffline))
            .frame(width: 10, height: 10)
            .shadow(
                color: device.isOnline ? Theme.color(.statusOnline).opacity(0.6) : .clear,
                radius: 3,
                y: 1
            )
    }

    private func discoveryPillColor(for source: DiscoverySource) -> Color {
        switch source {
        case .mdns: return Theme.color(.accentPrimary)
        case .ssdp: return Theme.color(.accentSecondary)
        case .arp: return Theme.color(.accentMuted)
        case .nio: return Theme.color(.accentWarn)
        case .ping: return Theme.color(.accentDanger)
        case .unknown: return Theme.color(.accentMuted)
        }
    }
}

struct DeviceRowView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DeviceRowView(device: Device.mocks[0])
            DeviceRowView(device: Device.mocks[1])
            DeviceRowView(device: Device.mocks[2])
        }
        .padding()
        .background(Theme.color(.bgRoot))
        .previewLayout(.sizeThatFits)
    }
}
