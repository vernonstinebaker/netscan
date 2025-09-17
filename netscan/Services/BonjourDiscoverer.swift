import Foundation
import Darwin

// Simple VPN detection
private func hasVPNConnection() -> Bool {
    #if os(macOS)
    // Check for common VPN interface names
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return false }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let ifa = ptr.pointee
        let name = String(cString: ifa.ifa_name)
        // Common VPN interface prefixes
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("tun") {
            return true
        }
    }
    #endif
    return false
}

// Using types from Device.swift

public struct BonjourHostResult: Sendable {
    public let hostname: String?
    public let services: [NetworkService]
    public let ipAddress: String?
    public let modelHint: String?
    public let deviceTypeHint: String? // Using String instead of DeviceType for compatibility
}

public class BonjourDiscoverer {
    private let wildcardBrowser = NetServiceBrowser()
    private var wildcardDelegate: WildcardBrowserDelegate?
    private var serviceBrowsers: [String: NetServiceBrowser] = [:]
    private var serviceDelegates: [String: ServiceBrowserDelegate] = [:]
    private var discoveredServices: [String: [NetService]] = [:]
    private var fallbackStarted = false

    public init() {
        // Set up wildcard browser delegate
        wildcardDelegate = WildcardBrowserDelegate(discoverer: self)
        wildcardBrowser.delegate = wildcardDelegate
    }

    // MARK: - Service Type Discovery

    /// Discover the available service types using DNS-SD's canonical service enumeration.
    /// Falls back to a default seed list if nothing is found within the timeout.
    public func discoverServiceTypes(timeout: TimeInterval = 1.0) async -> [String] {
        let collector = await MainActor.run { () -> ServiceTypeCollector in
            let c = ServiceTypeCollector()
            c.start()
            return c
        }
        // Wait briefly off the main actor
        try? await Task.sleep(nanoseconds: UInt64(max(0, timeout)) * 1_000_000_000)
        let discovered = await MainActor.run { () -> [String] in
            collector.stop()
            return Array(collector.types)
        }
        if !discovered.isEmpty { return discovered }
        // fallback seed list
        return [
            "_http._tcp.", "_https._tcp.", "_ssh._tcp.", "_smb._tcp.", "_afpovertcp._tcp.",
            "_device-info._tcp.", "_airplay._tcp.", "_raop._tcp.", "_ipp._tcp.", "_printer._tcp.",
            "_googlecast._tcp.", "_hap._tcp.", "_ftp._tcp.", "_workstation._tcp.", "_rfb._tcp.",
            "_miio._udp.", "_spotify-connect._tcp.", "_sftp-ssh._tcp.", "_companion-link._tcp.",
            "_remotepairing._tcp.", "_apple-mobdev2._tcp.", "_asquic._udp."
        ]
    }

    // MARK: - Advanced Discovery with Wildcard and Fallback

    /// Start wildcard browsing to discover all available service types dynamically
    private func startWildcardBrowsing() async {
        await MainActor.run {
            debugLog("BonjourDiscoverer: Starting wildcard browse _services._dns-sd._udp")
            wildcardBrowser.searchForServices(ofType: "_services._dns-sd._udp", inDomain: "local.")
        }
    }

    /// Start fallback browsers for common service types
    private func startFallbackBrowsers() async {
        guard !fallbackStarted else { return }
        fallbackStarted = true

        let types = [
            "_http._tcp.", "_https._tcp.", "_ssh._tcp.", "_smb._tcp.",
            "_afpovertcp._tcp.", "_airplay._tcp.", "_raop._tcp.", "_hap._tcp.",
            "_homekit._tcp.", "_miio._udp.", "_ipp._tcp.", "_printer._tcp.",
            "_googlecast._tcp.", "_spotify-connect._tcp.", "_rfb._tcp.",
            "_sftp-ssh._tcp.", "_companion-link._tcp.", "_remotepairing._tcp.",
            "_apple-mobdev2._tcp.", "_asquic._udp."
        ]

        await MainActor.run {
            debugLog("BonjourDiscoverer: Starting fallback browse for \(types.count) service types")
            for type in types where serviceBrowsers[type] == nil {
                let delegate = ServiceBrowserDelegate(discoverer: self, serviceType: type)
                serviceDelegates[type] = delegate  // Store delegate first
                let browser = NetServiceBrowser()
                browser.delegate = delegate
                serviceBrowsers[type] = browser
                debugLog("BonjourDiscoverer: Created browser for type: \(type)")
                browser.searchForServices(ofType: type, inDomain: "local.")
            }
        }
    }

