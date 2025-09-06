import Foundation

/// Minimal Process-based ping helper that runs the system ping and parses RTT.
/// Designed to be sandbox-friendly by invoking the system binary and returning a simple result.
public struct SimplePing {
    /// Ping a host once and return (isAlive, rttMs?) or nil on timeout/error.
    public static func ping(host: String, timeout: TimeInterval = 1.0) async -> (Bool, Double)? {
#if os(macOS)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")

                // Use a single ICMP echo request with timeout.
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
        // Not supported on non-macOS platforms in this helper
        return nil
#endif
    }
}
