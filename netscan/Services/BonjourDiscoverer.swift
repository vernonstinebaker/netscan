// @preconcurrency import Foundation
import Foundation
import Darwin

// Simple Bonjour test function
func testBonjourOnIOS() {
    #if os(iOS)
    print("BonjourTest: Testing Bonjour on iOS")
    DispatchQueue.main.async {
        let browser = NetServiceBrowser()
        let delegate = BonjourTestDelegate()
        browser.delegate = delegate
        print("BonjourTest: Starting browser for _http._tcp")
        browser.searchForServices(ofType: "_http._tcp", inDomain: "local.")

        // Stop after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            print("BonjourTest: Stopping browser")
            browser.stop()
        }
    }
    #endif
}

class BonjourTestDelegate: NSObject, NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("BonjourTest: Found service: \(service.name) type: \(service.type)")
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("BonjourTest: Browser stopped")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("BonjourTest: Browser error: \(errorDict)")
    }
}

public struct BonjourHostResult: Sendable {
    public let hostname: String?
    public let services: [NetworkService]
}

public actor BonjourDiscoverer {
    public init() {}

    // Discover the available service types using DNS-SD's canonical service enumeration.
    // Falls back to a default seed list if nothing is found within the timeout.
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
            "_googlecast._tcp.", "_hap._tcp.", "_ftp._tcp.", "_workstation._tcp.", "_rfb._tcp."
        ]
    }

    public func discover(timeout: TimeInterval = 4.0, serviceTypes: [String]? = nil) async -> [String: BonjourHostResult] {
        let types: [String]
        if let provided = serviceTypes {
            types = provided
        } else {
            // Use multiple common service types for better discovery
            types = ["_http._tcp.", "_https._tcp.", "_ssh._tcp.", "_smb._tcp.", "_afpovertcp._tcp."]
        }

        debugLog("BonjourDiscoverer: Starting discovery with \(types.count) service types: \(types)")

        return await withCheckedContinuation { continuation in
            // Bonjour operations must be done on main thread
            DispatchQueue.main.async {
                let collector = BonjourCollector(serviceTypes: types)
                debugLog("BonjourDiscoverer: Created collector on main thread")

                collector.start()
                debugLog("BonjourDiscoverer: Started collector")

                // Wait for the timeout period
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    debugLog("BonjourDiscoverer: Timeout reached, stopping collector")
                    collector.stop()
                    let results = collector.collected
                    debugLog("BonjourDiscoverer: Found \(results.count) results: \(results.keys)")
                    continuation.resume(returning: results)
                }
            }
        }
    }
}

private final class BonjourCollector: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let serviceTypes: [String]
    private var browsers: [NetServiceBrowser] = []
    private var services: Set<NetService> = []
    // Map IP -> hostname + [NetworkService]
    private(set) var collected: [String: BonjourHostResult] = [:]

    init(serviceTypes: [String]) {
        self.serviceTypes = serviceTypes
    }

    func start() {
        debugLog("BonjourCollector: Starting \(serviceTypes.count) service browsers")
        for type in serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            debugLog("BonjourCollector: Created browser for type: \(type)")
            debugLog("BonjourCollector: Starting browser search for type: \(type) in domain: local.")
            browser.searchForServices(ofType: type, inDomain: "local.")
            debugLog("BonjourCollector: Browser searchForServices called for type: \(type)")
        }
        debugLog("BonjourCollector: All browsers started (\(browsers.count) total)")
    }

    func stop() {
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        services.forEach { $0.stop() }
        services.removeAll()
    }

    // NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        debugLog("BonjourCollector: Found service: \(service.name) (\(service.type)) at \(service.hostName ?? "unknown")")
        debugLog("BonjourCollector: Service domain: \(service.domain), port: \(service.port)")
        debugLog("BonjourCollector: Service addresses count: \(service.addresses?.count ?? 0)")

        // If the service already has addresses, we can process it immediately
        if let addresses = service.addresses, !addresses.isEmpty {
            debugLog("BonjourCollector: Service \(service.name) already has addresses, processing directly")
            processServiceAddresses(service)
        } else {
            // Otherwise, resolve it
            service.delegate = self
            services.insert(service)
            debugLog("BonjourCollector: Resolving service \(service.name) with 3.0s timeout")
            service.resolve(withTimeout: 3.0)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        debugLog("BonjourCollector: Browser failed to search: \(errorDict)")
        // Log specific error codes
        for (key, value) in errorDict {
            debugLog("BonjourCollector: Error \(key): \(value)")
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        debugLog("BonjourCollector: Browser stopped search")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        debugLog("BonjourCollector: Removed service: \(service.name)")
        services.remove(service)
    }

    // NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        debugLog("BonjourCollector: Resolved service \(sender.name) - extracting IP addresses")
        processServiceAddresses(sender)
    }

    private func processServiceAddresses(_ service: NetService) {
        guard let addrs = service.addresses else {
            debugLog("BonjourCollector: No addresses for service \(service.name)")
            return
        }
        debugLog("BonjourCollector: Address data count: \(addrs.count) for service \(service.name)")

        for data in addrs {
            debugLog("BonjourCollector: Address raw bytes length: \(data.count) for service \(service.name)")
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
                    debugLog("BonjourCollector: Extracted IP: \(ip)")
                    // Map NetService type->ServiceType; skip unknown service types
                    let svcType = BonjourCollector.mapServiceType(service.type)
                    if svcType != .unknown {
                        let port = service.port > 0 ? Int(service.port) : nil
                        let networkService = NetworkService(name: service.name, type: svcType, port: port)
                        let current = collected[ip]
                        var newServices = current?.services ?? []
                        if !newServices.contains(where: { $0.type == networkService.type && $0.port == networkService.port && $0.name == networkService.name }) {
                            newServices.append(networkService)
                        }
                        let hostName = service.hostName
                        collected[ip] = BonjourHostResult(hostname: current?.hostname ?? hostName, services: newServices)
                        debugLog("BonjourCollector: Added service \(networkService.name) of type \(svcType) at IP \(ip)")
                    }
                }
            }
        }
    }

    static func mapServiceType(_ netServiceType: String) -> ServiceType {
        return ServiceMapper.type(forBonjour: netServiceType)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        debugLog("BonjourCollector: Failed to resolve service \(sender.name). Error: \(errorDict)")
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
