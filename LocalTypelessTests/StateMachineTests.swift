import XCTest
@testable import LocalTypeless

@MainActor
final class StateMachineTests: XCTestCase {

    func test_initialStateIsIdle() {
        let sm = StateMachine()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_toggleFromIdleStartsRecording() {
        let sm = StateMachine()
        sm.toggle()
        XCTAssertEqual(sm.state, .recording)
    }

    func test_toggleFromRecordingGoesToTranscribing() {
        let sm = StateMachine()
        sm.toggle()
        sm.toggle()
        XCTAssertEqual(sm.state, .transcribing)
    }

    func test_advanceFromTranscribingGoesToPolishing() {
        let sm = StateMachine()
        sm.toggle()
        sm.toggle()
        sm.advance()
        XCTAssertEqual(sm.state, .polishing)
    }

    func test_advanceFromPolishingGoesToInjecting() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle(); sm.advance()
        sm.advance()
        XCTAssertEqual(sm.state, .injecting)
    }

    func test_advanceFromInjectingReturnsToIdle() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle(); sm.advance(); sm.advance()
        sm.advance()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_failMovesToErrorFromAnyProcessingState() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle()
        sm.fail(message: "boom")
        if case .error(let msg) = sm.state {
            XCTAssertEqual(msg, "boom")
        } else {
            XCTFail("expected error state, got \(sm.state)")
        }
    }

    func test_toggleFromErrorReturnsToIdle() {
        let sm = StateMachine()
        sm.fail(message: "x")
        sm.toggle()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_toggleWhileTranscribingIsIgnored() {
        let sm = StateMachine()
        sm.toggle(); sm.toggle()
        sm.toggle()
        XCTAssertEqual(sm.state, .transcribing)
    }
}
