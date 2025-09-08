import Foundation
import Network

/// Service for discovering NTP (Network Time Protocol) servers and clients
public actor NTPDiscoverer {
    public struct NTPInfo: Sendable {
        public let isNTPServer: Bool
        public let stratum: Int?
        public let referenceId: String?
        public let precision: Double?
        public let rootDelay: Double?
        public let rootDispersion: Double?
        public let serverVersion: String?
    }

    private let timeout: TimeInterval
    private let ntpPacket: Data

    public init(timeout: TimeInterval = 3.0) {
        self.timeout = timeout
        self.ntpPacket = Self.createNTPQueryPacket()
    }

    private static func createNTPQueryPacket() -> Data {
        // Create a basic NTP client query packet
        var packet = Data(count: 48)

        // NTP version 4, client mode
        packet[0] = 0x23  // LI=0, VN=4, Mode=3 (client)

        return packet
    }

    /// Check if a host is running NTP and gather information
    public func discoverNTPInfo(for ipAddress: String) async -> NTPInfo? {
        debugLog("[NTPDiscoverer] Checking NTP service on \(ipAddress)")

        // Try NTP query on port 123
        guard let serverAddress = try? NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: NWEndpoint.Port(123)) else {
            return nil
        }

        let connection = NWConnection(to: serverAddress, using: .udp)
        let ntpPacket = Self.createNTPQueryPacket()

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "ntp-sync")
            var didResume = false

            connection.stateUpdateHandler = { state in
                queue.sync {
                    if didResume {
                        return
                    }
                    didResume = true
                }

                switch state {
                case .ready:
                    // Send NTP query packet
                    connection.send(content: ntpPacket, completion: .contentProcessed { error in
                        if let error = error {
                            debugLog("[NTPDiscoverer] Failed to send NTP query: \(error)")
                            connection.cancel()
                            continuation.resume(returning: nil)
                            return
                        }

                        // Wait for response
                        connection.receive(minimumIncompleteLength: 48, maximumLength: 48) { data, _, isComplete, error in
                            connection.cancel()

                            if let error = error {
                                debugLog("[NTPDiscoverer] NTP receive error: \(error)")
                                continuation.resume(returning: nil)
                                return
                            }

                            if let data = data, data.count >= 48 {
                                let info = NTPDiscoverer.parseNTPResponse(data)
                                debugLog("[NTPDiscoverer] NTP response from \(ipAddress): stratum \(info.stratum ?? -1)")
                                continuation.resume(returning: info)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    })

                case .failed:
                    connection.cancel()
                    continuation.resume(returning: nil)

                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                queue.sync {
                    if !didResume {
                        didResume = true
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }



    private static func parseNTPResponse(_ data: Data) -> NTPInfo {
        guard data.count >= 48 else {
            return NTPInfo(isNTPServer: false, stratum: nil, referenceId: nil, precision: nil, rootDelay: nil, rootDispersion: nil, serverVersion: nil)
        }

        let bytes = [UInt8](data)

        // Parse NTP response
        let stratum = Int(bytes[1])
        let precision = Int(Int8(bitPattern: bytes[2]))

        // Reference ID (4 bytes, big-endian)
        let refIdBytes = bytes[12...15]
        let referenceId = String(format: "%c%c%c%c",
                                refIdBytes[0], refIdBytes[1], refIdBytes[2], refIdBytes[3])

        // Root delay (4 bytes, NTP short format)
        let rootDelay = NTPDiscoverer.ntpShortToDouble(bytes[4...7])

        // Root dispersion (4 bytes, NTP short format)
        let rootDispersion = NTPDiscoverer.ntpShortToDouble(bytes[8...11])

        // Extract version from first byte
        let version = (bytes[0] >> 3) & 0x07
        let serverVersion = "NTPv\(version)"

        return NTPInfo(
            isNTPServer: stratum > 0 && stratum < 16, // Valid stratum levels
            stratum: stratum,
            referenceId: referenceId,
            precision: Double(precision),
            rootDelay: rootDelay,
            rootDispersion: rootDispersion,
            serverVersion: serverVersion
        )
    }

    private static func ntpShortToDouble(_ bytes: ArraySlice<UInt8>) -> Double {
        guard bytes.count == 4 else { return 0.0 }

        let integerPart = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let fractionalPart = UInt16(bytes[2]) << 8 | UInt16(bytes[3])

        return Double(integerPart) + Double(fractionalPart) / 65536.0
    }

    /// Scan subnet for NTP servers
    public func scanSubnet(info: NetworkInfo, concurrency: Int = 8) async -> [String: NTPInfo] {
        guard let parsed = await NetworkInterface.parseNetworkInfo(info) else { return [:] }
        let (_, _, _, hosts) = parsed

        var results: [String: NTPInfo] = [:]

        await withTaskGroup(of: (String, NTPInfo?).self) { group in
            for hostIP in hosts {
                let ipString = await MainActor.run { IPv4.format(hostIP) }

                group.addTask {
                    if let info = await self.discoverNTPInfo(for: ipString) {
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

        let ntpServers = results.filter { $0.value.isNTPServer }.count
        debugLog("[NTPDiscoverer] Found \(ntpServers) NTP servers out of \(results.count) responding hosts")
        return results
    }
}