import SwiftUI
import SwiftData

@available(macOS 14.0, *)
public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: ScanViewModel
    @State private var selectedDevice: Device?
    
    public init(modelContext: ModelContext) {
        _vm = StateObject(wrappedValue: ScanViewModel(modelContext: modelContext))
    }

    // This initializer is specifically for SwiftUI Previews
    init(inMemory: Bool = false) {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try! ModelContainer(for: PersistentDevice.self, configurations: config)
        _vm = StateObject(wrappedValue: ScanViewModel(modelContext: container.mainContext))
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
            .buttonStyle(.bordered)
            .tint(Theme.color(.accentPrimary))
            
            if vm.isScanning {
                Button(role: .destructive, action: { vm.cancelScan() }) {
                    Label("Stop", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: { vm.startScan() }) {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                .disabled(vm.networkInfo == nil)
            }
            
            Spacer()
            
            ZStack {
                ProgressView()
                    .scaleEffect(0.7)
                    .opacity(vm.isScanning ? 1.0 : 0.0)
            }
            .frame(width: 24, height: 24)
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
