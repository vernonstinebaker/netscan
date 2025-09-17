import Foundation
import Network

/// Service for discovering MAC addresses through multiple methods
public actor MACAddressDiscoverer {
    private let httpInfoGatherer: HTTPInfoGatherer
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 3.0) {
        self.timeout = timeout
        self.httpInfoGatherer = HTTPInfoGatherer(timeout: timeout)
    }

    /// Discover MAC address for a host using multiple methods
    public func discoverMACAddress(for ipAddress: String) async -> String? {
        await MainActor.run {
            debugLog("[MACAddressDiscoverer] Starting MAC discovery for \(ipAddress)")
        }

        // Method 1: ARP table lookup (most reliable)
        if let mac = await getMACFromARP(ipAddress) {
            await MainActor.run {
                debugLog("[MACAddressDiscoverer] Found MAC via ARP: \(mac)")
            }
            return mac
        }

        // Method 2: HTTP header inspection
        if let mac = await getMACFromHTTP(ipAddress) {
            await MainActor.run {
                debugLog("[MACAddressDiscoverer] Found MAC via HTTP: \(mac)")
            }
            return mac
        }

        // Method 3: Bonjour TXT records (if available)
        if let mac = await getMACFromBonjour(ipAddress) {
            await MainActor.run {
                debugLog("[MACAddressDiscoverer] Found MAC via Bonjour: \(mac)")
            }
            return mac
        }

        // Method 4: SNMP queries (for network devices)
        if let mac = await getMACFromSNMP(ipAddress) {
            await MainActor.run {
                debugLog("[MACAddressDiscoverer] Found MAC via SNMP: \(mac)")
            }
            return mac
        }

        // Method 5: System ARP cache
        if let mac = await getMACFromSystemCache(ipAddress) {
            await MainActor.run {
                debugLog("[MACAddressDiscoverer] Found MAC via system cache: \(mac)")
            }
            return mac
        }

        await MainActor.run {
            debugLog("[MACAddressDiscoverer] No MAC address found for \(ipAddress)")
        }
        return nil
    }

    private func getMACFromARP(_ ipAddress: String) async -> String? {
        // ARP table lookup - this is the most reliable method
        let arpTable = await ARPTableParser().getARPTable()
        return arpTable.first { $0.ipAddress == ipAddress }?.macAddress
    }

    private func getMACFromHTTP(_ ipAddress: String) async -> String? {
        // Try common HTTP ports
        let ports = [80, 443, 8080, 8443]

        for port in ports {
            // Try HTTP first
            if let info = await httpInfoGatherer.gatherInfo(host: ipAddress, port: port, useHTTPS: false),
               let mac = info.macAddress {
                return mac
            }

            // Try HTTPS if HTTP failed
            if port == 80 || port == 8080 {
                if let info = await httpInfoGatherer.gatherInfo(host: ipAddress, port: port == 80 ? 443 : 8443, useHTTPS: true),
                   let mac = info.macAddress {
                    return mac
                }
            }
        }

        return nil
    }

    private func getMACFromBonjour(_ ipAddress: String) async -> String? {
        // Bonjour TXT records sometimes contain MAC addresses
        // This would require extending the BonjourDiscoverer to parse TXT records
        // For now, return nil as this would need more implementation
        return nil
    }

    private func getMACFromSNMP(_ ipAddress: String) async -> String? {
        // SNMP queries for network devices
        // Common OIDs for MAC addresses:
        // .1.3.6.1.2.1.4.22.1.2 (ARP table)
        // .1.3.6.1.2.1.17.4.3.1.1 (bridge forwarding table)

        // This would require SNMP library integration
        // For now, return nil as this would need more implementation
        return nil
    }

    private func getMACFromSystemCache(_ ipAddress: String) async -> String? {
        // Try to read from system ARP cache using command line
        #if os(macOS)
        return await getMACFromSystemCommand(ipAddress)
        #else
        // On iOS, we can't execute system commands
        return nil
        #endif
    }

    #if os(macOS)
    private func getMACFromSystemCommand(_ ipAddress: String) async -> String? {
        // First, ping the IP to populate the ARP table
        let pingProcess = Process()
        pingProcess.executableURL = URL(fileURLWithPath: "/sbin/ping")
        pingProcess.arguments = ["-c", "1", "-t", "1", ipAddress]
        try? pingProcess.run()
        pingProcess.waitUntilExit()

        // Small delay to allow ARP table to update
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ipAddress]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse arp output: "192.168.1.1 (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0"
                let pattern = #"at ([0-9a-f:]+)"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                    let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                    let range = Range(match.range(at: 1), in: output) {
                    return String(output[range]).uppercased()
                }
            }
        } catch {
            await MainActor.run {
                debugLog("[MACAddressDiscoverer] Failed to run arp command: \(error)")
            }
        }

        return nil
    }
    #endif

    /// Enhanced device information gathering combining HTTP info and MAC discovery
    public func gatherDeviceInfo(for ipAddress: String) async -> (macAddress: String?, vendor: String?, deviceInfo: [String: String]) {
        var macAddress: String?
        var vendor: String?
        var deviceInfo: [String: String] = [:]

        // Try to get MAC address
        macAddress = await discoverMACAddress(for: ipAddress)

        // Try to get vendor from MAC address
        if let mac = macAddress {
            vendor = await OUILookupService.shared.findVendor(for: mac)
        }

        // Try to gather HTTP information
        let ports = [80, 443, 8080, 8443]
        for port in ports {
            if let info = await httpInfoGatherer.gatherInfo(host: ipAddress, port: port, useHTTPS: port == 443 || port == 8443) {
                deviceInfo = info.deviceInfo

                // Override vendor if we found better info from HTTP
                if let httpVendor = info.vendor {
                    vendor = httpVendor
                }

                // Add server info
                if let server = info.serverHeader {
                    deviceInfo["web_server"] = server
                }

                break // Found HTTP info, no need to check more ports
            }
        }

        return (macAddress, vendor, deviceInfo)
    }
}