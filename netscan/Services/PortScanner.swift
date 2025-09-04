import Foundation
import Network
import Darwin

public actor PortScanner {
    private let host: NWEndpoint.Host
    
    public init(host: String) {
        self.host = NWEndpoint.Host(host)
    }
    
    public func scanPorts(portRange: ClosedRange<UInt16>) async -> [Port] {
        var openPorts: [Port] = []
        
        // Scan common ports instead of the full range to avoid performance issues
        let commonPorts: [UInt16] = [21, 22, 23, 25, 53, 80, 110, 143, 443, 993, 995]
        let portsToScan = commonPorts.filter { portRange.contains($0) }
        
        for port in portsToScan {
            if await isPortOpen(port) {
                let name = self.getServiceName(for: port)
                let portInfo = await MainActor.run { Port(number: Int(port), serviceName: name, description: "Open", status: .open) }
                openPorts.append(portInfo)
            }
        }
        
        return openPorts
    }
    
    private func isPortOpen(_ port: UInt16) async -> Bool {
        return await Task.detached {
            let host = String(describing: self.host)
            let portValue = in_port_t(port.bigEndian)
            
            // Create socket
            let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else { return false }
            defer { close(fd) }
            
            // Set non-blocking
            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            
            // Setup address
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = portValue
            _ = host.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
            
            // Attempt connection
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                    Darwin.connect(fd, addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            if result == 0 {
                return true // Connected immediately
            } else if errno == EINPROGRESS {
                // Wait for connection with select
                var tv = timeval(tv_sec: 1, tv_usec: 0)
                var readfds = fd_set()
                var writefds = fd_set()
                
                // Use Darwin functions for fd_set manipulation
                Darwin.bzero(&readfds, MemoryLayout<fd_set>.size)
                Darwin.bzero(&writefds, MemoryLayout<fd_set>.size)
                
                // Set the file descriptor in writefds
                let wordIndex = Int(fd) / (MemoryLayout<Int32>.size * 8)
                let bitIndex = Int(fd) % (MemoryLayout<Int32>.size * 8)
                
                withUnsafeMutablePointer(to: &writefds) { ptr in
                    ptr.withMemoryRebound(to: Int32.self, capacity: 32) { intPtr in
                        intPtr[wordIndex] |= Int32(1 << bitIndex)
                    }
                }
                
                let selectResult = Darwin.select(fd + 1, &readfds, &writefds, nil, &tv)
                
                if selectResult > 0 {
                    // Check if our fd is set in writefds
                    var isSet = false
                    withUnsafeMutablePointer(to: &writefds) { ptr in
                        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { intPtr in
                            isSet = (intPtr[wordIndex] & Int32(1 << bitIndex)) != 0
                        }
                    }
                    
                    if isSet {
                        var soError: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 && soError == 0 {
                            return true
                        }
                    }
                }
            }
            
            return false
        }.value
    }
    
    private func getServiceName(for port: UInt16) -> String {
        switch port {
        case 21: return "ftp"
        case 22: return "ssh"
        case 23: return "telnet"
        case 25: return "smtp"
        case 53: return "dns"
        case 80: return "http"
        case 110: return "pop3"
        case 143: return "imap"
        case 443: return "https"
        case 993: return "imaps"
        case 995: return "pop3s"
        default: return "unknown"
        }
    }
}