    /// Handle discovered service type from wildcard browsing
    func handleDiscoveredServiceType(_ service: NetService) {
        let name = service.name
        guard !name.isEmpty else { return }
        let type = name.hasSuffix(".") ? name : name + "."
        guard serviceBrowsers[type] == nil else { return }

        debugLog("BonjourDiscoverer: Discovered new service type: \(type)")
        Task {
            await MainActor.run {
                let delegate = ServiceBrowserDelegate(discoverer: self, serviceType: type)
                serviceDelegates[type] = delegate  // Store delegate first
                let browser = NetServiceBrowser()
                browser.delegate = delegate
                serviceBrowsers[type] = browser
                browser.searchForServices(ofType: type, inDomain: "local.")
            }
        }
    }

    /// Handle discovered service instance
    func handleDiscoveredService(_ service: NetService, serviceType: String) {
        let delegate = DiscovererServiceDelegate(discoverer: self)
        service.delegate = delegate
        service.resolve(withTimeout: 5.0)

        if discoveredServices[serviceType] == nil {
            discoveredServices[serviceType] = []
        }
        discoveredServices[serviceType]?.append(service)
        debugLog("BonjourDiscoverer: Found service instance: \(service.name) (\(serviceType))")
    }

    /// Handle service resolution
    func handleServiceResolved(_ service: NetService) {
        debugLog("BonjourDiscoverer: Resolved service \(service.name) - extracting addresses")
        // This will be handled by the collector in the main discover method
    }

    /// Clean up browsers
    func cleanup() {
        wildcardBrowser.stop()
        serviceBrowsers.values.forEach { $0.stop() }
        serviceBrowsers.removeAll()
        discoveredServices.removeAll()
        fallbackStarted = false
    }

    // MARK: - ARP Subnet Scanning Fallback

    /// Check if VPN is active and start ARP scanning if needed
    private func checkForVPNAndStartARP() async {
        if hasVPNConnection() {
            debugLog("BonjourDiscoverer: VPN detected, starting ARP subnet scanning as fallback")
            await startARPSubnetScanning()
        }
    }

    /// Start ARP subnet scanning
    private func startARPSubnetScanning() async {
        do {
            let subnetIPs = try getLocalSubnetIPs()
            debugLog("BonjourDiscoverer: Scanning subnet with \(subnetIPs.count) IPs via ARP")

            await withTaskGroup(of: Void.self) { group in
                for ip in subnetIPs {
                    group.addTask {
                        await self.pingAndDiscoverDevice(at: ip)
                    }
                }
            }
        } catch {
            debugLog("BonjourDiscoverer: Subnet scanning failed: \(error.localizedDescription)")
        }
    }

