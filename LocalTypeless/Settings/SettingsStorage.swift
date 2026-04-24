import Foundation

protocol SettingsStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func string(forKey key: String) -> String?
    func set(_ string: String?, forKey key: String)
    func bool(forKey key: String) -> Bool
    func set(_ bool: Bool, forKey key: String)
    func integer(forKey key: String) -> Int
    func set(_ int: Int, forKey key: String)
    func contains(_ key: String) -> Bool
}

final class UserDefaultsSettingsStorage: SettingsStorage {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func set(_ string: String?, forKey key: String) { defaults.set(string, forKey: key) }
    func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    func set(_ bool: Bool, forKey key: String) { defaults.set(bool, forKey: key) }
    func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    func set(_ int: Int, forKey key: String) { defaults.set(int, forKey: key) }
    func contains(_ key: String) -> Bool { defaults.object(forKey: key) != nil }
}

final class InMemorySettingsStorage: SettingsStorage {
    private var store: [String: Any] = [:]
    func data(forKey key: String) -> Data? { store[key] as? Data }
    func set(_ data: Data?, forKey key: String) { store[key] = data }
    func string(forKey key: String) -> String? { store[key] as? String }
    func set(_ string: String?, forKey key: String) { store[key] = string }
    func bool(forKey key: String) -> Bool { store[key] as? Bool ?? false }
    func set(_ bool: Bool, forKey key: String) { store[key] = bool }
    func integer(forKey key: String) -> Int { store[key] as? Int ?? 0 }
    func set(_ int: Int, forKey key: String) { store[key] = int }
    func contains(_ key: String) -> Bool { store[key] != nil }
}
