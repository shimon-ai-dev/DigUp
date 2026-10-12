import Testing
@testable import DigUpApp

struct EngineRestartPolicyTests {
    @Test func fatalExitBeforeRetryAcknowledgementNeverRestarts() {
        for status in [Int32(1), 2, 9, 15] {
            #expect(!Engine.shouldRestartHelper(exitStatus: status, retryWanted: true, syncWanted: false))
            #expect(!Engine.shouldRestartHelper(exitStatus: status, retryWanted: true, syncWanted: true))
        }
    }
    @Test func cleanExitRetriesOnlyOutstandingRequests() {
        #expect(Engine.shouldRestartHelper(exitStatus: 0, retryWanted: true, syncWanted: false))
        #expect(Engine.shouldRestartHelper(exitStatus: 0, retryWanted: false, syncWanted: true))
        #expect(!Engine.shouldRestartHelper(exitStatus: 0, retryWanted: false, syncWanted: false))
    }
}
