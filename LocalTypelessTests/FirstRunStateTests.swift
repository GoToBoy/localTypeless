import XCTest
@testable import LocalTypeless

@MainActor
final class FirstRunStateTests: XCTestCase {

    func test_default_not_completed() {
        let defaults = UserDefaults(suiteName: "FirstRunTests")!
        defaults.removePersistentDomain(forName: "FirstRunTests")
        let state = FirstRunState(defaults: defaults)
        XCTAssertFalse(state.onboardingCompleted)
    }

    func test_markCompleted_persists() {
        let defaults = UserDefaults(suiteName: "FirstRunTests")!
        defaults.removePersistentDomain(forName: "FirstRunTests")
        let state = FirstRunState(defaults: defaults)
        state.markOnboardingCompleted()
        XCTAssertTrue(state.onboardingCompleted)

        // New instance, same defaults
        let state2 = FirstRunState(defaults: defaults)
        XCTAssertTrue(state2.onboardingCompleted)
    }
}
