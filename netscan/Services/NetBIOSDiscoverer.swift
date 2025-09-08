import Foundation
import Network

/// Service for discovering devices via NetBIOS name resolution
public actor NetBIOSDiscoverer {
    public struct NetBIOSInfo: Sendable {
        public let hostname: String?
        public let workgroup: String?
        public let macAddress: String?
        public let services: [String]
    }

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 2.0) {
        self.timeout = timeout
    }

    /// Discover NetBIOS information for a host
    public func discoverInfo(for ipAddress: String) async -> NetBIOSInfo? {
        debugLog("[NetBIOSDiscoverer] Starting NetBIOS discovery for \(ipAddress)")

        // Try NetBIOS name query (port 137)
        if let info = await queryNetBIOSName(ipAddress) {
            debugLog("[NetBIOSDiscoverer] Found NetBIOS info for \(ipAddress): \(info.hostname ?? "unknown")")
            return info
        }

        // Try NetBIOS datagram service (port 138) for workgroup info
        if let workgroupInfo = await queryNetBIOSDatagram(ipAddress) {
            debugLog("[NetBIOSDiscoverer] Found workgroup info for \(ipAddress)")
            return workgroupInfo
        }

        debugLog("[NetBIOSDiscoverer] No NetBIOS info found for \(ipAddress)")
        return nil
    }

    private func queryNetBIOSName(_ ipAddress: String) async -> NetBIOSInfo? {
        // NetBIOS Name Service query (simplified)
        // In a full implementation, this would send proper NetBIOS NS packets
        // For now, we'll try a basic UDP connection to see if the service responds

        guard let serverAddress = try? NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: NWEndpoint.Port(137)) else {
            return nil
        }

        let connection = NWConnection(to: serverAddress, using: .udp)
        let result = await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Service is responding, create basic info
                    connection.cancel()
                    continuation.resume(returning: NetBIOSInfo(
                        hostname: nil, // Would need proper NetBIOS packet parsing
                        workgroup: nil,
                        macAddress: nil,
                        services: ["NetBIOS Name Service"]
                    ))
                case .failed:
                    connection.cancel()
                    continuation.resume(returning: NetBIOSInfo(hostname: nil, workgroup: nil, macAddress: nil, services: []))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }

        // Timeout after our specified timeout
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        connection.cancel()

        return result
    }

    private func queryNetBIOSDatagram(_ ipAddress: String) async -> NetBIOSInfo? {
        // Similar to name query but for datagram service
        guard let serverAddress = try? NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: NWEndpoint.Port(138)) else {
            return nil
        }

        let connection = NWConnection(to: serverAddress, using: .udp)
        let result = await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    continuation.resume(returning: NetBIOSInfo(
                        hostname: nil,
                        workgroup: nil,
                        macAddress: nil,
                        services: ["NetBIOS Datagram Service"]
                    ))
                case .failed:
                    connection.cancel()
                    continuation.resume(returning: NetBIOSInfo(hostname: nil, workgroup: nil, macAddress: nil, services: []))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }

        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        connection.cancel()

        return result
    }

    /// Scan subnet for NetBIOS-enabled devices
    public func scanSubnet(info: NetworkInfo, concurrency: Int = 16) async -> [String: NetBIOSInfo] {
        guard let parsed = await NetworkInterface.parseNetworkInfo(info) else { return [:] }
        let (_, _, _, hosts) = parsed

        var results: [String: NetBIOSInfo] = [:]

        await withTaskGroup(of: (String, NetBIOSInfo?).self) { group in
            for hostIP in hosts {
                let ipString = await MainActor.run { IPv4.format(hostIP) }

                group.addTask {
                    if let info = await self.discoverInfo(for: ipString) {
                        return (ipString, info)
                    }
                    return (ipString, nil)
                }
            }

            for await (ip, info) in group {
                if let info = info {
                    results[ip] = info
                }
            }
        }

        debugLog("[NetBIOSDiscoverer] Found \(results.count) NetBIOS devices")
        return results
    }
}