    /// Get local subnet IP addresses
    private func getLocalSubnetIPs() throws -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get network interfaces"])
        }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP else { continue }
            guard (flags & IFF_LOOPBACK) != IFF_LOOPBACK else { continue }
            guard ifa.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var addr = ifa.ifa_addr.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = getnameinfo(&addr, socklen_t(addr.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard r == 0, let ip = String(validatingUTF8: host) else { continue }

            let name = String(cString: ifa.ifa_name)
            if name.hasPrefix("en") { // Prefer Ethernet/WiFi interfaces
                return try calculateSubnetIPs(from: ip)
            }
        }
        throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "No suitable network interface found"])
    }

    /// Calculate all IP addresses in the same subnet
    private func calculateSubnetIPs(from ip: String) throws -> [String] {
        let components = ip.split(separator: ".")
        guard components.count == 4 else {
            throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid IP address format"])
        }

        let baseIP = "\(components[0]).\(components[1]).\(components[2])."
        var ips: [String] = []

        // Scan .1 to .254 (excluding .0 and .255 which are network/broadcast)
        for i in 1...254 {
            if i != Int(components[3]) ?? 0 { // Exclude our own IP
                ips.append("\(baseIP)\(i)")
            }
        }
        return ips
    }

    /// Ping and discover device at IP address
    private func pingAndDiscoverDevice(at ip: String) async {
        // Simple ping implementation
        let isAlive = await simplePing(host: ip, timeout: 1.0)
        if isAlive {
            debugLog("BonjourDiscoverer: Found alive host via ping: \(ip)")

            // Try to get MAC address
            if let mac = await getMACAddress(for: ip) {
                debugLog("BonjourDiscoverer: Found MAC \(mac) for \(ip)")
                // Try to get vendor
                if let vendor = await getVendor(for: mac) {
                    debugLog("BonjourDiscoverer: Found vendor \(vendor) for MAC \(mac)")
                }
            }

            // In a real implementation, we would create a Device here and add it to results
            // For now, just log the discovery
        }
    }

    /// Simple ping implementation
    private func simplePing(host: String, timeout: TimeInterval) async -> Bool {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "1", host]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
        #else
        // On iOS, we can't use system ping easily, so return false for now
        return false
        #endif
    }

    // MARK: - MAC Address and Vendor Lookup

    /// Get MAC address for an IP using ARP
    private func getMACAddress(for ip: String) async -> String? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            return parseMACFromARP(output)
        } catch {
            debugLog("BonjourDiscoverer: ARP command failed: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Parse MAC address from ARP command output
    private func parseMACFromARP(_ output: String) -> String? {
        guard !output.contains("incomplete") else { return nil }
        let pattern = "at ([0-9a-f:]{17})"
        if let range = output.range(of: pattern, options: .regularExpression) {
            return String(output[range]).replacingOccurrences(of: "at ", with: "")
        }
        return nil
    }

    /// Get vendor for MAC address using OUI lookup
    private func getVendor(for mac: String) async -> String? {
        // This would use OUILookupService in a real implementation
        // For now, return a placeholder
        debugLog("BonjourDiscoverer: Would lookup vendor for MAC: \(mac)")
        return nil
    }

    public func discover(timeout: TimeInterval = 4.0, serviceTypes: [String]? = nil) async -> [String: BonjourHostResult] {
        let types: [String]
        if let provided = serviceTypes {
            types = provided
        } else {
            // Use comprehensive service types for better discovery
            types = await discoverServiceTypes()
        }

        await MainActor.run {
            debugLog("BonjourDiscoverer: Starting enhanced discovery with \(types.count) service types")
        }

        // Start wildcard browsing and fallback browsers
        await startWildcardBrowsing()
        await startFallbackBrowsers()

        // Check for VPN and start ARP scanning if needed
        await checkForVPNAndStartARP()

        return await withCheckedContinuation { continuation in
            // Bonjour operations must be done on main thread
            DispatchQueue.main.async {
                let collector = EnhancedBonjourCollector(serviceTypes: types, discoverer: self)
                Task { @MainActor in
                    debugLog("BonjourDiscoverer: Created enhanced collector on main thread")
                }

                collector.start()
                Task { @MainActor in
                    debugLog("BonjourDiscoverer: Started enhanced collector")
                }

                // Wait for the timeout period
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    Task { @MainActor in
                        debugLog("BonjourDiscoverer: Timeout reached, stopping collector")
                        collector.stop()
                        let results = collector.collected
                        debugLog("BonjourDiscoverer: Found \(results.count) results: \(results.keys)")

                        // Clean up browsers
                        Task {
                            self.cleanup()
                        }

                        continuation.resume(returning: results)
                    }
                }
            }
        }
    }
}

