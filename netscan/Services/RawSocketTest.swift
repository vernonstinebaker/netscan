import Foundation
import Network

// Test if low-level network operations work in a sandboxed environment
func testRawSocketAccess() {
    // Instead of directly trying to use NIO's raw sockets (which require special permissions),
    // we'll test what's possible with Network framework
    print("Testing network permissions...")
    
    // Test 1: Create a standard TCP connection
    let tcpEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("8.8.8.8"), port: NWEndpoint.Port(rawValue: 53)!)
    let tcpParams = NWParameters.tcp
    let tcpConnection = NWConnection(to: tcpEndpoint, using: tcpParams)
    
    tcpConnection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("✅ TCP Connection successful")
            tcpConnection.cancel()
        case .failed(let error):
            print("❌ TCP Connection failed: \(error)")
            tcpConnection.cancel()
        case .cancelled:
            print("TCP Connection cancelled")
        default:
            break
        }
    }
    
    // Test 2: Create a UDP connection
    let udpEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("8.8.8.8"), port: NWEndpoint.Port(rawValue: 53)!)
    let udpParams = NWParameters.udp
    let udpConnection = NWConnection(to: udpEndpoint, using: udpParams)
    
    udpConnection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("✅ UDP Connection successful")
            udpConnection.cancel()
        case .failed(let error):
            print("❌ UDP Connection failed: \(error)")
            udpConnection.cancel()
        case .cancelled:
            print("UDP Connection cancelled")
        default:
            break
        }
    }
    
    // Test 3: Try to create a connection with custom IP options (which might require elevated permissions)
    let customParams = NWParameters.tcp
    customParams.includePeerToPeer = true
    
    // Try some options that are more likely to require special permissions
    customParams.prohibitExpensivePaths = false
    customParams.requiredInterfaceType = .wifi
    customParams.allowLocalEndpointReuse = true
    print("📋 Added custom network parameters to test permission levels")
    
    let customConnection = NWConnection(to: tcpEndpoint, using: customParams)
    customConnection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("✅ Custom parameters connection successful")
            customConnection.cancel()
        case .failed(let error):
            print("❌ Custom parameters connection failed: \(error)")
            customConnection.cancel()
        case .cancelled:
            print("Custom parameters connection cancelled")
        default:
            break
        }
    }
    
    // Start all test connections
    print("Starting network permission tests...")
    tcpConnection.start(queue: .global())
    udpConnection.start(queue: .global())
    customConnection.start(queue: .global())
}
