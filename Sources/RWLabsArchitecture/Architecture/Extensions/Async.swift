//
//  Async.swift
//  RWLabsArchitecture
//
//  Shorthands for dispatching work
//

import Foundation

/// Shorthands for `DispatchQueue`: `Async.main { … }`, `Async.background { … }`, `Async.after(0.3) { … }`
public enum Async {
    /// Runs `block` on the main queue, asynchronously
    public static func main(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    /// Runs `block` on a global queue with quality of service `qos`
    public static func background(qos: DispatchQoS.QoSClass = .default, _ block: @escaping () -> Void) {
        DispatchQueue.global(qos: qos).async(execute: block)
    }

    /// Runs `block` on the main queue after `delay` seconds
    public static func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}
