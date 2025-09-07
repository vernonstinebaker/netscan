import Foundation

public actor NetworkScanner {
    public struct Progress: Sendable { public let scanned: Int; public let total: Int }

    public typealias ProbeFunc = @Sendable (_ ip: String, _ timeout: TimeInterval) async -> NetworkFrameworkProber.Result
    public typealias PortScanFunc = @Sendable (_ host: String) async -> [Port]

    private let probe: ProbeFunc
    private let portScan: PortScanFunc
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 0.5, probe: @escaping ProbeFunc = { ip, timeout in
        if let (alive, rtt) = await SimplePing.ping(host: ip, timeout: timeout) {
            return alive ? .alive(rtt) : .dead
        } else {
            return .dead
        }
    }) {
        self.timeout = timeout
        self.probe = probe
        self.portScan = { host in await PortScanner(host: host).scanPorts(portRange: 1...1024) }
    }

    public init(timeout: TimeInterval = 0.75, probe: @escaping ProbeFunc, portScan: @escaping PortScanFunc) {
        self.timeout = timeout
        self.probe = probe
        self.portScan = portScan
    }

    public func scanSubnet(info: NetworkInfo, concurrency: Int = 64, onProgress: ((Progress) -> Void)? = nil) async -> [Device] {
        guard let parsed = await NetworkInterface.parseNetworkInfo(info) else {
            print("[NetworkScanner] Failed to parse IP or netmask: ip=\(info.ip) mask=\(info.netmask)")
            return []
        }
        let (_, mask, network, hosts) = parsed
        let total = hosts.count
        let header: String = await MainActor.run {
            "[NetworkScanner] Starting scan: network=\(IPv4.format(network)) mask=/\(IPv4.netmaskPrefix(mask)) totalHosts=\(total) concurrency=\(concurrency)"
        }
        print(header)
        var scanned = 0
        var results: [Device] = []
        results.reserveCapacity(total)
        let doProbe = self.probe
        let timeout = self.timeout
        var index = 0
        while index < total {
            if Task.isCancelled { break }
            let upper = min(index + max(1, concurrency), total)
            await withTaskGroup(of: Device?.self) { group in
                for i in index..<upper {
                    if Task.isCancelled { break }
                    let ipStr = await MainActor.run { IPv4.format(hosts[i]) }
                    group.addTask { [timeout] in
                        if Task.isCancelled { return nil }
                        let res = await doProbe(ipStr, timeout)
                        switch res {
                        case .alive(let ms):
                            let openPorts = await self.portScan(ipStr)
                            return await MainActor.run { Device(ip: ipStr, rttMillis: ms, openPorts: openPorts) }
                        case .dead:
                            return nil
                        }
                    }
                }
                for await maybe in group {
                    scanned += 1
                    if let d = maybe { results.append(d) }
                    onProgress?(Progress(scanned: scanned, total: total))
                }
            }
            index = upper
        }
        let snapshot = results
        let sorted: [Device] = await MainActor.run {
            snapshot.sorted { (a: Device, b: Device) in
                guard let aa = IPv4.parse(a.ipAddress)?.raw, let bb = IPv4.parse(b.ipAddress)?.raw else { return a.ipAddress < b.ipAddress }
                return aa < bb
            }
        }
        return sorted
    }
}
