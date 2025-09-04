import Foundation
import Network

@available(macOS 10.14, iOS 12.0, *)
public enum NetworkFrameworkProber {
    public enum Result: Sendable { case alive(Double?), dead }
    
    public nonisolated static func probe(ip: String, port: UInt16 = 80, timeout: TimeInterval = 0.75) async -> Result {
        let parsed: IPv4.Address? = await MainActor.run { IPv4.parse(ip) }
        guard parsed != nil else { return .dead }
        
        return await withCheckedContinuation { continuation in
            let start = DispatchTime.now().uptimeNanoseconds
            let actor = NetworkContinuationActor(continuation: continuation)
            
            // Create connection using Network framework with less restrictive parameters
            let host = NWEndpoint.Host(ip)
            let portEndpoint = NWEndpoint.Port(rawValue: port) ?? .http
            let endpoint = NWEndpoint.hostPort(host: host, port: portEndpoint)
            
            // Use TCP with default parameters (no custom options that might require extra permissions)
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi // Prefer WiFi to avoid cellular restrictions
            parameters.prohibitExpensivePaths = false
            parameters.allowLocalEndpointReuse = true
            
            let connection = NWConnection(to: endpoint, using: parameters)
            
            // Set up timeout with shorter duration to fail faster if permissions are denied
            let actualTimeout = min(timeout, 2.0) // Cap at 2 seconds
            let timeoutWorkItem = DispatchWorkItem {
                connection.cancel()
                Task { await actor.resume(with: .dead) }
            }
            
            DispatchQueue.global().asyncAfter(deadline: .now() + actualTimeout, execute: timeoutWorkItem)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeoutWorkItem.cancel()
                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
                    connection.cancel()
                    Task { await actor.resume(with: .alive(elapsedMs)) }
                    
                case .failed(let error):
                    timeoutWorkItem.cancel()
                    connection.cancel()
                    
                    // Log the specific error for debugging
                    print("[NetworkFrameworkProber] Connection failed to \(ip):\(port) - \(error)")
                    
                    // Connection refused typically means the host is alive but port is closed
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
                        Task { await actor.resume(with: .alive(elapsedMs)) }
                    } else {
                        Task { await actor.resume(with: .dead) }
                    }
                    
                case .cancelled:
                    timeoutWorkItem.cancel()
                    Task { await actor.resume(with: .dead) }
                    
                default:
                    break
                }
            }
            
            // Start connection on a background queue
            connection.start(queue: .global(qos: .utility))
        }
    }
}

// Thread-safe actor for managing continuations
private actor NetworkContinuationActor<T> {
    private var continuation: CheckedContinuation<T, Never>
    private var hasResumed = false
    
    init(continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }
    
    func resume(with value: T) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }
}
