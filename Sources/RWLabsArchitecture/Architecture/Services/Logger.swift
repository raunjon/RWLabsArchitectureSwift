//
//  Logger.swift
//  RWLabsArchitecture
//
//  Logging protocol, a console logger, and the `Log` shortcuts
//

import Foundation

// MARK: - LoggerService

/// Writes log messages. Implement `log(_:level:error:file:function:line:)`;
/// the per-level methods (`info`, `error`, …) come from the extension.
///
/// ```swift
/// @Injected var logger: LoggerService
/// logger.info("Signed in")
/// logger.error("Sync failed", error: error)
/// ```
public protocol LoggerService: Service {
    /// Writes one message; every per-level method calls this
    func log(_ message: String, level: LogLevel, error: Error?, file: String, function: String, line: Int)
}

public extension LoggerService {
    func debug(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .debug, error: nil, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .info, error: nil, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .warning, error: nil, file: file, function: function, line: line)
    }

    func error(_ message: String, error: Error? = nil, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .error, error: error, file: file, function: function, line: line)
    }

    func success(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .success, error: nil, file: file, function: function, line: line)
    }

    func network(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .network, error: nil, file: file, function: function, line: line)
    }

    func data(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .data, error: nil, file: file, function: function, line: line)
    }

    func ui(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .ui, error: nil, file: file, function: function, line: line)
    }
}

// MARK: - LogLevel

public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case success = "SUCCESS"
    case network = "NETWORK"
    case ui = "UI"
    case data = "DATA"

    /// The level with an emoji, for console output
    public var display: String {
        switch self {
        case .debug: return "🔵 DEBUG"
        case .error: return "❌ ERROR"
        case .info: return "ℹ️ INFO"
        case .warning: return "⚠️ WARNING"
        case .success: return "✅ SUCCESS"
        case .network: return "🌐 NETWORK"
        case .ui: return "🎨 UI"
        case .data: return "💾 DATA"
        }
    }
}

// MARK: - ConsoleLogger

/// A `LoggerService` that prints to the console: timestamp, level, file, line
/// and function in debug builds; just the level and message in release builds.
public final class ConsoleLogger: LoggerService {
    public init() {}

    public func log(_ message: String, level: LogLevel, error: Error?, file: String, function: String, line: Int) {
        var text = message
        if let error {
            text += " - Error: \(error.localizedDescription)"
        }
        #if DEBUG
        let fileName = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        print("[\(Self.timestampFormatter.string(from: Date()))] \(level.display) [\(fileName):\(line)] \(function) - \(text)")
        #endif
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Log

/// Static shortcuts to the registered `LoggerService`, callable from any thread.
///
/// The logger is looked up on each call, so it can be registered at any time.
/// Messages are dropped if no `LoggerService` is registered.
///
/// ```swift
/// Log.i("Signed in")
/// Log.e("Sync failed", error: error)
/// ```
public enum Log {
    public static func d(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .debug, nil, file, function, line)
    }

    public static func i(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .info, nil, file, function, line)
    }

    public static func w(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .warning, nil, file, function, line)
    }

    public static func e(_ message: String, error: Error? = nil, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .error, error, file, function, line)
    }

    public static func s(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .success, nil, file, function, line)
    }

    public static func data(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .data, nil, file, function, line)
    }

    public static func network(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .network, nil, file, function, line)
    }

    public static func ui(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        write(message, .ui, nil, file, function, line)
    }

    private static func write(_ message: String, _ level: LogLevel, _ error: Error?, _ file: String, _ function: String, _ line: Int) {
        DependencyContainer.shared.resolveOptional(LoggerService.self)?
            .log(message, level: level, error: error, file: file, function: function, line: line)
    }
}
