import Foundation
import os

enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    var prefix: String {
        switch self {
        case .debug: return "🐛 DEBUG"
        case .info: return "ℹ️ INFO"
        case .warning: return "⚠️ WARNING"
        case .error: return "🚨 ERROR"
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum LogCategory: String {
    case general = "General"
    case ui = "UI"
    case youtube = "YouTube"
    case favorites = "Favorites"
    case network = "Network"
}

class Logger {
    static let shared = Logger()
    
    // Configuration
    var minimumLevel: LogLevel = .debug
    var enabledCategories: Set<LogCategory>? = nil // nil means all enabled
    
    private init() {}
    
    static func debug(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, category: category, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, category: category, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, category: category, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, category: category, file: file, function: function, line: line)
    }
    
    private static func log(_ level: LogLevel, _ message: String, category: LogCategory, file: String, function: String, line: Int) {
        guard level >= shared.minimumLevel else { return }
        
        if let enabled = shared.enabledCategories, !enabled.contains(category) {
            return
        }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone.current, formatOptions: [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime])
        
        // Format: [TIMESTAMP] [LEVEL] [CATEGORY] [File:Line] Message
        let logMessage = "[\(timestamp)] \(level.prefix) [\(category.rawValue)] [\(fileName):\(line)] \(message)"
        
        // Print to console (native print checks scheme settings, but we assume we want to see it)
        print(logMessage)
        
        // TODO: Could integrate with OSLog for deeper system tracing
    }
}
