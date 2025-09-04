import Foundation
import NIO
import NIOCore

/// An ICMP packet structure for ping requests and responses
struct ICMPPacket {
    var type: UInt8 = 8 // Echo Request
    var code: UInt8 = 0
    var checksum: UInt16 = 0
    var identifier: UInt16
    var sequenceNumber: UInt16
    var payload: Data
    
    init(
        identifier: UInt16 = UInt16.random(in: 0...UInt16.max),
        sequenceNumber: UInt16 = 0,
        payload: Data = Data("NetScan Ping".utf8)
    ) {
        self.identifier = identifier
        self.sequenceNumber = sequenceNumber
        self.payload = payload
    }
    
    func toByteBuffer() -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 8 + payload.count)
        buffer.writeInteger(type)
        buffer.writeInteger(code)
        buffer.writeInteger(UInt16(0)) // Temporary checksum placeholder
        buffer.writeInteger(identifier)
        buffer.writeInteger(sequenceNumber)
        buffer.writeBytes(payload)
        
        // Calculate and set checksum
        let checksum = calculateChecksum(buffer: buffer)
        buffer.setInteger(checksum, at: 2)
        return buffer
    }
    
    func calculateChecksum(buffer: ByteBuffer) -> UInt16 {
        // ICMP checksum calculation
        var sum: UInt32 = 0
        let bytes = buffer.getBytes(at: 0, length: buffer.readableBytes) ?? []
        
        // Process 16-bit chunks
        for i in stride(from: 0, to: bytes.count - 1, by: 2) {
            let word = (UInt32(bytes[i]) << 8) | UInt32(bytes[i + 1])
            sum += word
        }
        
        // Add last byte if length is odd
        if bytes.count % 2 == 1 {
            sum += UInt32(bytes[bytes.count - 1]) << 8
        }
        
        // Fold 32-bit sum to 16 bits
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        
        return ~UInt16(truncatingIfNeeded: sum)
    }
}
