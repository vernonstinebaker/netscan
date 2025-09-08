import Foundation
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

    // Published property for sorted devices by IP address
    @Published var sortedDevices: [Device] = []

    // Update sorted devices whenever devices array changes
    private func updateSortedDevices() {
        sortedDevices = devices.sorted { a, b in
            guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else {
                return a.ipAddress < b.ipAddress
            }
            return aa < bb
        }
    }

    private let modelContext: ModelContext?
    private let arpParser = ARPTableParser()
    private let classifier = DeviceClassifier()
    private let ouiService = OUILookupService.shared
    private let macDiscoverer = MACAddressDiscoverer()
    private let dnsLookupService = DNSReverseLookupService()
    private let ntpDiscoverer = NTPDiscoverer()
    private let sshFingerprintService = SSHFingerprintService()
    private let netbiosDiscoverer = NetBIOSDiscoverer()
    private let networkScanner = NetworkScanner()
    private let portScannerFactory: (String) -> PortScanning
    private var portScanInProgress: Set<String> = []
    private var portScanCompleted: Set<String> = []
    private var portScanTasks: [String: Task<Void, Never>] = [:]
    private var scanTask: Task<Void, Error>?
    private var persistTask: Task<Void, Never>? = nil
    private var currentNetworkKey: String? = nil

    init(modelContext: ModelContext? = nil, portScannerFactory: @escaping (String) -> PortScanning = { host in PortScanner(host: host) }) {
        self.modelContext = modelContext
        self.portScannerFactory = portScannerFactory

        if modelContext != nil {
            fetchDevicesFromDB(markAsOffline: true)
        }
    }

    func detectNetwork() {
        networkInfo = NetworkInterface.currentIPv4()
        Task { await loadFromKVSIfAvailable() }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] note in
            guard let self = self else { return }
            Task { await self.handleKVSChange(note) }
        }

        // Force local network permission prompt by attempting a basic Bonjour operation
        Task {
            debugLog("ScanViewModel: Attempting to trigger local network permission prompt")
            let browser = NetServiceBrowser()
            browser.searchForServices(ofType: "_http._tcp", inDomain: "local.")
            // Stop immediately to just trigger the permission prompt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                browser.stop()
                debugLog("ScanViewModel: Stopped test browser to trigger permission prompt")
            }
        }
    }

    func startScan() {
        guard !isScanning else { return }

        isScanning = true
        progressText = "Starting scan..."

        scanTask = Task {
            do {
                detectNetwork()
                guard let info = networkInfo else { return }

        // Bonjour should work on iOS with proper entitlements, but may need longer timeouts
        async let bonjourTask = BonjourDiscoverer().discover(timeout: 6.0)
        async let ssdpTask = SSDPDiscoverer().discover(timeout: 5.0)
        async let wsTask = WSDiscoveryDiscoverer().discover(timeout: 4.0)
        async let arpEntriesTask = arpParser.getARPTable()

                 let bonjourResults = await bonjourTask
                 print("[DEBUG] Bonjour discovery found \(bonjourResults.count) devices")
                 if !bonjourResults.isEmpty {
                     for (ip, host) in bonjourResults {
                         try Task.checkCancellation()
                         print("[DEBUG] Bonjour found device: \(ip) hostname: \(host.hostname ?? "unknown") services: \(host.services.count)")
                         await updateDevice(ipAddress: ip, arpMap: [:], isOnline: true, hostname: host.hostname, services: host.services, discoverySource: .mdns)
                     }
                 } else {
                     print("[DEBUG] Bonjour discovery returned 0 devices")
                 }

                 let ssdpResults = await ssdpTask
                 print("[DEBUG] SSDP discovery found \(ssdpResults.ips.count) devices: \(ssdpResults.ips)")
                 if !ssdpResults.ips.isEmpty {
                     for ip in ssdpResults.ips {
                         try Task.checkCancellation()
                         print("[DEBUG] SSDP found device: \(ip)")
                         await updateDevice(ipAddress: ip, arpMap: [:], isOnline: true, discoverySource: .ssdp)
                     }
                 } else {
                     print("[DEBUG] SSDP discovery returned 0 devices")
                 }

                 let wsResults = await wsTask
                 print("[DEBUG] WS-Discovery found \(wsResults.ips.count) devices: \(wsResults.ips)")
                 if !wsResults.ips.isEmpty {
                     for ip in wsResults.ips {
                         try Task.checkCancellation()
                         print("[DEBUG] WS-Discovery found device: \(ip)")
                         await updateDevice(ipAddress: ip, arpMap: [:], isOnline: true)
                     }
                 } else {
                     print("[DEBUG] WS-Discovery returned 0 devices")
                 }

                let arpEntries = await arpEntriesTask
                let arpMap = arpEntries.reduce(into: [String: String]()) { $0[$1.ipAddress] = $1.macAddress }
                if !arpEntries.isEmpty {
                    for entry in arpEntries {
                        try Task.checkCancellation()
                        if let existing = devices.first(where: { $0.ipAddress == entry.ipAddress }) {
                            await updateDevice(ipAddress: entry.ipAddress, arpMap: arpMap, isOnline: existing.isOnline, discoverySource: .arp)
                        } else {
                            await updateDevice(ipAddress: entry.ipAddress, arpMap: arpMap, isOnline: true, discoverySource: .arp)
                        }
                    }
                }

                guard let ip = IPv4.parse(info.ip), let mask = IPv4.parse(info.netmask) else {
                    print("[ERROR] Invalid IP address or netmask: \(info.ip)/\(info.netmask)")
                    return
                }
                let totalHosts = IPv4.hosts(inNetwork: IPv4.network(ip: ip, mask: mask), mask: mask).count

                let alreadyOnlineIPs = Set(devices.filter { $0.isOnline }.map { $0.ipAddress })
                progressText = "Discovering new devices..."

                let total = totalHosts
                let effectiveConcurrency: Int = {
                    if total <= 256 { return 64 }
                    if total <= 1024 { return 32 }
                    return 16
                }()
                let devices = await self.networkScanner.scanSubnet(info: info, concurrency: effectiveConcurrency) { progress in
                    Task { @MainActor in self.progressText = "Port Scan: \(progress.scanned)/\(totalHosts)" }
                }
                 for device in devices {
                     if !alreadyOnlineIPs.contains(device.ipAddress) {
                         await self.updateDevice(ipAddress: device.ipAddress, arpMap: arpMap, isOnline: true, openPorts: device.openPorts.map { $0.number }, discoverySource: .ping)
                     }
                 }

                do {
                    let discoveredAfterNIO = Set(self.devices.filter { $0.isOnline }.map { $0.ipAddress })
                    let icmpScanner = SystemPingScanner()
                    _ = try await icmpScanner.scanSubnet(info: info, concurrency: 16, skipIPs: discoveredAfterNIO) { _ in } onDeviceFound: { device in
                        Task { @MainActor in
                            await self.updateDevice(ipAddress: device.ipAddress, arpMap: arpMap, isOnline: true, discoverySource: .ping)
                        }
                    }
                } catch {
                    // ignore
                }

                await MainActor.run {
                    self.isScanning = false
                    self.progressText = "Scan complete."
                }
                await self.persistToKVS()

            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.progressText = "Scan failed or cancelled."
                }
            }
        }
    }

    // MARK: - iCloud KVS persistence
    private func loadFromKVSIfAvailable() async {
        guard let info = networkInfo else { return }
        let key = DeviceKVStore.networkKey(info: info)
        currentNetworkKey = key
        let snapshots = DeviceKVStore.loadSnapshots(for: key)
        print("[DEBUG] Loaded \(snapshots.count) snapshots from KV store for network: \(key)")
        guard !snapshots.isEmpty else {
            print("[DEBUG] No snapshots found in KV store")
            return
        }
        for snap in snapshots {
            if devices.contains(where: { $0.id == snap.id }) { continue }
            if devices.contains(where: { $0.macAddress == snap.mac && $0.macAddress != nil }) { continue }
            let discoverySource = snap.discoverySource.flatMap { DiscoverySource(rawValue: $0) } ?? .unknown
            let d = Device(
                id: snap.id,
                name: snap.vendor ?? snap.hostname ?? snap.ip,
                ipAddress: snap.ip,
                discoverySource: discoverySource,
                rttMillis: nil,
                hostname: snap.hostname,
                macAddress: snap.mac,
                deviceType: DeviceType(rawValue: snap.deviceType ?? "unknown") ?? .unknown,
                manufacturer: snap.vendor,
                isOnline: false,
                services: snap.services,
                firstSeen: snap.firstSeen,
                lastSeen: snap.lastSeen,
                openPorts: []
            )
            devices.append(d)
        }
        devices.sort { a, b in
            guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
            return aa < bb
        }
        updateCounts()
        updateSortedDevices()

        // Start parallel ping operations to update online status
        for d in devices {
            Task { [weak self] in
                guard let self = self else { return }
                if let (isAlive, _) = await SimplePing.ping(host: d.ipAddress, timeout: 1.0), isAlive {
                    print("[DEBUG] Ping success for \(d.ipAddress)")
                    await self.updateDevice(ipAddress: d.ipAddress, arpMap: [:], isOnline: true, discoverySource: .ping)
                    await MainActor.run { self.startPortScanIfNeeded(for: d.ipAddress) }
                } else {
                    print("[DEBUG] Ping failed for \(d.ipAddress)")
                }
            }
        }
    }

    private func schedulePersistToKVS() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            // Wait 2 seconds before persisting to batch multiple rapid updates
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.persistToKVS()
        }
    }

    func persistToKVS() async {
        guard let info = networkInfo else {
            print("[DEBUG] Cannot persist to KV store: no network info")
            return
        }
        let key = currentNetworkKey ?? DeviceKVStore.networkKey(info: info)
        print("[DEBUG] Persisting \(devices.count) devices to KV store for key: \(key)")
        let snaps: [DeviceSnapshot] = devices.map { d in
            DeviceSnapshot(
                id: d.id,
                ip: d.ipAddress,
                mac: d.macAddress,
                hostname: d.hostname,
                vendor: d.manufacturer,
                deviceType: d.deviceType == .unknown ? nil : d.deviceType.rawValue,
                name: d.name == d.ipAddress ? nil : d.name,
                firstSeen: d.firstSeen ?? Date(),
                lastSeen: d.lastSeen ?? Date(),
                services: d.services,
                discoverySource: d.discoverySource == .unknown ? nil : d.discoverySource.rawValue
            )
        }
        DeviceKVStore.saveSnapshots(snaps, for: key)
    }

    @MainActor
    private func handleKVSChange(_ note: Notification) async {
        guard let info = networkInfo else { return }
        let key = currentNetworkKey ?? DeviceKVStore.networkKey(info: info)
        let incoming = DeviceKVStore.loadSnapshots(for: key)
        guard !incoming.isEmpty else { return }
        mergeSnapshots(incoming)
        updateCounts()
    }

    @MainActor
    private func mergeSnapshots(_ snaps: [DeviceSnapshot]) {
        for snap in snaps {
            if let idx = devices.firstIndex(where: { $0.id == snap.id || $0.ipAddress == snap.ip || ($0.macAddress == snap.mac && $0.macAddress != nil) }) {
                if let fs = devices[idx].firstSeen { devices[idx].firstSeen = min(fs, snap.firstSeen) } else { devices[idx].firstSeen = snap.firstSeen }
                if let ls = devices[idx].lastSeen { devices[idx].lastSeen = max(ls, snap.lastSeen) } else { devices[idx].lastSeen = snap.lastSeen }
                if (devices[idx].hostname == nil || devices[idx].hostname?.isEmpty == true), let hn = snap.hostname, !hn.isEmpty { devices[idx].hostname = hn }
                if (devices[idx].manufacturer == nil || devices[idx].manufacturer?.isEmpty == true), let v = snap.vendor, !v.isEmpty { devices[idx].manufacturer = v }
                if devices[idx].deviceType == .unknown, let t = snap.deviceType, let dt = DeviceType(rawValue: t) { devices[idx].deviceType = dt }
                if devices[idx].name == devices[idx].ipAddress, let nm = snap.name, !nm.isEmpty { devices[idx].name = nm }
            } else {
            let discoverySource = snap.discoverySource.flatMap { DiscoverySource(rawValue: $0) } ?? .unknown
            let d = Device(
                id: snap.id,
                name: snap.vendor ?? snap.hostname ?? snap.ip,
                ipAddress: snap.ip,
                discoverySource: discoverySource,
                rttMillis: nil,
                hostname: snap.hostname,
                macAddress: snap.mac,
                deviceType: DeviceType(rawValue: snap.deviceType ?? "unknown") ?? .unknown,
                manufacturer: snap.vendor,
                isOnline: false,
                services: snap.services,
                firstSeen: snap.firstSeen,
                lastSeen: snap.lastSeen,
                openPorts: []
            )
                devices.append(d)
            }
        }
        devices.sort { a, b in
            guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
            return aa < bb
        }
        updateSortedDevices()
    }

    @MainActor
    func updateDevice(ipAddress: String, arpMap: [String: String], isOnline: Bool, hostname: String? = nil, services: [NetworkService] = [], openPorts: [Int] = [], discoverySource: DiscoverySource = .unknown) async {
        print("[DEBUG] updateDevice called for \(ipAddress), online: \(isOnline), source: \(discoverySource.rawValue)")
        let loopbacks: Set<String> = ["127.0.0.1", "::1", "localhost"]
        if loopbacks.contains(ipAddress) { return }
        if let info = networkInfo, let ipAddr = IPv4.parse(info.ip), let mask = IPv4.parse(info.netmask) {
            let bcast = IPv4.broadcast(ip: ipAddr, mask: mask)
            if ipAddress == IPv4.format(bcast) { return }
        }

        let ports: [Port] = openPorts.map { Port(number: $0, serviceName: "unknown", description: "Port \($0)", status: .open) }

        // Priority order (higher index = higher priority for upgrade decisions)
        let ordered: [DiscoverySource] = [.ping, .arp, .mdns]
        let claimable: Set<DiscoverySource> = Set(ordered)
        func rank(_ s: DiscoverySource) -> Int { ordered.firstIndex(of: s) ?? -1 }

        if let index = devices.firstIndex(where: { $0.ipAddress == ipAddress }) {
            var d = devices[index]
            if claimable.contains(discoverySource) {
                let existingRank = rank(d.discoverySource)
                let incomingRank = rank(discoverySource)
                // Upgrade if: existing not claimable (unknown/nio/ssdp) OR incoming has strictly higher rank
                if !claimable.contains(d.discoverySource) || incomingRank > existingRank {
                    // Never downgrade to ping if we already have arp/mdns (handled by incomingRank > existingRank)
                    d.discoverySource = discoverySource
                }
            }

            d.isOnline = isOnline
            if !ports.isEmpty {
                var merged = d.openPorts
                for p in ports where !merged.contains(where: { $0.number == p.number }) { merged.append(p) }
                d.openPorts = merged
            }
            for svc in services where !d.services.contains(where: { $0.type == svc.type && $0.port == svc.port }) { d.services.append(svc) }
            if (d.hostname == nil || d.hostname?.isEmpty == true), let hn = hostname, !hn.isEmpty { d.hostname = hn }
            if let mac = arpMap[ipAddress], !mac.isEmpty { d.macAddress = mac }
            // Enhanced MAC address and manufacturer discovery
            if d.macAddress == nil || (d.manufacturer == nil || d.manufacturer?.isEmpty == true) {
                let (macAddress, vendor, deviceInfo) = await macDiscoverer.gatherDeviceInfo(for: d.ipAddress)

                if let mac = macAddress, d.macAddress == nil {
                    d.macAddress = mac
                    print("[DEBUG] Discovered MAC address for \(d.ipAddress): \(mac)")
                }

                if let vendor = vendor, (d.manufacturer == nil || d.manufacturer?.isEmpty == true) {
                    d.manufacturer = vendor
                    print("[DEBUG] Set manufacturer for \(d.ipAddress) to: \(vendor)")
                }

                // Store additional device info if available
                if !deviceInfo.isEmpty {
                    print("[DEBUG] Additional device info for \(d.ipAddress): \(deviceInfo)")
                }
            }
            if d.firstSeen == nil { d.firstSeen = Date() }
            d.lastSeen = Date()
            devices[index] = d
        } else {
            let initialSource: DiscoverySource = claimable.contains(discoverySource) ? discoverySource : .unknown
            let newDevice = Device(
                id: ipAddress,
                name: ipAddress,
                ipAddress: ipAddress,
                discoverySource: initialSource,
                rttMillis: nil,
                hostname: hostname,
                macAddress: arpMap[ipAddress],
                deviceType: .unknown,
                manufacturer: nil,
                isOnline: isOnline,
                services: services,
                firstSeen: Date(),
                lastSeen: Date(),
                openPorts: ports
            )
            devices.append(newDevice)
        }

        updateCounts()
        // objectWillChange.send() is not needed with @Published properties
        updateSortedDevices()
        print("[DEBUG] updateDevice completed for \(ipAddress), devices count: \(devices.count), sortedDevices count: \(sortedDevices.count)")

        if let idx = devices.firstIndex(where: { $0.ipAddress == ipAddress }) {
            let deviceId = devices[idx].id
            let host = devices[idx].hostname
            let vend = devices[idx].manufacturer
            let openPortsCopy = devices[idx].openPorts
            Task.detached { [weak self] in
                guard let self = self else { return }
                let (newType, conf) = await self.classifier.classifyWithConfidence(hostname: host, vendor: vend, openPorts: openPortsCopy)
                await MainActor.run {
                    if let found = self.devices.firstIndex(where: { $0.id == deviceId }) {
                        self.devices[found].deviceType = newType
                        self.devices[found].confidence = conf
                        if openPortsCopy.isEmpty { self.startPortScanIfNeeded(for: ipAddress) }
                    }
                }
            }
        }
    }

    private func startPortScanIfNeeded(for ip: String) {
        guard !portScanInProgress.contains(ip) && !portScanCompleted.contains(ip) else { return }
        portScanInProgress.insert(ip)

        let task = Task { [weak self] in
            guard let self = self else { return }
            let scanner = self.portScannerFactory(ip)
            let openPorts = await scanner.scanPorts(portRange: 1...1024)
            await MainActor.run {
                if let idx = self.devices.firstIndex(where: { $0.ipAddress == ip }) {
                    for port in openPorts {
                        if !self.devices[idx].openPorts.contains(where: { $0.number == port.number }) {
                            self.devices[idx].openPorts.append(port)
                        }
                    }
                    for port in openPorts {
                        let svcType: ServiceType = ServiceMapper.type(forPort: port.number)
                        let svc = NetworkService(name: port.serviceName, type: svcType, port: port.number)
                        if !self.devices[idx].services.contains(where: { $0.type == svc.type && $0.port == svc.port }) {
                            self.devices[idx].services.append(svc)
                        }
                    }
                    // Capture current device state for asynchronous classification/fingerprinting
                    let deviceId2 = self.devices[idx].id
                    let servicesCopy = self.devices[idx].services
                    let openPortsCopy2 = self.devices[idx].openPorts
                    let hostnameCopy = self.devices[idx].hostname
                    let vendorCopy = self.devices[idx].manufacturer

                     Task.detached { [weak self] in
                         guard let self = self else { return }
                         print("[DEBUG] Starting device classification for \(deviceId2)")
                         // Gather additional information from multiple discovery methods
                        var enhancedServices = servicesCopy
                        var enhancedVendor = vendorCopy
                        var enhancedHostname = hostnameCopy

                        // 1. HTTP information gathering
                        for service in servicesCopy where service.type == .http || service.type == .https {
                            if let port = service.port {
                                let useHTTPS = service.type == .https
                                if let httpInfo = await HTTPInfoGatherer().gatherInfo(host: deviceId2, port: port, useHTTPS: useHTTPS) {
                                    // Add HTTP server as additional service info
                                    if let server = httpInfo.serverHeader {
                                        enhancedServices.append(NetworkService(name: "HTTP Server: \(server)", type: .http, port: port))
                                    }

                                    // Use HTTP-detected vendor if we don't have one
                                    if enhancedVendor == nil, let httpVendor = httpInfo.vendor {
                                        enhancedVendor = httpVendor
                                    }

                                    // Add device info from HTTP
                                    if let deviceType = httpInfo.deviceInfo["device_type"] {
                                        enhancedServices.append(NetworkService(name: "Device Type: \(deviceType)", type: .unknown, port: nil))
                                    }
                                }
                            }
                        }

                        // 2. DNS reverse lookup for hostname
                        if enhancedHostname == nil {
                            if let dnsInfo = await dnsLookupService.reverseLookup(deviceId2), let hostname = dnsInfo.hostname {
                                enhancedHostname = hostname
                                debugLog("[DEBUG] Found hostname via DNS: \(hostname) for \(deviceId2)")
                            }
                        }

                        // 3. NTP discovery
                        if let ntpInfo = await ntpDiscoverer.discoverNTPInfo(for: deviceId2), ntpInfo.isNTPServer {
                            enhancedServices.append(NetworkService(name: "NTP Server (Stratum \(ntpInfo.stratum ?? 0))", type: .unknown, port: 123))
                            debugLog("[DEBUG] Found NTP server: stratum \(ntpInfo.stratum ?? 0) for \(deviceId2)")
                        }

                        // 4. SSH fingerprinting
                        if let sshInfo = await sshFingerprintService.getSSHInfo(for: deviceId2), let banner = sshInfo.banner {
                            enhancedServices.append(NetworkService(name: "SSH: \(banner)", type: .ssh, port: 22))

                            // Extract OS info from SSH banner
                            if let banner = sshInfo.banner {
                                // Simple OS detection from SSH banner
                                if banner.contains("Ubuntu") {
                                    enhancedServices.append(NetworkService(name: "OS: Linux (Ubuntu)", type: .unknown, port: nil))
                                } else if banner.contains("Debian") {
                                    enhancedServices.append(NetworkService(name: "OS: Linux (Debian)", type: .unknown, port: nil))
                                } else if banner.contains("CentOS") {
                                    enhancedServices.append(NetworkService(name: "OS: Linux (CentOS)", type: .unknown, port: nil))
                                } else if banner.contains("FreeBSD") {
                                    enhancedServices.append(NetworkService(name: "OS: BSD (FreeBSD)", type: .unknown, port: nil))
                                } else if banner.contains("OpenSSH") {
                                    enhancedServices.append(NetworkService(name: "OS: Linux/Unix", type: .unknown, port: nil))
                                }
                            }

                            debugLog("[DEBUG] SSH fingerprint: \(banner) for \(deviceId2)")
                        }

                        // 5. NetBIOS discovery
                        if let netbiosInfo = await netbiosDiscoverer.discoverInfo(for: deviceId2) {
                            if let hostname = netbiosInfo.hostname {
                                if enhancedHostname == nil {
                                    enhancedHostname = hostname
                                }
                                enhancedServices.append(NetworkService(name: "NetBIOS: \(hostname)", type: .unknown, port: nil))
                            }
                            debugLog("[DEBUG] Found NetBIOS info for \(deviceId2)")
                        }

                        let (newType, conf) = await self.classifier.classifyWithConfidence(
                            hostname: hostnameCopy,
                            vendor: enhancedVendor,
                            openPorts: openPortsCopy2,
                            services: enhancedServices
                        )
                        let fps = await self.classifier.fingerprintServices(services: servicesCopy, openPorts: openPortsCopy2)
                         await MainActor.run {
                             if let found = self.devices.firstIndex(where: { $0.id == deviceId2 }) {
                                 print("[DEBUG] Classification result for \(self.devices[found].ipAddress): type=\(newType.rawValue), confidence=\(conf)")
                                 self.devices[found].deviceType = newType
                                 self.devices[found].confidence = conf
                                 self.devices[found].fingerprints = fps
                                 if self.devices[found].name == self.devices[found].ipAddress {
                                     if let hostname = self.devices[found].hostname, !hostname.isEmpty, !hostname.contains(".local"), hostname != "localhost" {
                                         self.devices[found].name = hostname
                                         print("[DEBUG] Updated device \(self.devices[found].ipAddress) name to hostname: \(hostname)")
                                     } else if let vendor = self.devices[found].manufacturer {
                                         self.devices[found].name = vendor
                                         print("[DEBUG] Updated device \(self.devices[found].ipAddress) name to vendor: \(vendor)")
                                     } else if newType != .unknown {
                                         self.devices[found].name = newType.rawValue.capitalized
                                         print("[DEBUG] Updated device \(self.devices[found].ipAddress) name to type: \(newType.rawValue.capitalized)")
                                     } else {
                                         print("[DEBUG] Could not update device \(self.devices[found].ipAddress) name - no hostname, vendor, or type available")
                                     }
                                 }
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

    private func updateCounts() {
        deviceCount = devices.count
        onlineCount = devices.filter { $0.isOnline }.count
        servicesCount = devices.reduce(0) { $0 + $1.services.count }
        updateSortedDevices()
    }

    // MARK: - Persistence with SwiftData
    private func fetchDevicesFromDB(markAsOffline: Bool = false) {
        guard let ctx = modelContext else { return }
        Task { @MainActor in
            let fetch = FetchDescriptor<PersistentDevice>()
            let list = try ctx.fetch(fetch)
            self.devices = list.map { persistent in
                Device(
                    id: persistent.id,
                    name: persistent.hostname ?? persistent.ipAddress,
                    ipAddress: persistent.ipAddress,
                    discoverySource: .unknown,
                    rttMillis: nil,
                    hostname: persistent.hostname,
                    macAddress: persistent.macAddress,
                    deviceType: DeviceType(rawValue: persistent.deviceType ?? "unknown") ?? .unknown,
                    manufacturer: persistent.vendor,
                    isOnline: !markAsOffline,
                    services: [],
                    firstSeen: persistent.firstSeen,
                    lastSeen: persistent.lastSeen,
                    openPorts: []
                )
            }
            updateCounts()
            updateSortedDevices()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        for (_, task) in portScanTasks { task.cancel() }
        portScanTasks.removeAll()
        portScanInProgress.removeAll()
    }

    func clearDevices() {
        devices.removeAll()
        sortedDevices.removeAll()
        portScanInProgress.removeAll()
        portScanCompleted.removeAll()
        portScanTasks.removeAll()

        // Also clear the persistent KV store
        DeviceKVStore.clearAll()

        updateCounts()
    }
}
