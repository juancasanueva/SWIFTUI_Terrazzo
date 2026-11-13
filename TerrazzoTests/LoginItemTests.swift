import ServiceManagement
import Testing
@testable import Terrazzo

struct LoginItemTests {
    @Test(arguments: [SMAppService.Status.notRegistered, .notFound])
    func turningOffAnItemThatIsNotRegisteredChangesNothing(status: SMAppService.Status) {
        #expect(LoginItemChange.needed(openAtLogin: false, status: status) == nil)
    }

    @Test func turningOnAnItemThatIsAlreadyEnabledChangesNothing() {
        #expect(LoginItemChange.needed(openAtLogin: true, status: .enabled) == nil)
    }

    @Test(arguments: [SMAppService.Status.enabled, .requiresApproval])
    func turningOffARegisteredItemUnregistersIt(status: SMAppService.Status) {
        #expect(LoginItemChange.needed(openAtLogin: false, status: status) == .unregister)
    }

    @Test(arguments: [SMAppService.Status.notRegistered, .notFound, .requiresApproval])
    func turningOnAnItemThatIsNotEnabledRegistersIt(status: SMAppService.Status) {
        #expect(LoginItemChange.needed(openAtLogin: true, status: status) == .register)
    }
}
