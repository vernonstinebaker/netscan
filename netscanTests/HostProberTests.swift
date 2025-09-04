import Testing
import Network
@testable import netscan

struct HostProberTests {
    @Test func classifyRefusedIsAlive() async throws {
        let error = NWError.posix(.ECONNREFUSED)
        #expect(HostProber.classify(error: error) == true)
    }

    @Test func classifyOtherIsDead() async throws {
        let error = NWError.posix(.ETIMEDOUT)
        #expect(HostProber.classify(error: error) == false)
    }
}
