import Foundation
import CoreFoundation

/// Service for performing DNS reverse lookups to get hostnames from IP addresses
public actor DNSReverseLookupService {
    public struct DNSInfo: Sendable {
        public let hostname: String?
        public let aliases: [String]
        public let resolved: Bool
    }

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 2.0) {
        self.timeout = timeout
    }

    /// Perform reverse DNS lookup for an IP address
    public func reverseLookup(_ ipAddress: String) async -> DNSInfo? {
        await MainActor.run {
            debugLog("[DNSReverseLookup] Starting reverse lookup for \(ipAddress)")
        }

        // For now, disable actual DNS lookups to prevent SIGCHLD issues
        // Return unresolved to avoid crashes
        await MainActor.run {
            debugLog("[DNSReverseLookup] DNS lookup disabled to prevent SIGCHLD signal issues")
        }
        return DNSInfo(hostname: nil, aliases: [], resolved: false)
    }



    /// Batch reverse lookup for multiple IP addresses
    public func batchReverseLookup(_ ipAddresses: [String], concurrency: Int = 8) async -> [String: DNSInfo] {
        var results: [String: DNSInfo] = [:]

        await withTaskGroup(of: (String, DNSInfo?).self) { group in
            for ipAddress in ipAddresses {
                group.addTask {
                    if let info = await self.reverseLookup(ipAddress) {
                        return (ipAddress, info)
                    }
                    return (ipAddress, nil)
                }
            }

            for await (ip, info) in group {
                if let info = info {
                    results[ip] = info
                }
            }
        }

        let resultCount = results.count
        await MainActor.run {
            debugLog("[DNSReverseLookup] Completed batch lookup for \(ipAddresses.count) IPs, found \(resultCount) hostnames")
        }
        return results
    }

    /// Enhanced hostname resolution that tries multiple methods
    public func resolveHostname(for ipAddress: String) async -> String? {
        // Try reverse DNS lookup first
        if let dnsInfo = await reverseLookup(ipAddress), let hostname = dnsInfo.hostname {
            return hostname
        }

        // Fallback: try common hostname patterns
        if let lastOctet = ipAddress.split(separator: ".").last {
            let commonPatterns = [
                "host-\(lastOctet)",
                "device-\(lastOctet)",
                "computer-\(lastOctet)",
                "\(lastOctet)"
            ]

            // Try forward DNS lookup for these patterns
            for pattern in commonPatterns {
                if await forwardLookupSucceeds(pattern) {
                    return pattern
                }
            }
        }

        return nil
    }

    private func forwardLookupSucceeds(_ hostname: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let host = CFHostCreateWithName(kCFAllocatorDefault, hostname as CFString).takeRetainedValue()

                var error = CFStreamError()
                let success = CFHostStartInfoResolution(host, .addresses, &error)

                continuation.resume(returning: success)
            }
        }
    }
}