import Foundation
import Darwin
import Network

public enum HostProber {
    public enum Result: Sendable { case alive(Double?), dead }
    
    // Classify NWError into host liveness. ECONNREFUSED => host alive (port closed), otherwise treat as dead.
    public static func classify(error: NWError) -> Bool {
        if case let .posix(code) = error, code == .ECONNREFUSED {
            return true
        }
        return false
    }
    
    public nonisolated static func probe(ip: String, port: UInt16 = 80, timeout: TimeInterval = 0.1) async throws -> Result {
        let parsed: IPv4.Address? = await MainActor.run { IPv4.parse(ip) }
        guard parsed != nil else { return .dead }
        
        // Check for cancellation before starting
        try Task.checkCancellation()

        let portValue = in_port_t(port.bigEndian)
        let start = DispatchTime.now().uptimeNanoseconds

        // Build sockaddr_in
        var saddr = sockaddr_in()
        saddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        saddr.sin_family = sa_family_t(AF_INET)
        saddr.sin_port = portValue
        var ina = in_addr()
        _ = ip.withCString { cstr in inet_pton(AF_INET, cstr, &ina) }
        saddr.sin_addr = ina

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return .dead }
        defer { _ = close(fd) }

        // Non-blocking
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var sa = unsafeBitCast(saddr, to: sockaddr.self)
        _ = withUnsafePointer(to: &sa) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { p in
                return Darwin.connect(fd, p, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if errno != EINPROGRESS {
            return .dead // Early exit on immediate failure
        }
        
        // Check for cancellation while waiting
        try Task.checkCancellation()

        // Wait for writability with poll up to timeout
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let toMs = Int32(max(0, min(timeout, 10.0)) * 1000.0)
        let pr = poll(&pfd, nfds_t(1), toMs)

        if pr <= 0 {
            return .dead // Timeout or error
        }

        // Check SO_ERROR to see if the non-blocking connect succeeded
        var soErr: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len) == 0 else {
            return .dead
        }

        if soErr == 0 {
            // Connection successful - port is open
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            return .alive(elapsedMs)
        } else if soErr == ECONNREFUSED {
            // Connection refused - port is closed but host is responding
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            return .alive(elapsedMs)
        } else if soErr == EHOSTUNREACH || soErr == ENETUNREACH || soErr == ETIMEDOUT {
            // Host unreachable, network unreachable, or timeout - host is definitely dead
            return .dead
        } else {
            // Other errors - treat as dead to be safe
            return .dead
        }
    }
}
