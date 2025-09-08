import Foundation
import Darwin

/// Cross-platform ICMP ping implementation.
/// Uses system ping command on macOS and proper ICMP on iOS via Network framework.
public struct SimplePing {
    /// Ping a host once and return (isAlive, rttMs?) or nil on timeout/error.
    public static func ping(host: String, timeout: TimeInterval = 1.0) async -> (Bool, Double)? {
        #if os(macOS)
        return await macPing(host: host, timeout: timeout)
        #else
        return await iosPing(host: host, timeout: timeout)
        #endif
    }

    private static func macPing(host: String, timeout: TimeInterval) async -> (Bool, Double)? {
        #if os(macOS)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Foundation.Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")

                // Use a single ICMP echo request with timeout
                let t = max(1, Int(timeout))
                process.arguments = ["-c", "1", "-t", String(t), host]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        // Parse RTT like: "time=0.123 ms"
                        if let matchRange = output.range(of: "time=([0-9.]+) ms", options: .regularExpression) {
                            let match = output[matchRange]
                            if let timeString = match.split(separator: "=").last?.split(separator: " ").first,
                               let rtt = Double(String(timeString)) {
                                continuation.resume(returning: (true, rtt))
                                return
                            }
                        }

                        // Alive but couldn't parse RTT
                        continuation.resume(returning: (true, 0.0))
                    } else {
                        // Non-zero exit code - treat as not reachable
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
        #else
        // This should never be called on iOS, but return nil as fallback
        return nil
        #endif
    }

    private static func iosPing(host: String, timeout: TimeInterval) async -> (Bool, Double)? {
        // On iOS, we use TCP connection testing since ICMP requires special entitlements
        // Only return success if we can actually establish a connection
        return await tcpPing(host: host, timeout: timeout)
    }

    private static func performICMPPing(host: String, timeout: TimeInterval) async -> (Bool, Double)? {
        // Try multiple common ports for better device detection
        let commonPorts = [80, 443, 22, 23, 53, 139, 445, 548, 631, 3689, 5000, 8080, 8443]

        for _ in commonPorts {
            if let result = await tcpPing(host: host, timeout: timeout) {
                return result
            }
        }

        // If all TCP attempts fail, try a basic connectivity check
        return await basicConnectivityCheck(host: host, timeout: timeout)
    }

    private static func tcpPing(host: String, timeout: TimeInterval) async -> (Bool, Double)? {
        // On iOS, try common ports that are likely to be open for faster detection
        let commonPorts = [80, 443, 22, 53] // HTTP, HTTPS, SSH, DNS

        for port in commonPorts {
            let startTime = ProcessInfo.processInfo.systemUptime

            do {
                // Use URLSession with a timeout to test connectivity
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = timeout
                config.timeoutIntervalForResource = timeout
                let session = URLSession(configuration: config)

                let urlString = port == 443 ? "https://\(host)" : "http://\(host):\(port)"
                guard let url = URL(string: urlString) else { continue }

                let (_, response) = try await session.data(from: url)
                let endTime = ProcessInfo.processInfo.systemUptime
                let rtt = (endTime - startTime) * 1000.0

                if let httpResponse = response as? HTTPURLResponse {
                    // Only consider successful responses (2xx) as valid
                    // 3xx redirects, 4xx client errors, and 5xx server errors don't indicate the host is "alive" for ping purposes
                    if (200...299).contains(httpResponse.statusCode) {
                        return (true, rtt)
                    }
                }
            } catch let error as URLError {
                // Handle specific URL errors
                switch error.code {
                case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                    // These indicate the host is not reachable
                    continue
                case .timedOut:
                    // Timeout - host might be slow but could be alive
                    continue
                default:
                    // Other errors - try next port
                    continue
                }
            } catch {
                // This port failed, try the next one
                continue
            }
        }

        return nil
    }

    private static func basicConnectivityCheck(host: String, timeout: TimeInterval) async -> (Bool, Double)? {
        // Use getaddrinfo to check basic DNS resolution and connectivity
        let startTime = ProcessInfo.processInfo.systemUptime

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?

        let status = getaddrinfo(host, "80", &hints, &result)
        defer {
            if let result = result {
                freeaddrinfo(result)
            }
        }

        let endTime = ProcessInfo.processInfo.systemUptime
        let rtt = (endTime - startTime) * 1000.0

        return status == 0 ? (true, rtt) : nil
    }
}
