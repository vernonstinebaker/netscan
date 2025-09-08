import Foundation
import Network

/// Service for SSH fingerprinting and banner grabbing
public actor SSHFingerprintService {
    public struct SSHInfo: Sendable {
        public let banner: String?
        public let version: String?
        public let keyExchangeAlgorithms: [String]
        public let hostKeyAlgorithms: [String]
        public let encryptionAlgorithms: [String]
        public let macAlgorithms: [String]
        public let compressionAlgorithms: [String]
        public let supportsPasswordAuth: Bool?
        public let supportsPublicKeyAuth: Bool?
    }

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 5.0) {
        self.timeout = timeout
    }

    /// Get SSH information from a host
    public func getSSHInfo(for ipAddress: String, port: Int = 22) async -> SSHInfo? {
        debugLog("[SSHFingerprint] Starting SSH fingerprint for \(ipAddress):\(port)")

        guard let serverAddress = try? NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: NWEndpoint.Port(integerLiteral: UInt16(port))) else {
            return nil
        }

        let connection = NWConnection(to: serverAddress, using: .tcp)

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "ssh-sync")
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
                    // SSH server should send identification string immediately
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                        connection.cancel()

                        if let error = error {
                            debugLog("[SSHFingerprint] SSH connection error: \(error)")
                            continuation.resume(returning: nil)
                            return
                        }

                        if let data = data, let banner = String(data: data, encoding: .utf8) {
                            let sshInfo = SSHFingerprintService.parseSSHBanner(banner)
                            debugLog("[SSHFingerprint] SSH banner from \(ipAddress):\(port): \(sshInfo.banner ?? "unknown")")
                            continuation.resume(returning: sshInfo)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }

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

    private static func parseSSHBanner(_ banner: String) -> SSHInfo {
        let lines = banner.split(separator: "\n").map { String($0) }
        var version: String?
        var keyExchangeAlgorithms: [String] = []
        var hostKeyAlgorithms: [String] = []
        var encryptionAlgorithms: [String] = []
        var macAlgorithms: [String] = []
        var compressionAlgorithms: [String] = []

        for line in lines {
            if line.hasPrefix("SSH-") {
                // SSH identification string
                version = line.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.contains("kex_algorithms") {
                keyExchangeAlgorithms = SSHFingerprintService.parseAlgorithmList(line)
            } else if line.contains("host_key_algorithms") {
                hostKeyAlgorithms = SSHFingerprintService.parseAlgorithmList(line)
            } else if line.contains("encryption_algorithms") {
                encryptionAlgorithms = SSHFingerprintService.parseAlgorithmList(line)
            } else if line.contains("mac_algorithms") {
                macAlgorithms = SSHFingerprintService.parseAlgorithmList(line)
            } else if line.contains("compression_algorithms") {
                compressionAlgorithms = SSHFingerprintService.parseAlgorithmList(line)
            }
        }

        return SSHInfo(
            banner: version,
            version: SSHFingerprintService.extractVersion(from: version),
            keyExchangeAlgorithms: keyExchangeAlgorithms,
            hostKeyAlgorithms: hostKeyAlgorithms,
            encryptionAlgorithms: encryptionAlgorithms,
            macAlgorithms: macAlgorithms,
            compressionAlgorithms: compressionAlgorithms,
            supportsPasswordAuth: nil, // Would need authentication attempt
            supportsPublicKeyAuth: nil  // Would need authentication attempt
        )
    }

    private static func parseAlgorithmList(_ line: String) -> [String] {
        // Extract algorithm list from SSH protocol line
        // Format: "name value1,value2,value3"
        guard let valueStart = line.firstIndex(of: " ") else { return [] }
        let valuePart = line[valueStart...].trimmingCharacters(in: .whitespaces)
        return valuePart.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func extractVersion(from banner: String?) -> String? {
        guard let banner = banner else { return nil }

        // Extract version from SSH banner like "SSH-2.0-OpenSSH_8.9p1 Ubuntu-3"
        let components = banner.split(separator: "-")
        if components.count >= 2 {
            return String(components[1])
        }

        return nil
    }

    /// Enhanced SSH analysis for device identification
    public func analyzeSSHForDeviceInfo(_ sshInfo: SSHInfo) -> [String: String] {
        var deviceInfo: [String: String] = [:]

        if let banner = sshInfo.banner {
            deviceInfo["ssh_banner"] = banner

            // Identify SSH server software
            if banner.contains("OpenSSH") {
                deviceInfo["ssh_server"] = "OpenSSH"
                if banner.contains("Ubuntu") {
                    deviceInfo["os_family"] = "Linux"
                    deviceInfo["os_distribution"] = "Ubuntu"
                } else if banner.contains("Debian") {
                    deviceInfo["os_family"] = "Linux"
                    deviceInfo["os_distribution"] = "Debian"
                } else if banner.contains("CentOS") {
                    deviceInfo["os_family"] = "Linux"
                    deviceInfo["os_distribution"] = "CentOS"
                } else if banner.contains("FreeBSD") {
                    deviceInfo["os_family"] = "BSD"
                    deviceInfo["os_distribution"] = "FreeBSD"
                }
            } else if banner.contains("PuTTY") {
                deviceInfo["ssh_server"] = "PuTTY"
                deviceInfo["device_type"] = "Windows SSH Client"
            } else if banner.contains("libssh") {
                deviceInfo["ssh_server"] = "libssh"
            } else if banner.contains("dropbear") {
                deviceInfo["ssh_server"] = "Dropbear"
                deviceInfo["device_type"] = "Embedded Linux Device"
            }
        }

        // Analyze key algorithms for security assessment
        if !sshInfo.hostKeyAlgorithms.isEmpty {
            deviceInfo["ssh_key_algorithms"] = sshInfo.hostKeyAlgorithms.joined(separator: ", ")

            // Check for modern vs legacy algorithms
            if sshInfo.hostKeyAlgorithms.contains(where: { $0.contains("ed25519") }) {
                deviceInfo["ssh_security"] = "Modern (Ed25519)"
            } else if sshInfo.hostKeyAlgorithms.contains(where: { $0.contains("ecdsa") }) {
                deviceInfo["ssh_security"] = "Modern (ECDSA)"
            } else if sshInfo.hostKeyAlgorithms.contains(where: { $0.contains("rsa") }) {
                deviceInfo["ssh_security"] = "Legacy (RSA)"
            }
        }

        return deviceInfo
    }

    /// Scan subnet for SSH servers
    public func scanSubnet(info: NetworkInfo, concurrency: Int = 8) async -> [String: SSHInfo] {
        guard let parsed = await NetworkInterface.parseNetworkInfo(info) else { return [:] }
        let (_, _, _, hosts) = parsed

        var results: [String: SSHInfo] = [:]

        await withTaskGroup(of: (String, SSHInfo?).self) { group in
            for hostIP in hosts {
                let ipString = await MainActor.run { IPv4.format(hostIP) }

                group.addTask {
                    if let info = await self.getSSHInfo(for: ipString) {
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

        debugLog("[SSHFingerprint] Found \(results.count) SSH servers")
        return results
    }
}