import Foundation
import Network
import os

/// Cross-platform ICMP ping implementation using Network framework
public actor NetworkPingScanner {
    public struct Progress: Sendable {
        public let scanned: Int
        public let total: Int
    }

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 1.0) {
        self.timeout = timeout
    }

    public func ping(host: String) async -> (Bool, Double)? {
        await withCheckedContinuation { continuation in
            let startTime = DispatchTime.now().uptimeNanoseconds
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: .any, // Use .any for ICMP-like checks
                using: .tcp
            )

            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            connection.stateUpdateHandler = { state in
                let shouldResume = hasResumed.withLock { flag in
                    if !flag {
                        flag = true
                        return true
                    }
                    return false
                }
                guard shouldResume else { return }

                switch state {
                case .ready:
                    connection.cancel()
                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000.0
                    continuation.resume(returning: (true, elapsedMs))

                case .failed(let error):
                    connection.cancel()
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000.0
                        continuation.resume(returning: (true, elapsedMs))
                    } else {
                        continuation.resume(returning: nil)
                    }

                case .cancelled:
                    continuation.resume(returning: nil)

                default:
                    break
                }
            }

            connection.start(queue: .global())

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                let shouldResume = hasResumed.withLock { flag in
                    if !flag {
                        flag = true
                        return true
                    }
                    return false
                }
                if shouldResume {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    public func scanSubnet(
        info: NetworkInfo,
        concurrency: Int = 32,
        skipIPs: Set<String> = [],
        onProgress: @escaping (Progress) -> Void,
        onDeviceFound: @escaping (Device) -> Void
    ) async -> [Device] {
        // Compute IP/mask/network/hosts on the main actor
        let parsed = await MainActor.run { (IPv4.parse(info.ip), IPv4.parse(info.netmask)) }
        guard let ip = parsed.0, let mask = parsed.1 else { return [] }
        let network = await MainActor.run { IPv4.network(ip: ip, mask: mask) }
        let hosts = await MainActor.run { IPv4.hosts(inNetwork: network, mask: mask) }
        let totalHosts = hosts.count

        var devices: [Device] = []
        var scanned = 0

        await withTaskGroup(of: (String, (Bool, Double)?).self) { group in
            for hostIP in hosts {
                let ipString = await MainActor.run { IPv4.format(hostIP) }

                if ipString == "127.0.0.1" || ipString.hasPrefix("127.") || skipIPs.contains(ipString) {
                    continue
                }

                group.addTask {
                    let result = await self.ping(host: ipString)
                    return (ipString, result)
                }
            }

            for await (ipString, result) in group {
                scanned += 1

                if scanned % 25 == 0 || scanned == totalHosts {
                    onProgress(Progress(scanned: scanned, total: totalHosts))
                }

                if let (isAlive, rtt) = result, isAlive {
                    let device = await MainActor.run { Device(id: ipString, name: ipString, ipAddress: ipString, rttMillis: rtt > 0 ? rtt : nil) }
                    devices.append(device)
                    onDeviceFound(device)
                }
            }
        }

        onProgress(Progress(scanned: totalHosts, total: totalHosts))
        return devices
    }
}
