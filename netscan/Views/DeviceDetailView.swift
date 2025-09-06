import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct DeviceDetailView: View {
    let device: Device
    
    public var body: some View {
        ZStack {
            Theme.color(.bgRoot).ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space(.xxxl)) {
                    deviceHeader
                    networkInfoSection
                    identificationSection
                    activeServicesSection
                }
                .padding(Theme.space(.xl))
            }
        }
        .navigationTitle("Device Details")
    }

    private var identificationSection: some View {
        VStack(alignment: .leading, spacing: Theme.space(.lg)) {
            Text("Identification")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.color(.textPrimary))

            VStack(alignment: .leading, spacing: Theme.space(.md)) {
                HStack {
                    Text("Type")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.color(.textSecondary))
                    Spacer()
                    Text(device.deviceType.rawValue.capitalized)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.color(.textPrimary))
                }
                if let conf = device.confidence {
                    VStack(alignment: .leading) {
                        Text("Confidence")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.color(.textSecondary))
                        #if os(macOS)
                        Gauge(value: conf, in: 0...1) {
                            Text(String(format: "%.0f%%", conf * 100))
                        }
                        .gaugeStyle(.accessoryLinear)
                        #else
                        Gauge(value: conf, in: 0...1) {
                            Text(String(format: "%.0f%%", conf * 100))
                        }
                        #endif
                    }
                }

            }
            .padding(Theme.space(.lg))
            .background(Theme.color(.bgCard))
            .cornerRadius(Theme.radius(.lg))
        }
    }
    
    private var deviceHeader: some View {
        HStack(spacing: Theme.space(.lg)) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radius(.lg))
                    .fill(Theme.color(.bgElevated))
                    .frame(width: 54, height: 54)
                
                Image(systemName: device.deviceType.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Theme.color(.accentPrimary))
            }
            
            VStack(alignment: .leading, spacing: Theme.space(.xs)) {
                Text(device.name)
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.color(.textPrimary))
                
                Text(device.manufacturer ?? "Unknown Manufacturer")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.color(.textSecondary))
                
                HStack(spacing: Theme.space(.sm)) {
                    Circle()
                        .fill(device.isOnline ? Theme.color(.statusOnline) : Theme.color(.statusOffline))
                        .frame(width: 8, height: 8)
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.color(.textTertiary))
                }
            }
            Spacer()
        }
    }
    
    private var networkInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.space(.lg)) {
            Text("Network Information")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.color(.textPrimary))
            
            VStack(spacing: Theme.space(.md)) {
                InfoRow(label: "IP Address", value: device.ipAddress, isMono: true, showCopy: true)
                InfoRow(label: "MAC Address", value: device.macAddress?.uppercased(), isMono: true, showCopy: true)
                InfoRow(label: "Hostname", value: device.hostname)
                InfoRow(label: "First Seen", value: device.firstSeen?.formatted())
                InfoRow(label: "Last Seen", value: device.lastSeen?.formatted())
            }
            .padding(Theme.space(.lg))
            .background(Theme.color(.bgCard))
            .cornerRadius(Theme.radius(.lg))
        }
    }

    private var activeServicesSection: some View {
        // build port-derived services (only map well-known ports)
        let portDerived: [NetworkService] = device.openPorts.compactMap { port in
            switch port.number {
            case 80: return NetworkService(name: port.serviceName, type: .http)
            case 443: return NetworkService(name: port.serviceName, type: .https)
            case 22: return NetworkService(name: port.serviceName, type: .ssh)
            case 1900: return NetworkService(name: port.serviceName, type: .ssdp)
            case 5353: return NetworkService(name: port.serviceName, type: .mdns)
            default: return nil
            }
        }

    // Combine uniqueServices (from discovery) with port-derived services, deduping by type
    var map: [ServiceType: NetworkService] = [:]
    for svc in device.displayServices + portDerived {
            if let existing = map[svc.type] {
                // prefer the one with longer name
                if svc.name.count > existing.name.count {
                    map[svc.type] = svc
                }
            } else {
                map[svc.type] = svc
            }
        }
        let combined = Array(map.values).filter { $0.type != .unknown }

        return VStack(alignment: .leading, spacing: Theme.space(.lg)) {
            Text("Active Services")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.color(.textPrimary))

            VStack(alignment: .leading) {
                if #available(macOS 13.0, *) {
                    FlowLayout(alignment: .leading, spacing: Theme.space(.sm)) {
                        ForEach(combined) { svc in
                            serviceTagButton(for: svc)
                        }
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(combined) { svc in
                                serviceTagButton(for: svc)
                            }
                        }
                    }
                }
            }
            .padding(Theme.space(.lg))
            .background(Theme.color(.bgCard))
            .cornerRadius(Theme.radius(.lg))
        }
    }

    @ViewBuilder
    private func serviceTagButton(for svc: NetworkService) -> some View {
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
                ServiceTag(service: svc, showNonStandardPort: true)
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
                // On iOS, we can't open ssh URLs; copy the ssh command to the clipboard instead.
                let cmd = "ssh \(device.ipAddress)"
                UIPasteboard.general.string = cmd
                #endif
            }) {
                ServiceTag(service: svc, showNonStandardPort: true)
            }.buttonStyle(.plain)
        } else {
            ServiceTag(service: svc, showNonStandardPort: true)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String?
    var isMono: Bool = false
    var showCopy: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.color(.textSecondary))
            
            Spacer()
            
            Text(value ?? "N/A")
                .font(isMono ? Theme.Typography.mono : Theme.Typography.subheadline)
                .foregroundColor(Theme.color(.textPrimary))
            
            if showCopy, let value = value {
                Button(action: { copyToClipboard(value) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.color(.textTertiary))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #elseif canImport(UIKit)
    UIPasteboard.general.string = text
    #endif
    }
}

private struct PortRow: View {
    let port: Port
    
    var body: some View {
        HStack(spacing: Theme.space(.lg)) {
            Text("\(port.number)")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.color(.accentPrimary))
                .frame(width: 50, alignment: .leading)
            
            VStack(alignment: .leading) {
                Text(port.serviceName)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.color(.textPrimary))
                Text(port.description)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textTertiary))
            }
            
            Spacer()
            
            HStack(spacing: Theme.space(.sm)) {
                Image(systemName: "checkmark.circle.fill")
                Text(port.status.rawValue.capitalized)
            }
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.color(.statusOnline))
        }
        .padding(.vertical, Theme.space(.sm))
    }
}

// A simple horizontal flow layout for tags
@available(macOS 13.0, *)
struct FlowLayout: Layout {
    var alignment: Alignment = .center
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for size in sizes {
            if currentRowWidth + spacing + size.width > proposal.width ?? .infinity {
                totalHeight += currentRowHeight
                totalWidth = max(totalWidth, currentRowWidth)
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth += spacing + size.width
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        totalHeight += currentRowHeight
        totalWidth = max(totalWidth, currentRowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for index in subviews.indices {
            if x + sizes[index].width > bounds.width {
                y += currentRowHeight + spacing
                x = bounds.minX
                currentRowHeight = 0
            }
            subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += sizes[index].width + spacing
            currentRowHeight = max(currentRowHeight, sizes[index].height)
        }
    }
}


struct DeviceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceDetailView(device: Device.mock)
    }
}
