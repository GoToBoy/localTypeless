import Foundation
import os

enum Log {
    static let subsystem = "com.localtypeless.app"
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    static let asr = Logger(subsystem: subsystem, category: "asr")
    static let polish = Logger(subsystem: subsystem, category: "polish")
    static let injector = Logger(subsystem: subsystem, category: "injector")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let state = Logger(subsystem: subsystem, category: "state")
    static let menu = Logger(subsystem: subsystem, category: "menu")
}
