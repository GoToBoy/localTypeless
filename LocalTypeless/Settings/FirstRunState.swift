import Foundation

@MainActor
final class FirstRunState {

    private let defaults: UserDefaults
    private let key = "onboardingCompleted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboardingCompleted: Bool {
        defaults.bool(forKey: key)
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: key)
    }

    /// Exposed for testing + reset via Settings "Reset welcome" action.
    func reset() {
        defaults.removeObject(forKey: key)
    }
}
