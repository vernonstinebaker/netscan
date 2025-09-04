import Foundation

public struct NetworkInfo: Equatable, Sendable, CustomStringConvertible {
    public let ip: String
    public let netmask: String
    public let cidr: Int
    public let network: String
    public let broadcast: String

    public init(ip: String, netmask: String, cidr: Int, network: String, broadcast: String) {
        self.ip = ip
        self.netmask = netmask
        self.cidr = cidr
        self.network = network
        self.broadcast = broadcast
    }
    
    public var description: String {
        return "NetworkInfo(ip: \(ip), network: \(network), cidr: \(cidr))"
    }
}