private final class EnhancedBonjourCollector: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let serviceTypes: [String]
    private let discoverer: BonjourDiscoverer
    private var browsers: [NetServiceBrowser] = []
    private var browserDelegates: [BrowserDelegate] = []
    private var services: Set<NetService> = []
    private var serviceDelegates: [ServiceDelegate] = []
    // Map IP -> hostname + [NetworkService]
    private(set) var collected: [String: BonjourHostResult] = [:]

    init(serviceTypes: [String], discoverer: BonjourDiscoverer) {
        self.serviceTypes = serviceTypes
        self.discoverer = discoverer
    }

    func start() {
        debugLog("EnhancedBonjourCollector: Starting \(serviceTypes.count) service browsers")
        for type in serviceTypes {
            let browser = NetServiceBrowser()
            let delegate = BrowserDelegate(collector: self, serviceType: type)
            browser.delegate = delegate
            browsers.append(browser)
            browserDelegates.append(delegate)
            debugLog("EnhancedBonjourCollector: Created browser for type: \(type)")
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
        debugLog("EnhancedBonjourCollector: All browsers started (\(browsers.count) total)")
    }

    func stop() {
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        services.forEach { $0.stop() }
        services.removeAll()
    }

    // NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        debugLog("EnhancedBonjourCollector: Found service: \(service.name) (\(service.type)) at \(service.hostName ?? "unknown")")

        // If the service already has addresses, we can process it immediately
        if let addresses = service.addresses, !addresses.isEmpty {
            debugLog("EnhancedBonjourCollector: Service \(service.name) already has addresses, processing directly")
            processServiceAddresses(service)
        } else {
            // Otherwise, resolve it
            let serviceDelegate = ServiceDelegate(collector: self)
            service.delegate = serviceDelegate
            services.insert(service)
            serviceDelegates.append(serviceDelegate)
            debugLog("EnhancedBonjourCollector: Resolving service \(service.name) with 5.0s timeout")
            service.resolve(withTimeout: 5.0)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        debugLog("EnhancedBonjourCollector: Browser failed to search: \(errorDict)")
        for (key, value) in errorDict {
            debugLog("EnhancedBonjourCollector: Error \(key): \(value)")
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        debugLog("EnhancedBonjourCollector: Browser stopped search")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        debugLog("EnhancedBonjourCollector: Removed service: \(service.name)")
        services.remove(service)
    }

    // NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        debugLog("EnhancedBonjourCollector: Resolved service \(sender.name) - extracting IP addresses")
        processServiceAddresses(sender)
    }

    private func processServiceAddresses(_ service: NetService) {
        guard let addrs = service.addresses else {
            debugLog("EnhancedBonjourCollector: No addresses for service \(service.name)")
            return
        }

        for data in addrs {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress else { return }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                if sa.pointee.sa_family == sa_family_t(AF_INET) {
                    var sin = sockaddr_in()
                    memcpy(&sin, sa, MemoryLayout<sockaddr_in>.size)
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    var sinCopy = sin
                    withUnsafePointer(to: &sinCopy) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                            _ = getnameinfo(saPtr,
                                             socklen_t(MemoryLayout<sockaddr_in>.size),
                                             &host, socklen_t(host.count),
                                             nil, 0,
                                             NI_NUMERICHOST)
                        }
                    }
                    let ip = String(cString: host)
                    debugLog("EnhancedBonjourCollector: Extracted IP: \(ip)")

                    // Map NetService type->ServiceType; skip unknown service types
                    let svcType = EnhancedBonjourCollector.mapServiceType(service.type)
                    if svcType != .unknown {
                        let port = service.port > 0 ? Int(service.port) : nil
                        let networkService = NetworkService(name: service.name, type: svcType, port: port)
                        let current = collected[ip]
                        var newServices = current?.services ?? []
                        if !newServices.contains(where: { $0.type == networkService.type && $0.port == networkService.port && $0.name == networkService.name }) {
                            newServices.append(networkService)
                        }
                        let hostName = service.hostName
                        collected[ip] = BonjourHostResult(
                            hostname: current?.hostname ?? hostName,
                            services: newServices,
                            ipAddress: ip,
                            modelHint: nil as String?, // Could be extracted from TXT records
                            deviceTypeHint: nil as String? // Could be inferred from services
                        )
                        debugLog("EnhancedBonjourCollector: Added service \(networkService.name) of type \(svcType) at IP \(ip)")
                    }
                }
            }
        }
    }

    static func mapServiceType(_ netServiceType: String) -> ServiceType {
        let t = netServiceType.lowercased()
        if t.contains("_http._tcp") { return .http }
        if t.contains("_https._tcp") { return .https }
        if t.contains("_ssh._tcp") { return .ssh }
        if t.contains("_smb._tcp") || t.contains("_afpovertcp._tcp") { return .smb }
        if t.contains("_googlecast._tcp") || t.contains("_raop._tcp") { return .chromecast }
        if t.contains("_ipp._tcp") || t.contains("_printer._tcp") { return .http }
        if t.contains("_dns") { return .dns }
        return .unknown
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        debugLog("EnhancedBonjourCollector: Failed to resolve service \(sender.name). Error: \(errorDict)")
    }
}

