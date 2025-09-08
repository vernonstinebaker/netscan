// filepath: /Volumes/X9Pro/Local/Programming/Swift/netscan/netscan/Services/SSDPDiscoverer.swift
import Foundation
import Network

public actor SSDPDiscoverer {
    public struct Result: Sendable { public let ips: Set<String> }

    public init() {}

    public func discover(timeout: TimeInterval = 7.0) async -> Result {
        let groupHost = "239.255.255.250"
        let port: NWEndpoint.Port = 1900
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        // Try to use any available interface (WiFi preferred but not forced)
        // params.requiredInterfaceType = .wifi

        let connection = NWConnection(host: .init(groupHost), port: port, using: params)
        var seenIPs = Set<String>()
        let deadline = Date().addingTimeInterval(timeout)
        let queue = DispatchQueue.global(qos: .utility)

        connection.stateUpdateHandler = { state in
                if case .ready = state {
                    // Log path/interface/local endpoint for diagnostics
                    if let path = connection.currentPath {
                        let ifNames = path.availableInterfaces.map { $0.name }.joined(separator: ",")
                        print("SSDPDiscoverer: Connection ready - interfaces: [\(ifNames)] path: \(path)")
                    }
                    print("SSDPDiscoverer: Connection debug: \(connection.debugDescription)")

                    // Send multiple M-SEARCH requests with different service types
                    let searchRequests = [
                        ("ssdp:all", "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: ssdp:all\r\nUSER-AGENT: iOS NetScan\r\n\r\n"),
                        ("upnp:rootdevice", "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: upnp:rootdevice\r\nUSER-AGENT: iOS NetScan\r\n\r\n"),
                        ("urn:schemas-upnp-org:device:InternetGatewayDevice:1", "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\nUSER-AGENT: iOS NetScan\r\n\r\n")
                    ]

                    for (serviceType, payload) in searchRequests {
                        guard let data = payload.data(using: .utf8) else {
                            print("SSDPDiscoverer: Failed to encode payload for \(serviceType) as UTF-8")
                            continue
                        }
                        connection.send(content: data, completion: .contentProcessed { error in
                            if let err = error {
                                print("SSDPDiscoverer: send completion error for \(serviceType): \(err)")
                            } else {
                                print("SSDPDiscoverer: Sent M-SEARCH for \(serviceType)")
                            }
                        })
                    }
                }
        }

        func parseResponderIP(from data: Data) -> String? {
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            // Find LOCATION header (case-insensitive)
            let lines = text.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            if let locLineSub = lines.first(where: { $0.lowercased().hasPrefix("location:") }) {
                let locValue = locLineSub.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if let url = URL(string: String(locValue)), let host = url.host {
                    // Strip interface suffix if any
                    return host.split(separator: "%").first.map(String.init)
                }
            }
            return nil
        }

        func receiveLoop() {
            connection.receiveMessage { data, remoteEndpoint, _, _ in
                if let endpoint = remoteEndpoint {
                    print("SSDPDiscoverer: Received message from endpoint: \(endpoint)")
                }
                if let data = data {
                    if let text = String(data: data, encoding: .utf8) {
                        print("SSDPDiscoverer: Received response (text): \(text.prefix(1000))")
                    } else {
                        // Dump short hex preview if not UTF-8
                        let hex = data.prefix(200).map { String(format: "%02x", $0) }.joined(separator: " ")
                        print("SSDPDiscoverer: Received response (hex preview): \(hex)")
                    }
                    // Also print a short hex snippet for diagnostics
                    let hexPreview = data.prefix(120).map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("SSDPDiscoverer: Response hex preview: \(hexPreview)")

                    if let ip = parseResponderIP(from: data) {
                        print("SSDPDiscoverer: Found device at IP: \(ip)")
                        seenIPs.insert(ip)
                    }
                }
                if Date() < deadline {
                    receiveLoop()
                } else {
                    print("SSDPDiscoverer: Timeout reached, found \(seenIPs.count) devices")
                    connection.cancel()
                }
            }
        }

    debugLog("SSDPDiscoverer: Starting SSDP discovery (timeout: \(timeout)s)...")
    debugLog("SSDPDiscoverer: Using multicast group: \(groupHost):\(port)")
    connection.start(queue: queue)
    receiveLoop()

    // Wait until timeout elapses (give an extra 0.5s slack)
    try? await Task.sleep(nanoseconds: UInt64(max(0, timeout + 0.5)) * 1_000_000_000)
    debugLog("SSDPDiscoverer: Discovery complete, returning \(seenIPs.count) IPs: \(seenIPs)")
    return Result(ips: seenIPs)
    }
}
