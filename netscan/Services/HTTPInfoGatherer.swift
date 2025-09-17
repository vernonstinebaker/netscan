import Foundation
import Network

/// Service for gathering additional information from HTTP services
public actor HTTPInfoGatherer {
    public struct HTTPInfo: Sendable {
        public let serverHeader: String?
        public let poweredByHeader: String?
        public let userAgent: String?
        public let contentType: String?
        public let title: String?
        public let deviceInfo: [String: String]
        public let macAddress: String?
        public let vendor: String?
    }

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 5.0) {
        self.timeout = timeout
    }

    /// Gather information from an HTTP service
    public func gatherInfo(host: String, port: Int = 80, useHTTPS: Bool = false) async -> HTTPInfo? {
        let scheme = useHTTPS ? "https" : "http"
        let urlString = port == (useHTTPS ? 443 : 80) ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"

        guard let url = URL(string: urlString) else {
            await MainActor.run {
                debugLog("[HTTPInfoGatherer] Invalid URL: \(urlString)")
            }
            return nil
        }

        do {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout
            let session = URLSession(configuration: config)

            await MainActor.run {
                debugLog("[HTTPInfoGatherer] Probing \(urlString)")
            }
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    debugLog("[HTTPInfoGatherer] Not an HTTP response")
                }
                return nil
            }

            // Extract headers
            let headers = httpResponse.allHeaderFields as? [String: String] ?? [:]
            let serverHeader = headers["Server"] ?? headers["server"]
            let poweredByHeader = headers["X-Powered-By"] ?? headers["x-powered-by"]
            let contentType = headers["Content-Type"] ?? headers["content-type"]

            // Try to extract title from HTML
            let title = extractTitle(from: data)

            // Look for device-specific information
            var deviceInfo: [String: String] = [:]
            var macAddress: String?
            var vendor: String?

            // Check for common device identification patterns
            if let server = serverHeader {
                deviceInfo["server"] = server

                // Extract device info from server header
                if server.contains("RouterOS") {
                    deviceInfo["device_type"] = "MikroTik Router"
                    vendor = "MikroTik"
                } else if server.contains("nginx") || server.contains("Apache") {
                    deviceInfo["web_server"] = server
                } else if server.contains("lighttpd") {
                    deviceInfo["web_server"] = "lighttpd"
                }
            }

            // Check for MAC address in various places
            macAddress = extractMACAddress(from: headers, data: data)

            // Look for vendor information in response
            if vendor == nil {
                vendor = extractVendor(from: headers, data: data)
            }

            // Additional device detection from content
            if let contentString = String(data: data, encoding: .utf8) {
                // Look for common device identifiers
                if contentString.contains("Synology") {
                    deviceInfo["device_type"] = "NAS"
                    vendor = vendor ?? "Synology"
                } else if contentString.contains("QNAP") {
                    deviceInfo["device_type"] = "NAS"
                    vendor = vendor ?? "QNAP"
                } else if contentString.contains("Ubiquiti") {
                    deviceInfo["device_type"] = "Network Device"
                    vendor = vendor ?? "Ubiquiti"
                }
            }

            let finalMacAddress = macAddress
            let finalVendor = vendor
            await MainActor.run {
                debugLog("[HTTPInfoGatherer] Gathered info for \(host):\(port) - server: \(serverHeader ?? "unknown"), mac: \(finalMacAddress ?? "none"), vendor: \(finalVendor ?? "unknown")")
            }

            return HTTPInfo(
                serverHeader: serverHeader,
                poweredByHeader: poweredByHeader,
                userAgent: nil, // Would need to be set from request if we had it
                contentType: contentType,
                title: title,
                deviceInfo: deviceInfo,
                macAddress: macAddress,
                vendor: vendor
            )

        } catch {
            await MainActor.run {
                debugLog("[HTTPInfoGatherer] Failed to gather HTTP info for \(host):\(port) - \(error)")
            }
            return nil
        }
    }

    private func extractTitle(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // Look for <title> tags
        let titlePattern = #"<title[^>]*>([^<]+)</title>"#
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func extractMACAddress(from headers: [String: String], data: Data) -> String? {
        // Check headers for MAC address
        for (key, value) in headers {
            if key.lowercased().contains("mac") || key.lowercased().contains("hardware") {
                if let mac = extractMACFromString(value) {
                    return mac
                }
            }
        }

        // Check response data for MAC address
        if let content = String(data: data, encoding: .utf8) {
            return extractMACFromString(content)
        }

        return nil
    }

    private func extractMACFromString(_ string: String) -> String? {
        // Common MAC address patterns
        let patterns = [
            #"[0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}"#, // XX:XX:XX:XX:XX:XX
            #"[0-9A-Fa-f]{12}"#, // XXXXXXXXXXXX
            #"[0-9A-Fa-f]{4}[:-][0-9A-Fa-f]{4}[:-][0-9A-Fa-f]{4}"# // XXXX:XXXX:XXXX
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
               let range = Range(match.range, in: string) {
                let mac = String(string[range])
                // Normalize to standard format
                return normalizeMACAddress(mac)
            }
        }

        return nil
    }

    private func normalizeMACAddress(_ mac: String) -> String {
        // Remove separators and convert to uppercase
        let cleaned = mac.replacingOccurrences(of: "[:-]", with: "", options: .regularExpression)
        if cleaned.count == 12 {
            // Insert colons every 2 characters
            var result = ""
            for (index, char) in cleaned.uppercased().enumerated() {
                if index > 0 && index % 2 == 0 {
                    result += ":"
                }
                result += String(char)
            }
            return result
        }
        return mac.uppercased()
    }

    private func extractVendor(from headers: [String: String], data: Data) -> String? {
        // Check headers for vendor information
        for (key, value) in headers {
            if key.lowercased().contains("server") {
                if value.contains("MikroTik") { return "MikroTik" }
                if value.contains("Cisco") { return "Cisco" }
                if value.contains("Juniper") { return "Juniper" }
                if value.contains("Huawei") { return "Huawei" }
                if value.contains("TP-Link") { return "TP-Link" }
                if value.contains("Netgear") { return "Netgear" }
                if value.contains("Linksys") { return "Linksys" }
                if value.contains("ASUS") { return "ASUS" }
                if value.contains("D-Link") { return "D-Link" }
            }
        }

        // Check response data
        if let content = String(data: data, encoding: .utf8) {
            if content.contains("Synology") { return "Synology" }
            if content.contains("QNAP") { return "QNAP" }
            if content.contains("Western Digital") { return "Western Digital" }
            if content.contains("Seagate") { return "Seagate" }
            if content.contains("Buffalo") { return "Buffalo" }
        }

        return nil
    }
}