// MARK: - Delegate Classes

private final class BrowserDelegate: NSObject, NetServiceBrowserDelegate {
    private let handleService: (NetService) -> Void
    private let handleError: ([String: NSNumber]) -> Void
    private let serviceType: String

    init(collector: EnhancedBonjourCollector, serviceType: String) {
        self.serviceType = serviceType
        self.handleService = { [weak collector] service in
            collector?.netServiceBrowser(NetServiceBrowser(), didFind: service, moreComing: false)
        }
        self.handleError = { [weak collector] errorDict in
            collector?.netServiceBrowser(NetServiceBrowser(), didNotSearch: errorDict)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        handleService(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        handleError(errorDict)
    }
}

private final class WildcardBrowserDelegate: NSObject, NetServiceBrowserDelegate {
    private let handleServiceType: (NetService) -> Void
    private let handleError: ([String: NSNumber]) -> Void

    init(discoverer: BonjourDiscoverer) {
        self.handleServiceType = { [weak discoverer] service in
            discoverer?.handleDiscoveredServiceType(service)
        }
        self.handleError = { errorDict in
            debugLog("WildcardBrowserDelegate: Browser failed to search: \(errorDict)")
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        handleServiceType(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        handleError(errorDict)
    }
}

private final class ServiceBrowserDelegate: NSObject, NetServiceBrowserDelegate {
    private let handleService: (NetService, String) -> Void
    private let handleError: ([String: NSNumber], String) -> Void
    private let serviceType: String

    init(discoverer: BonjourDiscoverer, serviceType: String) {
        self.serviceType = serviceType
        self.handleService = { [weak discoverer] service, type in
            discoverer?.handleDiscoveredService(service, serviceType: type)
        }
        self.handleError = { errorDict, type in
            debugLog("ServiceBrowserDelegate: Browser failed for \(type): \(errorDict)")
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        handleService(service, serviceType)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        handleError(errorDict, serviceType)
    }
}

private final class ServiceDelegate: NSObject, NetServiceDelegate {
    private let handleResolution: (NetService) -> Void
    private let handleError: (NetService, [String: NSNumber]) -> Void

    init(collector: EnhancedBonjourCollector) {
        self.handleResolution = { [weak collector] service in
            collector?.netServiceDidResolveAddress(service)
        }
        self.handleError = { service, errorDict in
            debugLog("ServiceDelegate: Failed to resolve \(service.name): \(errorDict)")
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        handleResolution(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        handleError(sender, errorDict)
    }
}

private final class DiscovererServiceDelegate: NSObject, NetServiceDelegate {
    private let handleResolution: (NetService) -> Void
    private let handleError: (NetService, [String: NSNumber]) -> Void

    init(discoverer: BonjourDiscoverer) {
        self.handleResolution = { [weak discoverer] service in
            discoverer?.handleServiceResolved(service)
        }
        self.handleError = { service, errorDict in
            debugLog("ServiceDelegate: Failed to resolve \(service.name): \(errorDict)")
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        handleResolution(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        handleError(sender, errorDict)
    }
}

@MainActor
private final class ServiceTypeCollector: NSObject, @preconcurrency NetServiceBrowserDelegate {
    private let browser = NetServiceBrowser()
    private(set) var types: Set<String> = []

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_services._dns-sd._udp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        // Extract a valid regtype like "_http._tcp." from the service record
        let candidates = [service.name, service.type]
        for cand in candidates {
            if let reg = Self.extractRegtype(from: cand) {
                types.insert(reg)
                break
            }
        }
    }

    private static func extractRegtype(from string: String) -> String? {
        // Normalize by stripping a trailing domain if present (e.g., ".local.")
        var s = string
        let lower = s.lowercased()
        if lower.hasSuffix(".local.") {
            s = String(s.dropLast(".local.".count))
        }
        // Look for a substring like "_name._tcp." or "_name._udp."
        let pattern = #"(_[A-Za-z0-9\-]+\._(tcp|udp)\.)"#
        if let range = s.range(of: pattern, options: .regularExpression) {
            let match = String(s[range])
            // Filter out the meta-service itself
            if match.lowercased() == "_services._dns-sd._udp." { return nil }
            return match.hasSuffix(".") ? match : match + "."
        }
        return nil
    }
}
