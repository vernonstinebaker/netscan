// @preconcurrency import Foundation
import Foundation
import Darwin

public actor BonjourDiscoverer {
    public init() {}

    public func discover(timeout: TimeInterval = 2.0, serviceTypes: [String]? = nil) async -> [String: [NetworkService]] {
        let types = serviceTypes ?? [
            "_http._tcp.", "_https._tcp.", "_ssh._tcp.", "_smb._tcp.", "_afpovertcp._tcp.",
            "_device-info._tcp.", "_airplay._tcp.", "_raop._tcp.", "_ipp._tcp.", "_printer._tcp.",
            "_googlecast._tcp.", "_hap._tcp.", "_ftp._tcp.", "_workstation._tcp.", "_rfb._tcp."
        ]

        debugLog("BonjourDiscoverer: Starting discovery with \(types.count) service types")
        
        // Create and control the collector on the main actor (NetService expects main run loop)
        let collector = await MainActor.run { BonjourCollector(serviceTypes: types) }
        await MainActor.run { collector.start() }

        debugLog("BonjourDiscoverer: Waiting for \(timeout) seconds...")
        // Wait to collect responses
        try? await Task.sleep(nanoseconds: UInt64(max(0, timeout)) * 1_000_000_000)

        // Stop and read results on MainActor
        let results: [String: [NetworkService]] = await MainActor.run {
            collector.stop()
            debugLog("BonjourDiscoverer: Found \(collector.collected.count) IPs: \(collector.collected.keys)")
            return collector.collected
        }
        return results
    }
}

@MainActor
private final class BonjourCollector: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private let serviceTypes: [String]
    private var browsers: [NetServiceBrowser] = []
    private var services: Set<NetService> = []
    // Map IP -> [NetworkService]
    private(set) var collected: [String: [NetworkService]] = [:]

    init(serviceTypes: [String]) {
        self.serviceTypes = serviceTypes
    }

    func start() {
        for type in serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            debugLog("BonjourCollector: Starting browser for type: \(type)")
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
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
        service.delegate = self
        services.insert(service)
        debugLog("BonjourCollector: Resolving service \(service.name) with 2.5s timeout")
        service.resolve(withTimeout: 2.5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        debugLog("BonjourCollector: Removed service: \(service.name)")
        services.remove(service)
    }

    // NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        debugLog("BonjourCollector: Resolved service \(sender.name) - extracting IP addresses")
        guard let addrs = sender.addresses else { 
            print("BonjourCollector: No addresses for service \(sender.name)")
            return 
        }
    debugLog("BonjourCollector: Address data count: \(addrs.count) for service \(sender.name)")
        
        for data in addrs {
            debugLog("BonjourCollector: Address raw bytes length: \(data.count) for service \(sender.name)")
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
                    let svcType = BonjourCollector.mapServiceType(sender.type)
                    if svcType != .unknown {
                        let networkService = NetworkService(name: sender.name, type: svcType)
                        var list = collected[ip] ?? []
                        // avoid duplicates by service type+name
                        if !list.contains(where: { $0.name == networkService.name && $0.type == networkService.type }) {
                            list.append(networkService)
                        }
                        collected[ip] = list
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
