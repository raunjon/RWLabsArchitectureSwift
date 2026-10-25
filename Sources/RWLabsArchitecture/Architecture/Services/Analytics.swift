//
//  Analytics.swift
//  RWLabsArchitecture
//
//  Analytics protocol and a console implementation
//

import Foundation

// MARK: - AnalyticsService

/// Tracks events, screens and user properties. Apps register their own
/// implementation (or `ConsoleAnalyticsService` during development).
public protocol AnalyticsService: Service {
    func trackEvent(_ name: String, parameters: [String: Any]?)
    func trackScreen(_ name: String)
    func setUserProperty(_ name: String, value: String)
}

// MARK: - ConsoleAnalyticsService

/// An `AnalyticsService` that prints every call to the console
public final class ConsoleAnalyticsService: AnalyticsService {
    public init() {}

    public func trackEvent(_ name: String, parameters: [String: Any]?) {
        print("[Analytics] Event: \(name), Parameters: \(parameters ?? [:])")
    }

    public func trackScreen(_ name: String) {
        print("[Analytics] Screen: \(name)")
    }

    public func setUserProperty(_ name: String, value: String) {
        print("[Analytics] User Property: \(name) = \(value)")
    }
}
