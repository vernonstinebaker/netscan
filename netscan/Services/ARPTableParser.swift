import Foundation

/// Service for parsing ARP table to get MAC addresses for IP addresses
public actor ARPTableParser {
    
    public struct ARPEntry {
        public let ipAddress: String
        public let macAddress: String
        public let interface: String
        
        public init(ipAddress: String, macAddress: String, interface: String) {
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.interface = interface
        }
    }
    
    public init() {}
    
    /// Parse the system ARP table to get MAC addresses for IP addresses
    public func getARPTable() async -> [ARPEntry] {
        #if os(macOS)
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-a"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            return parseARPOutput(output)
        } catch {
            print("[ARPTableParser] Error running arp command: \(error)")
            return []
        }
        #else
        // Not supported on non-macOS platforms
        return []
        #endif
    }
    
    /// Get MAC address for a specific IP address
    public func getMACAddress(for ipAddress: String) async -> String? {
        let arpTable = await getARPTable()
        return arpTable.first { $0.ipAddress == ipAddress }?.macAddress
    }
    
    /// Parse the output of the `arp -a` command
    internal func parseARPOutput(_ output: String) -> [ARPEntry] {
        var entries: [ARPEntry] = []
        
        let lines = output.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Parse line like: "hostname (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]"
            let components = trimmed.split(separator: " ")
            guard components.count >= 4 else { continue }
            
            // Find the IP address in parentheses
            var ipAddress = ""
            var macAddress = ""
            var interface = ""
            
            for (index, component) in components.enumerated() {
                if component.hasPrefix("(") && component.hasSuffix(")"),
                   let ipStart = component.firstIndex(of: "("),
                   let ipEnd = component.firstIndex(of: ")") {
                    let ipRange = component.index(after: ipStart)..<ipEnd
                    ipAddress = String(component[ipRange])
                }
                
                if component == "at" && index + 1 < components.count {
                    macAddress = String(components[index + 1])
                }
                
                if component == "on" && index + 1 < components.count {
                    interface = String(components[index + 1])
                }
            }
            
            // Validate MAC address format (should be xx:xx:xx:xx:xx:xx)
            if !ipAddress.isEmpty && isValidMACAddress(macAddress) && !interface.isEmpty {
                entries.append(ARPEntry(ipAddress: ipAddress, macAddress: macAddress, interface: interface))
            }
        }
        
        return entries
    }
    
    /// Validate MAC address format
    internal func isValidMACAddress(_ mac: String) -> Bool {
        let macRegex = "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", macRegex)
        return predicate.evaluate(with: mac)
    }
}
