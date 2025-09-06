import Foundation
import Combine

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var networkInfo: NetworkInfo?
    @Published var devices: [Device] = []
    @Published var filteredDevices: [Device] = []
    @Published var isScanning: Bool = false
    @Published var progressText: String = ""
    
    @Published var deviceCount: Int = 0
    @Published var onlineCount: Int = 0
    @Published var servicesCount: Int = 0
    
    @Published var filterOptions = DeviceFilterOptions() {
        didSet {
            applyFilters()
        }
    }

    private let arpParser = ARPTableParser()
    private let classifier = DeviceClassifier()
    private let ouiService = OUILookupService.shared
    private let pingScanner: PingScanner
    private let nioScanner = NIOPingScanner()
    private var scanTask: Task<Void, Error>?
    
    private var allDevices: [Device] = []
    
    init() {
        self.pingScanner = PingScanner()
        
        // Removed fetchDevicesFromKVStore call - will be called when network is detected
    }
    
    private func applyFilters() {
        filteredDevices = filterOptions.apply(to: allDevices)
        devices = filteredDevices
        updateCounts()
    }

    func detectNetwork() {
        networkInfo = NetworkInterface.currentIPv4()
        if networkInfo != nil {
            fetchDevicesFromKVStore(markAsOffline: true)
        }
    }

    func startScan() {
        guard !isScanning else { return }
        if networkInfo == nil { detectNetwork() }
        guard let info = networkInfo else { return }
        
        isScanning = true
        progressText = "Starting comprehensive network scan..."

        // 1) Load devices from the KV store immediately (marked offline) so UI shows known devices fast.
        fetchDevicesFromKVStore(markAsOffline: true)
        updateCounts()

        // Kick off background verification of KV devices (confirm online status and ports) in parallel.
        Task.detached { [weak self] in
            guard let self = self else { return }
            // Snapshot the devices safely from the main actor
            let kvDevices: [Device] = await MainActor.run { self.devices }
            await withTaskGroup(of: Void.self) { group in
                for dev in kvDevices {
                    let ip = dev.ipAddress
                    group.addTask {
                        // Ping check (lightweight)
                        let pingScanner = PingScanner()
                        if let result = try? await pingScanner.ping(host: ip), result.isOnline {
                            await self.updateDevice(ipAddress: ip, arpMap: [:], isOnline: true, discoverySource: .ping)
                        }

                        // Port scan to populate open ports
                        let portScanner = PortScanner(host: ip)
                        let openPorts = await portScanner.scanPorts(portRange: 1...1024)
                        if !openPorts.isEmpty {
                            await self.updateDevice(ipAddress: ip, arpMap: [:], isOnline: true, openPorts: openPorts)
                        }
                    }
                }
            }
        }

        // Reset the in-memory online flags for the new live scan
        for i in devices.indices { devices[i].isOnline = false }
        updateCounts()

        scanTask = Task {
            do {
                let totalHosts = IPv4.hosts(inNetwork: IPv4.network(ip: IPv4.parse(info.ip)!, mask: IPv4.parse(info.netmask)!), mask: IPv4.parse(info.netmask)!).count

                // --- Stage 2: Bonjour/mDNS Discovery ---
                progressText = "Discovering devices via Bonjour/mDNS..."
                let bonjourTask = Task { await BonjourDiscoverer().discover(timeout: 3.0) }

                // Run SSDP concurrently with mDNS (optional fast discovery)
                progressText = "Discovering devices via SSDP/UPnP..."
                let ssdpTask = Task { await SSDPDiscoverer().discover(timeout: 3.0) }

                // Wait for discovery methods to complete
                let bonjourResults = await bonjourTask.value
                let ssdpResults = await ssdpTask.value

                // --- Stage 3: ARP Table ---
                // ARP gives MAC addresses we can use to upsert KV entries
                let arpMap = await arpParser.getARPTable().reduce(into: [String: String]()) { $0[$1.ipAddress] = $1.macAddress }

                // Process Bonjour results (adds services/hostnames quickly)
                for (ip, hostResult) in bonjourResults {
                    await updateDevice(ipAddress: ip, arpMap: arpMap, isOnline: true, discoverySource: .mdns, services: hostResult.services)
                }

                // Process SSDP results
                for ip in ssdpResults.ips {
                    await updateDevice(ipAddress: ip, arpMap: arpMap, isOnline: true, discoverySource: .ssdp)
                }

                // --- Stage 4: Full subnet (NIO) scanning ---
                // NIO may be slower; skip IPs already marked online
                let alreadyOnlineIPs = Set(devices.filter { $0.isOnline }.map { $0.ipAddress })
                progressText = "Scanning subnet for new devices..."

                _ = try await self.nioScanner.scanSubnet(info: info, concurrency: 32, skipIPs: alreadyOnlineIPs) { progress in
                    Task { @MainActor in self.progressText = "Port scanning: \(progress.scanned)/\(totalHosts) hosts" }
                } onDeviceFound: { device in
                    Task { @MainActor in await self.updateDevice(ipAddress: device.ipAddress, arpMap: arpMap, isOnline: true, openPorts: device.openPorts, discoverySource: .nio) }
                }

                // --- Stage 5: Ping any remaining known IPs (slowest) ---
                progressText = "Pinging known devices..."
                let knownIPs = Set(devices.map { $0.ipAddress })
                for ip in knownIPs {
                    try Task.checkCancellation()
                    if let result = try? await pingScanner.ping(host: ip), result.isOnline {
                        await updateDevice(ipAddress: ip, arpMap: arpMap, isOnline: true, discoverySource: .ping)
                    }
                }

                await MainActor.run {
                    self.isScanning = false
                    self.progressText = "Scan complete - found \(self.onlineCount) online devices"
                }

                // Start background port scanning for discovered devices
                Task { @MainActor in
                    await self.startBackgroundPortScanning()
                }
                
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.progressText = "Scan failed or cancelled."
                }
            }
        }
    }
    
    private func updateDevice(ipAddress: String, arpMap: [String: String], isOnline: Bool, openPorts: [Port] = [], discoverySource: DiscoverySource = .unknown, services: [NetworkService] = []) async {
        guard ipAddress != "127.0.0.1" && !ipAddress.hasPrefix("127.") else { return }
        guard isScanning else { return }
        
        let macAddress = arpMap[ipAddress]
        let id = macAddress ?? ipAddress
        
        let vendorName = await ouiService.findVendor(for: macAddress)
        let deviceType = await classifier.classify(hostname: nil, vendor: vendorName, openPorts: openPorts)

        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].isOnline = isOnline
            devices[index].ipAddress = ipAddress
            if vendorName != nil { devices[index].manufacturer = vendorName }
            if deviceType != .unknown { devices[index].deviceType = deviceType }
            if discoverySource != .unknown { devices[index].discoverySource = discoverySource }
            if !services.isEmpty { 
                devices[index].services.append(contentsOf: services)
                // Deduplicate services
                devices[index].services = devices[index].services.reduce(into: [NetworkService]()) { result, service in
                    if !result.contains(where: { $0.type == service.type && $0.port == service.port }) {
                        result.append(service)
                    }
                }
            }
            if !openPorts.isEmpty { devices[index].openPorts = openPorts }

            // Recompute classification with confidence and fingerprints using the merged data
            let mergedServices = devices[index].services
            let mergedPorts = devices[index].openPorts
            Task { [weak self] in
                guard let self = self else { return }
                let (newType, conf) = await self.classifier.classifyWithConfidence(hostname: self.devices[index].hostname, vendor: self.devices[index].manufacturer, openPorts: mergedPorts, services: mergedServices)
                let fps = await self.classifier.fingerprintServices(services: mergedServices, openPorts: mergedPorts)
                await MainActor.run {
                    if newType != .unknown { self.devices[index].deviceType = newType }
                    self.devices[index].confidence = conf
                    self.devices[index].fingerprints = fps
                }
            }
            
            // Update allDevices as well
            if let allIndex = allDevices.firstIndex(where: { $0.id == id }) {
                allDevices[allIndex] = devices[index]
            }
            
            Task.detached {
                await self.updatePersistentDevice(id: id, ipAddress: ipAddress, macAddress: macAddress, vendor: vendorName, deviceType: deviceType, discoverySource: discoverySource, services: services, openPorts: openPorts)
            }
        } else if let index = devices.firstIndex(where: { $0.ipAddress == ipAddress }) {
            // Found existing device by IP address - update its ID and merge
            devices[index].id = id  // Update to MAC-based ID if available
            devices[index].isOnline = isOnline
            devices[index].macAddress = macAddress
            if vendorName != nil { devices[index].manufacturer = vendorName }
            if deviceType != .unknown { devices[index].deviceType = deviceType }
            if discoverySource != .unknown { devices[index].discoverySource = discoverySource }
            if !services.isEmpty { 
                devices[index].services.append(contentsOf: services)
                // Deduplicate services
                devices[index].services = devices[index].services.reduce(into: [NetworkService]()) { result, service in
                    if !result.contains(where: { $0.type == service.type && $0.port == service.port }) {
                        result.append(service)
                    }
                }
            }
            if !openPorts.isEmpty { devices[index].openPorts = openPorts }

            // Recompute classification with confidence and fingerprints using the merged data
            let mergedServices = devices[index].services
            let mergedPorts = devices[index].openPorts
            Task { [weak self] in
                guard let self = self else { return }
                let (newType, conf) = await self.classifier.classifyWithConfidence(hostname: self.devices[index].hostname, vendor: self.devices[index].manufacturer, openPorts: mergedPorts, services: mergedServices)
                let fps = await self.classifier.fingerprintServices(services: mergedServices, openPorts: mergedPorts)
                await MainActor.run {
                    if newType != .unknown { self.devices[index].deviceType = newType }
                    self.devices[index].confidence = conf
                    self.devices[index].fingerprints = fps
                }
            }
            
            // Update allDevices as well
            if let allIndex = allDevices.firstIndex(where: { $0.ipAddress == ipAddress }) {
                allDevices[allIndex] = devices[index]
            }
            
            Task.detached {
                await self.updatePersistentDevice(id: id, ipAddress: ipAddress, macAddress: macAddress, vendor: vendorName, deviceType: deviceType, discoverySource: discoverySource, services: services, openPorts: openPorts)
            }
        } else {
            var newDevice = Device(id: id, name: vendorName ?? ipAddress, ipAddress: ipAddress, discoverySource: discoverySource, rttMillis: nil, hostname: nil, macAddress: macAddress, deviceType: deviceType, manufacturer: vendorName, isOnline: isOnline, services: services, firstSeen: Date(), lastSeen: Date(), openPorts: openPorts)

            // Compute confidence/fingerprints for the new device
            let (initialType, conf) = await classifier.classifyWithConfidence(hostname: newDevice.hostname, vendor: newDevice.manufacturer, openPorts: newDevice.openPorts, services: newDevice.services)
            newDevice.deviceType = initialType
            newDevice.confidence = conf
            newDevice.fingerprints = await classifier.fingerprintServices(services: newDevice.services, openPorts: newDevice.openPorts)

            devices.append(newDevice)
            devices.sort { $0.ipAddress.compare($1.ipAddress, options: .numeric) == .orderedAscending }
            
            // Add to allDevices as well
            allDevices.append(newDevice)
            allDevices.sort { $0.ipAddress.compare($1.ipAddress, options: .numeric) == .orderedAscending }
            
            Task.detached {
                await self.createPersistentDevice(id: id, ipAddress: ipAddress, macAddress: macAddress, vendor: vendorName, deviceType: deviceType, discoverySource: discoverySource, services: services, openPorts: openPorts)
            }
        }
        updateCounts()
    }
    
    private func createPersistentDevice(id: String, ipAddress: String, macAddress: String?, vendor: String?, deviceType: DeviceType, discoverySource: DiscoverySource = .unknown, services: [NetworkService] = [], openPorts: [Port] = []) async {
        guard let networkInfo = networkInfo else { return }
        
        let key = DeviceKVStore.networkKey(info: networkInfo)
        var snapshots = DeviceKVStore.loadSnapshots(for: key)
        
        // Check if device already exists
        if let existingIndex = snapshots.firstIndex(where: { $0.id == id || $0.ip == ipAddress }) {
            // Update existing device
            snapshots[existingIndex].lastSeen = Date()
            snapshots[existingIndex].mac = macAddress ?? snapshots[existingIndex].mac
            snapshots[existingIndex].vendor = vendor ?? snapshots[existingIndex].vendor
            snapshots[existingIndex].deviceType = deviceType.rawValue
        } else {
            // Create new device
            let servicesData = try? JSONEncoder().encode(services)
            let openPortsData = try? JSONEncoder().encode(openPorts)
            let snapshot = DeviceSnapshot(
                id: id,
                ip: ipAddress,
                mac: macAddress,
                hostname: nil,
                vendor: vendor,
                deviceType: deviceType.rawValue,
                name: vendor ?? ipAddress,
                firstSeen: Date(),
                lastSeen: Date(),
                discoverySource: discoverySource.rawValue,
                servicesData: servicesData,
                openPortsData: openPortsData
            )
            snapshots.append(snapshot)
        }
        
        DeviceKVStore.saveSnapshots(snapshots, for: key)
    }
    
    private func updatePersistentDevice(id: String, ipAddress: String, macAddress: String?, vendor: String?, deviceType: DeviceType, discoverySource: DiscoverySource = .unknown, services: [NetworkService] = [], openPorts: [Port] = []) async {
        guard let networkInfo = networkInfo else { return }
        
        let key = DeviceKVStore.networkKey(info: networkInfo)
        var snapshots = DeviceKVStore.loadSnapshots(for: key)
        
        if let existingIndex = snapshots.firstIndex(where: { $0.id == id }) {
            // Update existing device by ID
            snapshots[existingIndex].ip = ipAddress
            snapshots[existingIndex].lastSeen = Date()
            snapshots[existingIndex].mac = macAddress ?? snapshots[existingIndex].mac
            snapshots[existingIndex].vendor = vendor ?? snapshots[existingIndex].vendor
            snapshots[existingIndex].deviceType = deviceType.rawValue
            snapshots[existingIndex].discoverySource = discoverySource.rawValue
            if !services.isEmpty {
                snapshots[existingIndex].servicesData = try? JSONEncoder().encode(services)
            }
            if !openPorts.isEmpty {
                snapshots[existingIndex].openPortsData = try? JSONEncoder().encode(openPorts)
            }
        } else if let existingIndex = snapshots.firstIndex(where: { $0.ip == ipAddress }) {
            // Update existing device by IP (ID may have changed from IP-based to MAC-based)
            snapshots[existingIndex].id = id
            snapshots[existingIndex].lastSeen = Date()
            snapshots[existingIndex].mac = macAddress ?? snapshots[existingIndex].mac
            snapshots[existingIndex].vendor = vendor ?? snapshots[existingIndex].vendor
            snapshots[existingIndex].deviceType = deviceType.rawValue
            snapshots[existingIndex].discoverySource = discoverySource.rawValue
            if !services.isEmpty {
                snapshots[existingIndex].servicesData = try? JSONEncoder().encode(services)
            }
            if !openPorts.isEmpty {
                snapshots[existingIndex].openPortsData = try? JSONEncoder().encode(openPorts)
            }
        }
        
        DeviceKVStore.saveSnapshots(snapshots, for: key)
    }

    func fetchDevicesFromKVStore(markAsOffline: Bool = false) {
        guard let networkInfo = networkInfo else { return }
        
        let key = DeviceKVStore.networkKey(info: networkInfo)
        let snapshots = DeviceKVStore.loadSnapshots(for: key)
        
        allDevices = snapshots.map { convertToTransient($0, isOnline: !markAsOffline) }
        applyFilters()
    }
    
    private func convertToTransient(_ snapshot: DeviceSnapshot, isOnline: Bool) -> Device {
        let services: [NetworkService] = {
            if let data = snapshot.servicesData {
                return (try? JSONDecoder().decode([NetworkService].self, from: data)) ?? []
            }
            return []
        }()
        
        let openPorts: [Port] = {
            if let data = snapshot.openPortsData {
                return (try? JSONDecoder().decode([Port].self, from: data)) ?? []
            }
            return []
        }()
        
        let discoverySource = DiscoverySource(rawValue: snapshot.discoverySource ?? "unknown") ?? .unknown
        
        return Device(
            id: snapshot.id,
            name: snapshot.name ?? snapshot.hostname ?? snapshot.vendor ?? snapshot.ip,
            ipAddress: snapshot.ip,
            discoverySource: discoverySource,
            rttMillis: nil,
            hostname: snapshot.hostname,
            macAddress: snapshot.mac,
            deviceType: DeviceType(rawValue: snapshot.deviceType ?? "unknown") ?? .unknown,
            manufacturer: snapshot.vendor,
            isOnline: isOnline,
            services: services,
            firstSeen: snapshot.firstSeen,
            lastSeen: snapshot.lastSeen,
            openPorts: openPorts
        )
    }

    private func updateCounts() {
        deviceCount = devices.count
        onlineCount = devices.filter { $0.isOnline }.count
        servicesCount = devices.reduce(0) { $0 + $1.services.count }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        progressText = "Scan cancelled."
    }
    
    private func startBackgroundPortScanning() async {
        for device in devices.filter({ $0.isOnline && $0.openPorts.isEmpty }) {
            let portScanner = PortScanner(host: device.ipAddress)
            let openPorts = await portScanner.scanPorts(portRange: 1...1024)
            if !openPorts.isEmpty {
                await updateDevice(ipAddress: device.ipAddress, arpMap: [:], isOnline: true, openPorts: openPorts)
            }
        }
    }
}
