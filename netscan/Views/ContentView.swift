import SwiftUI
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: ScanViewModel
    @State private var selectedDevice: Device?
    // Search & filter state
    @State private var searchText: String = ""
    @State private var filterOnlineOnly: Bool = false
    @State private var filterDeviceType: DeviceType? = nil
    @State private var filterDiscoverySource: DiscoverySource? = nil
    
    public init() {
        // This initializer will be used by AppDelegate
        _vm = StateObject(wrappedValue: ScanViewModel(modelContext: DataManager.shared.modelContainer.mainContext))
    }

    // This initializer is specifically for SwiftUI Previews
    init(inMemory: Bool = false) {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try! ModelContainer(for: PersistentDevice.self, configurations: config)
        _vm = StateObject(wrappedValue: ScanViewModel(modelContext: container.mainContext))
    }
    
    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Network info header - fixed at top
                header
                
                // Control buttons - fixed below header  
                controls
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                
                // Device list - expandable content area
                deviceListSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Summary footer - fixed at bottom
                summaryFooter
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Theme.color(.bgRoot))
            .navigationTitle("Network Scanner")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { vm.detectNetwork() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        // Online only toggle
                        Toggle(isOn: $filterOnlineOnly) { Label("Online Only", systemImage: "dot.radiowaves.left.and.right") }
                        Divider()
                        // Device type picker
                        Picker("Device Type", selection: Binding(get: { filterDeviceType ?? .unknown }, set: { filterDeviceType = ($0 == .unknown ? nil : $0) })) {
                            Text("All Types").tag(DeviceType.unknown)
                            ForEach(DeviceType.allCases.filter { $0 != .unknown }, id: \.self) { t in
                                Text(t.rawValue.capitalized).tag(t)
                            }
                        }
                        // Discovery source picker
                        Picker("Source", selection: Binding(get: { filterDiscoverySource ?? .unknown }, set: { filterDiscoverySource = ($0 == .unknown ? nil : $0) })) {
                            Text("All Sources").tag(DiscoverySource.unknown)
                            Text("mDNS").tag(DiscoverySource.mdns)
                            Text("SSDP").tag(DiscoverySource.ssdp)
                            Text("ARP").tag(DiscoverySource.arp)
                            Text("NIO").tag(DiscoverySource.nio)
                            Text("Ping").tag(DiscoverySource.ping)
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .help("Filter devices")
                }
            }
            // System search field in toolbar
            .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search devices"))
            .onAppear {
                vm.detectNetwork()
            }
        } detail: {
            if let selectedDevice = selectedDevice {
                DeviceDetailView(device: selectedDevice)
            } else {
                placeholderView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 350, ideal: 400)
        .animation(.default, value: vm.devices)
    }
    
    private var deviceListSection: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                // Debug label removed for production UI
                
                ForEach(filteredDevices) { device in
                    Button(action: { selectedDevice = device }) {
                        DeviceRowView(device: device)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedDevice?.id == device.id ? 
                                  Color.accentColor.opacity(0.1) : 
                                  Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                
                if filteredDevices.isEmpty && !vm.isScanning {
                    VStack(spacing: 12) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        
                        Text("No devices found")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Click 'Scan' to discover devices on your network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.clear) // Remove the grey background
    }

    // MARK: - Derived filtered list
    private var filteredDevices: [Device] {
        var list = vm.devices
        // Online filter
        if filterOnlineOnly { list = list.filter { $0.isOnline } }
        // Type filter
        if let t = filterDeviceType { list = list.filter { $0.deviceType == t } }
        // Source filter
        if let s = filterDiscoverySource { list = list.filter { $0.discoverySource == s } }
        // Search text across common fields
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let lower = q.lowercased()
            list = list.filter { d in
                if d.name.lowercased().contains(lower) { return true }
                if d.ipAddress.lowercased().contains(lower) { return true }
                if (d.manufacturer ?? "").lowercased().contains(lower) { return true }
                if (d.hostname ?? "").lowercased().contains(lower) { return true }
                if (d.macAddress ?? "").lowercased().contains(lower) { return true }
                // services, ports
                if d.displayServices.contains(where: { $0.type.rawValue.lowercased().contains(lower) || $0.name.lowercased().contains(lower) || (String($0.port ?? -1).contains(lower) && $0.port != nil) }) { return true }
                return false
            }
        }
        return list
    }
    
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.americas.fill")
                .foregroundColor(.secondary)
                .imageScale(.medium)
            
            if let networkInfo = vm.networkInfo {
                VStack(alignment: .leading, spacing: 2) {
                    Text(networkInfo.network)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                            .foregroundColor(.accentColor)
                            .imageScale(.small)
                        
                        Text(networkInfo.ip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                }
                
                Spacer()
            } else {
                Text("No Network")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.color(.bgCard))
        .overlay(
            Divider()
                .frame(maxWidth: .infinity, maxHeight: 1)
                .background(Theme.color(.separator)),
            alignment: .bottom
        )
    }
    
    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Left: buttons group - take flexible space
                HStack(spacing: 8) {
                    Button(action: { vm.detectNetwork() }) {
                        Label("Detect", systemImage: "magnifyingglass")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if vm.isScanning {
                        Button(role: .destructive, action: { vm.cancelScan() }) {
                            Label("Stop", systemImage: "stop.circle")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(action: { vm.startScan() }) {
                            Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(vm.networkInfo == nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Right: fixed area for spinner and scan progress
                HStack(spacing: 8) {
                    // Show numeric/phase progress when available, otherwise show a simple status.
                    Text(vm.isScanning ? (vm.progressText.isEmpty ? "Scanning" : vm.progressText) : "Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Group {
                        if vm.isScanning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                                .frame(width: 8, height: 8)
                                .scaleEffect(0.8, anchor: .center)
                                .controlSize(.small)
                                .baselineOffset(-1)
                        } else {
                            Color.clear.frame(width: 8, height: 8)
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(width: 220, alignment: .trailing)
            }
            .padding(.top, 4)
        }
    }
    
    private var summaryFooter: some View {
        HStack(spacing: 20) {
            StatBlock(count: vm.deviceCount, title: "Devices")
            StatBlock(count: vm.onlineCount, title: "Online")
            StatBlock(count: vm.servicesCount, title: "Services")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    .background(Theme.color(.bgCard))
        .frame(maxWidth: .infinity)
    }
    
    private var placeholderView: some View {
        ZStack {
            // Keep the placeholder inside the column's safe area so it doesn't paint over the
            // titlebar or other system chrome. This avoids the 'floating panel' visual.
            Theme.color(.bgRoot)
            VStack(spacing: Theme.space(.md)) {
                Image(systemName: "network")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.color(.textTertiary))
                Text("Select a Device")
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.color(.textPrimary))
                Text("Choose a device from the list to see more information.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.color(.textSecondary))
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StatBlock: View {
    let count: Int
    let title: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60)
    }
}

#Preview {
    ContentView(inMemory: true)
}
