import Foundation
import Network

// WS-Discovery (UDP 3702) probe to discover devices that respond to WS-Discovery (common on Windows/Printers)
public actor WSDiscoveryDiscoverer {
    public struct Result: Sendable { public let ips: Set<String> }

    public init() {}

    public func discover(timeout: TimeInterval = 3.0) async -> Result {
        let groupHost = "239.255.255.250"
        let port: NWEndpoint.Port = 3702
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let connection = NWConnection(host: .init(groupHost), port: port, using: params)
        let deadline = Date().addingTimeInterval(timeout)
        var seenIPs = Set<String>()
        let queue = DispatchQueue.global(qos: .utility)

        @Sendable func wsProbe() -> Data {
            let uuid = UUID().uuidString.uppercased()
            // Minimal WS-Discovery Probe request (Probe for any types)
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">
              <e:Header>
                <w:MessageID>uuid:
            """ + uuid + """
                </w:MessageID>
                <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
                <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
              </e:Header>
              <e:Body>
                <d:Probe>
                  <d:Types/>
                </d:Probe>
              </e:Body>
            </e:Envelope>
            """
            return xml.data(using: .utf8) ?? Data()
        }

        connection.stateUpdateHandler = { state in
            if case .ready = state {
                let payload = wsProbe()
                connection.send(content: payload, completion: .contentProcessed { error in
                    if let err = error {
                        Task { @MainActor in
                            debugLog("WS-Discovery: send error: \(err)")
                        }
                    }
                })
            }
        }

        func parseXAddrsHost(from data: Data) -> [String] {
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return WSDiscoveryDiscoverer.parseXAddrsHosts(fromXML: text)
        }

        func receiveLoop() {
            connection.receiveMessage { data, remoteEndpoint, _, _ in
                if let data = data {
                    for host in parseXAddrsHost(from: data) {
                        // strip any interface scope
                        if let h = host.split(separator: "%").first { seenIPs.insert(String(h)) }
                    }
                }
                if Date() < deadline {
                    receiveLoop()
                } else {
                    connection.cancel()
                }
            }
        }

        connection.start(queue: queue)
        receiveLoop()

        try? await Task.sleep(nanoseconds: UInt64(max(0, timeout + 0.25)) * 1_000_000_000)
        return Result(ips: seenIPs)
    }

    // Exposed for testing: parse XAddrs URLs in WS-Disco ProbeMatch responses and extract hostnames
    public nonisolated static func parseXAddrsHosts(fromXML xml: String) -> [String] {
        // Find <d:XAddrs>...</d:XAddrs> (some devices use different ns prefixes, so match any :XAddrs)
        let lower = xml.lowercased()
        guard let startRange = lower.range(of: "<d:xaddrs>") ?? lower.range(of: ":xaddrs>") else {
            return []
        }
        let tail = lower[startRange.upperBound...]
        guard let endRange = tail.range(of: "</") else { return [] }
        let value = String(tail[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        // The value may contain one or multiple URLs separated by spaces
        let urls = value.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        var hosts: [String] = []
        for u in urls {
            if let url = URL(string: u), let host = url.host { hosts.append(host) }
        }
        return hosts
    }
}
