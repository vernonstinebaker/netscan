import SwiftUI

@available(macOS 14.0, *)
public struct ContentView: View {
    @StateObject private var vm: ScanViewModel
    @State private var selectedDevice: Device?
    
    public init() {
        _vm = StateObject(wrappedValue: ScanViewModel())
    }

    // This initializer is specifically for SwiftUI Previews
    init(inMemory: Bool = false) {
        _vm = StateObject(wrappedValue: ScanViewModel())
    }
    
    public var body: some View {
        NavigationSplitView {
            ZStack(alignment: .bottom) {
                Theme.color(.bgRoot).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, Theme.space(.lg))
                        .padding(.top, Theme.space(.lg))
                    
                    controls
                        .padding(.horizontal, Theme.space(.lg))
                        .padding(.vertical, Theme.space(.md))
                    
                    searchAndFilterControls
                        .padding(.horizontal, Theme.space(.lg))
                        .padding(.bottom, Theme.space(.md))

                    ScrollView {
                        LazyVStack(spacing: Theme.space(.md)) {
                            ForEach(vm.devices) { device in
                                Button(action: { selectedDevice = device }) {
                                    DeviceRowView(device: device)
                                }
                                .buttonStyle(.plain)
                                .background(selectedDevice?.id == device.id ? Theme.color(.accentPrimary).opacity(0.1) : .clear)
                                .cornerRadius(Theme.radius(.xl))
                            }
                        }
                        .padding(.horizontal, Theme.space(.lg))
                        .padding(.bottom, 100)
                    }
                }
                
                summaryFooter
            }
            .navigationTitle("Network Scanner")
            .onAppear {
                vm.detectNetwork()
                // vm.startScan() was removed to restore manual Scan button control
            }
        } detail: {
            if let selectedDevice = selectedDevice {
                DeviceDetailView(device: selectedDevice)
            } else {
                placeholderView
            }
        }
        .animation(.default, value: vm.devices)
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "globe.americas.fill")
                .foregroundColor(Theme.color(.textTertiary))
            
            if let networkInfo = vm.networkInfo {
                Text(networkInfo.network)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.color(.textSecondary))
                
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(Theme.color(.accentPrimary))
                
                Text(networkInfo.ip)
                    .font(Theme.Typography.mono)
                    .foregroundColor(Theme.color(.textSecondary))
            } else {
                Text("No Network")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.color(.textSecondary))
            }
            
            Spacer()
        }
        .padding()
        .background(Theme.color(.bgCard).opacity(0.5))
        .cornerRadius(Theme.radius(.md))
    }
    
    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: { vm.detectNetwork() }) {
                Label("Detect", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.color(.accentPrimary))
            
            if vm.isScanning {
                Button(role: .destructive, action: { vm.cancelScan() }) {
                    Label("Stop", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: { vm.startScan() }) {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.color(.accentPrimary))
                .disabled(vm.networkInfo == nil)
            }
            
            Spacer()
            
            if vm.isScanning {
                VStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(vm.progressText)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.color(.textSecondary))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 200)
                }
            } else {
                Text("\(vm.onlineCount) online")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.color(.textTertiary))
            }
        }
    }
    
    private var searchAndFilterControls: some View {
        VStack(spacing: Theme.space(.md)) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.color(.textTertiary))
                
                TextField("Search devices, IPs, services...", text: $vm.filterOptions.searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Theme.color(.textPrimary))
                
                if !vm.filterOptions.searchText.isEmpty {
                    Button(action: { vm.filterOptions.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.color(.textTertiary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.space(.md))
            .background(Theme.color(.bgElevated))
            .cornerRadius(Theme.radius(.lg))
            
            // Filter controls
            HStack(spacing: Theme.space(.md)) {
                // Online filter
                Toggle("Online Only", isOn: $vm.filterOptions.onlineOnly)
                    .toggleStyle(.switch)
                    .foregroundColor(Theme.color(.textSecondary))
                
                Spacer()
                
                // Device type filter
                Menu {
                    Button("All Types") {
                        vm.filterOptions.deviceType = nil
                    }
                    ForEach(DeviceType.allCases, id: \.self) { type in
                        Button(type.rawValue.capitalized) {
                            vm.filterOptions.deviceType = type
                        }
                    }
                } label: {
                    HStack {
                        Text(vm.filterOptions.deviceType?.rawValue.capitalized ?? "All Types")
                        Image(systemName: "chevron.down")
                    }
                    .foregroundColor(Theme.color(.textSecondary))
                }
                
                // Discovery source filter
                Menu {
                    Button("All Sources") {
                        vm.filterOptions.source = nil
                    }
                    ForEach([DiscoverySource.mdns, .arp, .ssdp, .nio, .ping], id: \.self) { source in
                        Button(source.rawValue) {
                            vm.filterOptions.source = source
                        }
                    }
                } label: {
                    HStack {
                        Text(vm.filterOptions.source?.rawValue ?? "All Sources")
                        Image(systemName: "chevron.down")
                    }
                    .foregroundColor(Theme.color(.textSecondary))
                }
            }
        }
    }
    
    private var summaryFooter: some View {
        HStack {
            StatBlock(count: vm.deviceCount, title: "Devices")
            Spacer()
            StatBlock(count: vm.onlineCount, title: "Online")
            Spacer()
            StatBlock(count: vm.servicesCount, title: "Services")
        }
        .padding(Theme.space(.xl))
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.radius(.xl))
        .padding(Theme.space(.md))
    }
    
    private var placeholderView: some View {
        ZStack {
            Theme.color(.bgRoot).ignoresSafeArea()
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
        }
    }
}

struct StatBlock: View {
    let count: Int
    let title: String
    
    var body: some View {
        VStack(spacing: Theme.space(.xs)) {
            Text("\(count)")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.color(.textPrimary))
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.color(.textSecondary))
        }
        .frame(minWidth: 80)
    }
}

#Preview {
    // Use an in-memory container for previews
    ContentView(inMemory: true)
}
