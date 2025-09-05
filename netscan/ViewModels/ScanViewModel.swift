import Foundation
import Darwin
import SwiftData
import Combine

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var networkInfo: NetworkInfo?
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false
    @Published var progressText: String = ""
    
    @Published var deviceCount: Int = 0
    @Published var onlineCount: Int = 0
    @Published var servicesCount: Int = 0

    private let modelContext: ModelContext?
    private let arpParser = ARPTableParser()
    private let classifier = DeviceClassifier()
    private let ouiService = OUILookupService.shared
    private let pingScanner: PingScanner
    private let nioScanner = NIOPingScanner()
    // Factory for creating per-host port scanners (DI for testing)
    private let portScannerFactory: (String) -> PortScanning
    private var portScanInProgress: Set<String> = []
    private var portScanCompleted: Set<String> = []
    private var portScanTasks: [String: Task<Void, Never>] = [:]
    private var scanTask: Task<Void, Error>?
    
    init(modelContext: ModelContext? = nil, portScannerFactory: @escaping (String) -> PortScanning = { host in PortScanner(host: host) }) {
        self.modelContext = modelContext
        self.pingScanner = PingScanner()
        self.portScannerFactory = portScannerFactory
        
        if modelContext != nil {
            fetchDevicesFromDB(markAsOffline: true)
        }
    }

    func detectNetwork() {
        networkInfo = NetworkInterface.currentIPv4()
        print("Detected network: \(networkInfo?.description ?? "nil")")
    }

    func startScan() {
        guard !isScanning else { return }
        
        print("🔍 Starting network scan...")
        isScanning = true
        progressText = "Starting scan..."
        
        scanTask = Task {
            do {
                print("📡 Detecting network info...")
                detectNetwork()
                guard let info = networkInfo else {
                    print("❌ Failed to detect network")
                    return
                }
                print("🌐 Network detected: \(info.ip)/\(info.netmask)")
                
                // --- Stage 1: Start Bonjour and SSDP immediately so fast mDNS results populate first ---
                print("🔍 Starting Bonjour and SSDP discovery...")
                #if os(iOS)
                // On iOS, Bonjour and other network discovery may be restricted without
                // the 'NSLocalNetworkUsageDescription' and service privacy entries in Info.plist
                // or without the Local Network permission granted at runtime. Log a hint.
                if Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") == nil {
                    print("[ScanViewModel] WARNING: NSLocalNetworkUsageDescription missing from Info.plist — Bonjour/mDNS may not work on iOS until user grants Local Network permission.")
                }
                #endif
                async let bonjourTask = BonjourDiscoverer().discover(timeout: 4.0)
                async let ssdpTask = SSDPDiscoverer().discover(timeout: 3.5)
                // Also kick off WS-Discovery (Windows/Printers) in parallel
                async let wsTask = WSDiscoveryDiscoverer().discover(timeout: 2.5)
                // Start ARP parsing concurrently so it can enrich devices early
                async let arpEntriesTask = arpParser.getARPTable()

                // Await Bonjour first and insert results immediately so UI shows mDNS devices quickly.
                let bonjourResults = await bonjourTask
                if !bonjourResults.isEmpty {
                    print("📱 Bonjour found: \(bonjourResults.count) devices: \(bonjourResults.keys)")
                    for (ip, host) in bonjourResults {
                        try Task.checkCancellation()
                        await updateDevice(ipAddress: ip, arpMap: [:], isOnline: true, hostname: host.hostname, services: host.services, discoverySource: .mdns)
                    }
                }

                // Now await SSDP results and insert them
                let ssdpResults = await ssdpTask
                if !ssdpResults.ips.isEmpty {
                    print("📺 SSDP found: \(ssdpResults.ips.count) devices: \(ssdpResults.ips)")
                    for ip in ssdpResults.ips {
                        try Task.checkCancellation()
                        await updateDevice(ipAddress: ip, arpMap: [:], isOnline: true, discoverySource: .ssdp)
                    }
                }
                // WS-Discovery results
                let wsResults = await wsTask
                if !wsResults.ips.isEmpty {
                    print("🖨️ WS-Discovery found: \(wsResults.ips.count) devices: \(wsResults.ips)")
                    for ip in wsResults.ips {
                        try Task.checkCancellation()
                        await updateDevice(ipAddress: ip, arpMap: [:], isOnline: true, discoverySource: .ssdp)
                    }
                }

                // --- ARP (arrives whenever ready) ---
                let arpEntries = await arpEntriesTask
                let arpMap = arpEntries.reduce(into: [String: String]()) { $0[$1.ipAddress] = $1.macAddress }
                if !arpEntries.isEmpty {
                    print("[ScanViewModel] Populating devices from ARP table: \(arpEntries.map { $0.ipAddress })")
                    for entry in arpEntries {
                        try Task.checkCancellation()
                        if let existing = devices.first(where: { $0.ipAddress == entry.ipAddress }) {
                            // Update ARP info on existing device (don't override discovery source if higher priority)
                            await updateDevice(ipAddress: entry.ipAddress, arpMap: arpMap, isOnline: existing.isOnline, discoverySource: .arp)
                        } else {
                            await updateDevice(ipAddress: entry.ipAddress, arpMap: arpMap, isOnline: true, discoverySource: .arp)
                        }
                    }
                }

                let totalHosts = IPv4.hosts(inNetwork: IPv4.network(ip: IPv4.parse(info.ip)!, mask: IPv4.parse(info.netmask)!), mask: IPv4.parse(info.netmask)!).count

                // --- Stage: Check known devices for online status ---
                progressText = "Checking known devices..."
                let knownIPs = Set(devices.map { $0.ipAddress })
                print("📋 Found \(knownIPs.count) known devices: \(knownIPs)")

                print("� Checking known devices for online status (skipping already-online devices)...")
                for ip in knownIPs {
                    try Task.checkCancellation()
                    if let existing = devices.first(where: { $0.ipAddress == ip }), existing.isOnline {
                        print("ℹ️ Skipping ping for already-online known device: \(ip)")
                        continue
                    }
                    if let result = try? await pingScanner.ping(host: ip), result.isOnline {
                        print("✅ Known device \(ip) is online")
                        await updateDevice(ipAddress: ip, arpMap: arpMap, isOnline: true, discoverySource: .ping)
                    } else {
                        print("❌ Known device \(ip) is offline")
                    }
                }
                
                print("🔄 Sending UI update notification...")
                // Force UI update
                await MainActor.run {
                    self.objectWillChange.send()
                }
                
                print("📊 Current device count after discovery: \(devices.count)")
                print("📋 Current devices: \(devices.map { $0.ipAddress })")
                
                // --- Stage 2: Full Discovery for New Devices ---
                let alreadyOnlineIPs = Set(devices.filter { $0.isOnline }.map { $0.ipAddress })
                progressText = "Discovering new devices..."
                print("🔍 Starting full network scan for \(totalHosts) hosts...")
                
                // Adjust concurrency based on subnet size for better responsiveness
                let total = totalHosts
                let effectiveConcurrency: Int = {
                    if total <= 256 { return 64 }
                    if total <= 1024 { return 32 }
                    return 16
                }()
                _ = try await self.nioScanner.scanSubnet(info: info, concurrency: effectiveConcurrency, skipIPs: alreadyOnlineIPs) { progress in
                    Task { @MainActor in self.progressText = "Port Scan: \(progress.scanned)/\(totalHosts)" }
                } onDeviceFound: { device in
                    Task { @MainActor in await self.updateDevice(ipAddress: device.ipAddress, arpMap: arpMap, isOnline: true, openPorts: device.openPorts.map { $0.number }, discoverySource: .nio) }
                }

                // --- Stage: ICMP fallback for hosts that didn't respond to TCP probes ---
                // Some hosts don't have any of the probed TCP ports open but will respond to ICMP.
                // Run a SystemPingScanner for remaining hosts and merge results as discovery source `.ping`.
                do {
                    let discoveredAfterNIO = Set(self.devices.filter { $0.isOnline }.map { $0.ipAddress })
                    print("[ScanViewModel] Running ICMP fallback, skipping already-discovered: \(discoveredAfterNIO.count) ips")
                    let icmpScanner = SystemPingScanner()
                    _ = try await icmpScanner.scanSubnet(info: info, concurrency: 16, skipIPs: discoveredAfterNIO) { progress in
                        Task { @MainActor in self.progressText = "ICMP: \(progress.scanned)/\(totalHosts)" }
                    } onDeviceFound: { device in
                        Task { @MainActor in
                            await self.updateDevice(ipAddress: device.ipAddress, arpMap: arpMap, isOnline: true, discoverySource: .ping)
                        }
                    }
                    print("[ScanViewModel] ICMP fallback complete.")
                } catch {
                    print("[ScanViewModel] ICMP fallback failed: \(error)")
                }

                await MainActor.run {
                    self.isScanning = false
                    self.progressText = "Scan complete."
                    print("✅ Scan complete! Final device count: \(devices.count)")
                    print("📋 Final devices: \(devices.map { $0.ipAddress })")
                }
                
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.progressText = "Scan failed or cancelled."
                }
            }
        }
    }
    
    func priority(for source: DiscoverySource) -> Int {
        switch source {
        case .mdns: return 4
        case .ssdp: return 3
        case .arp:  return 2
        case .nio:  return 1
        case .ping: return 0
        case .unknown: fallthrough
        default: return -1
        }
    }

    @MainActor
    func updateDevice(ipAddress: String, arpMap: [String: String], isOnline: Bool, hostname: String? = nil, services: [NetworkService] = [], openPorts: [Int] = [], discoverySource: DiscoverySource = .unknown) async {
        print("🔄 updateDevice called for IP: \(ipAddress), online: \(isOnline)")

        // Ignore loopback/localhost addresses - they should not appear in the device list
        let loopbacks: Set<String> = ["127.0.0.1", "::1", "localhost"]
        if loopbacks.contains(ipAddress) {
            print("⛔ Skipping loopback address: \(ipAddress)")
            return
        }

        // Ignore the network broadcast address if we can compute it from detected network info
        if let info = networkInfo, let ipAddr = IPv4.parse(info.ip), let mask = IPv4.parse(info.netmask) {
            let bcast = IPv4.broadcast(ip: ipAddr, mask: mask)
            let bcastStr = IPv4.format(bcast)
            if ipAddress == bcastStr {
                print("⛔ Skipping broadcast address: \(ipAddress)")
                return
            }
        }
        
        // Convert [Int] to [Port]
        let ports: [Port] = openPorts.map { Port(number: $0, serviceName: "unknown", description: "Port \($0)", status: .open) }
        
        if let index = devices.firstIndex(where: { $0.ipAddress == ipAddress }) {
            print("📝 Updating existing device at index \(index)")

            // Respect discovery source priority: only update discoverySource if incoming source has equal/higher priority
            let currentPriority = priority(for: devices[index].discoverySource)
            let incomingPriority = priority(for: discoverySource)
            if incomingPriority >= currentPriority {
                devices[index].discoverySource = discoverySource
            }

            devices[index].isOnline = isOnline
            if let hn = hostname, (devices[index].hostname == nil || devices[index].hostname?.isEmpty == true) {
                devices[index].hostname = hn
            }
            // Merge incoming open ports; avoid clobbering existing ports when incoming is empty
            if !ports.isEmpty {
                var merged = devices[index].openPorts
                for p in ports {
                    if !merged.contains(where: { $0.number == p.number }) {
                        merged.append(p)
                    }
                }
                devices[index].openPorts = merged
            }
            // Merge incoming services (avoid duplicates by ServiceType + port)
            for svc in services {
                if !devices[index].services.contains(where: { $0.type == svc.type && $0.port == svc.port }) {
                    devices[index].services.append(svc)
                }
            }
            // Update MAC/manufacturer if present in the ARP map
            var vendor: String? = devices[index].manufacturer
            if let mac = arpMap[ipAddress] {
                devices[index].macAddress = mac
                vendor = await self.ouiService.findVendor(for: mac)
                devices[index].manufacturer = vendor
            }

            // Re-classify based on hostname/vendor/ports/services with confidence scoring
            let (classified, confidence) = await classifier.classifyWithConfidence(
                hostname: devices[index].hostname,
                vendor: vendor,
                openPorts: devices[index].openPorts,
                services: devices[index].services
            )
            devices[index].deviceType = classified
            devices[index].confidence = confidence

            // Generate fingerprints
            let fingerprints = await classifier.fingerprintServices(
                services: devices[index].services,
                openPorts: devices[index].openPorts
            )
            devices[index].fingerprints = fingerprints

            // Persist classification if we have a model context and the classification is meaningful
            if classified != .unknown {
                Task { await self.updatePersistentDevice(id: devices[index].id, ipAddress: devices[index].ipAddress, macAddress: devices[index].macAddress, vendor: vendor, deviceType: classified) }
            }
            print("✅ Updated device: \(devices[index].name) (\(ipAddress))")
            // Attempt reverse DNS if hostname is unknown
            if devices[index].hostname == nil {
                resolveHostnameIfPossible(for: ipAddress)
            }
        } else {
            print("🆕 Creating new device for IP: \(ipAddress)")
            let vendor = arpMap[ipAddress] != nil ? await self.ouiService.findVendor(for: arpMap[ipAddress]!) : nil
            // Deduplicate incoming services by (type, port) and prefer longer names
            var uniqueByKey: [String: NetworkService] = [:]
            for svc in services {
                let key = "\(svc.type.rawValue)-\(svc.port ?? -1)"
                if let existing = uniqueByKey[key] {
                    if svc.name.count > existing.name.count { uniqueByKey[key] = svc }
                } else {
                    uniqueByKey[key] = svc
                }
            }
            let uniqueServices = Array(uniqueByKey.values)
            
            let (classifiedType, confidence) = await classifier.classifyWithConfidence(
                hostname: nil, 
                vendor: vendor, 
                openPorts: ports,
                services: uniqueServices
            )
            
            // Generate fingerprints
            let fingerprints = await classifier.fingerprintServices(
                services: uniqueServices,
                openPorts: ports
            )

            let friendlyName: String
            if let vendor = vendor {
                friendlyName = vendor
            } else if classifiedType != .unknown {
                friendlyName = classifiedType.rawValue.capitalized
            } else {
                friendlyName = ipAddress
            }

            let newDevice = Device(
                id: ipAddress,
                name: friendlyName,
                ipAddress: ipAddress,
                discoverySource: discoverySource,
                rttMillis: nil,
                hostname: hostname,
                macAddress: arpMap[ipAddress],
                deviceType: classifiedType,
                manufacturer: vendor,
                isOnline: isOnline,
                services: uniqueServices,
                firstSeen: Date(),
                lastSeen: Date(),
                openPorts: ports,
                confidence: confidence,
                fingerprints: fingerprints
            )
            devices.append(newDevice)
            print("✅ Added new device: \(newDevice.name) (\(ipAddress))")
            // Persist the device if we have a model context and the classification is meaningful
            if classifiedType != .unknown {
                Task { await self.createPersistentDevice(id: newDevice.id, ipAddress: newDevice.ipAddress, macAddress: newDevice.macAddress, vendor: newDevice.manufacturer, deviceType: classifiedType) }
            }

            // Kick off a background port scan for this device (only once)
            startPortScanIfNeeded(for: ipAddress)
            // Attempt reverse DNS if hostname is unknown
            resolveHostnameIfPossible(for: ipAddress)
        }
        // Keep device list sorted by numeric IP ascending
        devices.sort { a, b in
            guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
            return aa < bb
        }

        print("📊 Device list now has \(devices.count) devices")
        print("📋 Current devices: \(devices.map { $0.ipAddress })")

        // Update derived counts and notify UI
        updateCounts()

        // Force UI update
        print("🔄 Sending objectWillChange notification")
        objectWillChange.send()
    }

    // Reverse DNS lookup to populate hostname and trigger re-classification
    private func resolveHostnameIfPossible(for ip: String) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            _ = ip.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var sa = unsafeBitCast(addr, to: sockaddr.self)
            let r = withUnsafePointer(to: &sa) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { p in
                    getnameinfo(p, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                }
            }
            if r == 0 {
                let name = String(cString: host)
                await MainActor.run {
                    if let idx = self.devices.firstIndex(where: { $0.ipAddress == ip }) {
                        self.devices[idx].hostname = name
                        // Reclassify with hostname
                        Task { [weak self] in
                            guard let self = self else { return }
                            let d = self.devices[idx]
                            let (t, conf) = await self.classifier.classifyWithConfidence(
                                hostname: d.hostname,
                                vendor: d.manufacturer,
                                openPorts: d.openPorts,
                                services: d.services
                            )
                            await MainActor.run {
                                self.devices[idx].deviceType = t
                                self.devices[idx].confidence = conf
                                if self.devices[idx].name == self.devices[idx].ipAddress {
                                    if let vendor = self.devices[idx].manufacturer { self.devices[idx].name = vendor }
                                    else if t != .unknown { self.devices[idx].name = t.rawValue.capitalized }
                                }
                                self.objectWillChange.send()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func createPersistentDevice(id: String, ipAddress: String, macAddress: String?, vendor: String?, deviceType: DeviceType) async {
    guard let ctx = modelContext else { return }
    let newDevice = PersistentDevice(id: id, ipAddress: ipAddress, macAddress: macAddress, vendor: vendor, deviceType: deviceType.rawValue, firstSeen: Date(), lastSeen: Date())
    ctx.insert(newDevice)
    try? ctx.save()
    }
    
    private func updatePersistentDevice(id: String, ipAddress: String, macAddress: String?, vendor: String?, deviceType: DeviceType) async {
        guard let ctx = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<PersistentDevice>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(fetchDescriptor).first {
            existing.ipAddress = ipAddress
            existing.lastSeen = Date()
            if vendor != nil { existing.vendor = vendor }
            if deviceType != .unknown { existing.deviceType = deviceType.rawValue }
            try? ctx.save()
        }
    }

    func fetchDevicesFromDB(markAsOffline: Bool = false) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PersistentDevice>(sortBy: [SortDescriptor(\.ipAddress, comparator: .lexical)])
        do {
            let persistentDevices = try ctx.fetch(descriptor)
            self.devices = persistentDevices.map { convertToTransient($0, isOnline: !markAsOffline) }
            // Sort numerically by IP
            self.devices.sort { a, b in
                guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
                return aa < bb
            }
            updateCounts()
        } catch {
            print("[ScanViewModel] Error fetching devices from DB: \(error)")
        }
    }
    
    private func convertToTransient(_ persistentDevice: PersistentDevice, isOnline: Bool) -> Device {
        return Device(
            id: persistentDevice.id,
            name: persistentDevice.hostname ?? persistentDevice.vendor ?? persistentDevice.ipAddress,
            ipAddress: persistentDevice.ipAddress,
            rttMillis: nil,
            hostname: persistentDevice.hostname,
            macAddress: persistentDevice.macAddress,
            deviceType: DeviceType(rawValue: persistentDevice.deviceType ?? "unknown") ?? .unknown,
            manufacturer: persistentDevice.vendor,
            isOnline: isOnline,
            services: [],
            firstSeen: persistentDevice.firstSeen,
            lastSeen: persistentDevice.lastSeen,
            openPorts: []
        )
    }

    private func updateCounts() {
        deviceCount = devices.count
        onlineCount = devices.filter { $0.isOnline }.count
        servicesCount = devices.reduce(0) { $0 + $1.services.count }
    }

    func cancelScan() {
        scanTask?.cancel()
        // Cancel any in-flight port scan tasks and clear state
        for (_, task) in portScanTasks { task.cancel() }
        portScanTasks.removeAll()
        portScanInProgress.removeAll()
    }

    private func startPortScanIfNeeded(for ip: String) {
        guard !portScanInProgress.contains(ip) && !portScanCompleted.contains(ip) else { return }
        portScanInProgress.insert(ip)

        let task = Task { [weak self] in
            guard let self = self else { return }
            let scanner = self.portScannerFactory(ip)
            let openPorts = await scanner.scanPorts(portRange: 1...1024)
            await MainActor.run {
                // Find device and merge open ports and derived services
                if let idx = self.devices.firstIndex(where: { $0.ipAddress == ip }) {
                    // Merge ports
                    for port in openPorts {
                        if !self.devices[idx].openPorts.contains(where: { $0.number == port.number }) {
                            self.devices[idx].openPorts.append(port)
                        }
                    }
                    // Create NetworkService entries from ports using ServiceCatalog mapping
                    for port in openPorts {
                        let svcType: ServiceType = ServiceMapper.type(forPort: port.number)
                        let svc = NetworkService(name: port.serviceName, type: svcType, port: port.number)
                        if !self.devices[idx].services.contains(where: { $0.type == svc.type && $0.port == svc.port }) {
                            self.devices[idx].services.append(svc)
                        }
                    }
                    // Re-classify after new evidence (ports/services) is added
                    Task { [weak self] in
                        guard let self = self else { return }
                        let d = self.devices[idx]
                        let (newType, conf) = await self.classifier.classifyWithConfidence(
                            hostname: d.hostname,
                            vendor: d.manufacturer,
                            openPorts: d.openPorts,
                            services: d.services
                        )
                        let fps = await self.classifier.fingerprintServices(services: d.services, openPorts: d.openPorts)
                        await MainActor.run {
                            self.devices[idx].deviceType = newType
                            self.devices[idx].confidence = conf
                            self.devices[idx].fingerprints = fps
                            if self.devices[idx].name == self.devices[idx].ipAddress {
                                if let vendor = self.devices[idx].manufacturer { self.devices[idx].name = vendor }
                                else if newType != .unknown { self.devices[idx].name = newType.rawValue.capitalized }
                            }
                        }
                    }
                    self.updateCounts()
                    self.objectWillChange.send()
                }
                self.portScanInProgress.remove(ip)
                self.portScanCompleted.insert(ip)
                self.portScanTasks.removeValue(forKey: ip)
            }
        }
        portScanTasks[ip] = task
    }
}
