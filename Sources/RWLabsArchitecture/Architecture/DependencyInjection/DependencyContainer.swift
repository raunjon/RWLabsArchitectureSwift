//
//  DependencyContainer.swift
//  RWLabsArchitecture
//
//  Thread-safe registry for app dependencies
//

import Foundation

// MARK: - DependencyContainer

/// The app's dependency registry, read by `@Injected`, `@LazyInjected` and `@OptionalInjected`.
///
/// ```swift
/// let container = DependencyContainer.shared
/// container.registerSingleton(ErrorService.self, instance: AppErrorService())  // one existing instance
/// container.registerLazySingleton(Database.self) { Database(path: dbPath) }    // built on first resolve
/// container.register(APIClient.self) { DefaultAPIClient() }                    // new instance per resolve
///
/// let api = container.resolve(APIClient.self)
/// ```
///
/// Types are keyed by identity, so register a protocol as the protocol type
/// (`ErrorService.self`) and resolve it the same way. Safe to use from any thread.
///
/// Registered singletons that conform to `Service` are started by
/// `startServices()` and stopped by `stopServices()` (`AppCoordinator` calls both).
public final class DependencyContainer: @unchecked Sendable {
    /// The shared container
    public static let shared = DependencyContainer()

    private enum Entry {
        case instance(Any)
        case factory(() -> Any)
        case lazySingleton(() -> Any)
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// Keys in first-registration order, so services start in that order and stop in reverse
    private var registrationOrder: [ObjectIdentifier] = []

    /// Whether `startServices()` has run; lazy singletons created afterwards are started on creation
    private var servicesStarted = false

    /// Recursive so a factory can resolve its own dependencies while the lock is held
    private let lock = NSRecursiveLock()

    private init() {}

    // MARK: - Registration

    /// Registers a factory; every `resolve` returns a new instance
    public func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        set(.factory { factory() }, for: type)
    }

    /// Registers an existing instance; every `resolve` returns it
    public func registerSingleton<T>(_ type: T.Type, instance: T) {
        set(.instance(instance), for: type)
    }

    /// Registers a singleton that `factory` creates on the first `resolve`; later resolves reuse it
    public func registerLazySingleton<T>(_ type: T.Type, factory: @escaping () -> T) {
        set(.lazySingleton { factory() }, for: type)
    }

    // MARK: - Resolution

    /// Resolves `type`, crashing if it isn't registered
    public func resolve<T>(_ type: T.Type) -> T {
        guard let value = resolveOptional(type) else {
            fatalError("Dependency \(type) not registered. Did you forget to register it?")
        }
        return value
    }

    /// Resolves `type`, or returns `nil` if it isn't registered
    public func resolveOptional<T>(_ type: T.Type) -> T? {
        var serviceToStart: Service?
        let resolved: T? = lock.withLock {
            let key = ObjectIdentifier(type)
            switch entries[key] {
            case .instance(let value):
                return value as? T
            case .factory(let make):
                return make() as? T
            case .lazySingleton(let make):
                let value = make()
                entries[key] = .instance(value)
                if servicesStarted {
                    serviceToStart = value as? Service
                }
                return value as? T
            case nil:
                return nil
            }
        }
        // Outside the lock, so a service's start() can take its time or resolve other dependencies
        serviceToStart?.start()
        return resolved
    }

    /// Whether anything is registered for `type`, without resolving it
    public func isRegistered<T>(_ type: T.Type) -> Bool {
        lock.withLock { entries[ObjectIdentifier(type)] != nil }
    }

    // MARK: - Service Lifecycle

    /// Calls `start()` on every registered singleton that conforms to `Service`, in
    /// registration order. Lazy singletons aren't created by this; they're started
    /// when first resolved. Factory registrations aren't started. Does nothing if already started.
    public func startServices() {
        let services: [Service] = lock.withLock {
            guard !servicesStarted else { return [] }
            servicesStarted = true
            return singletonServices()
        }
        services.forEach { $0.start() }
    }

    /// Calls `stop()` on every created singleton `Service`, in reverse registration order
    public func stopServices() {
        let services: [Service] = lock.withLock {
            guard servicesStarted else { return [] }
            servicesStarted = false
            return singletonServices()
        }
        services.reversed().forEach { $0.stop() }
    }

    /// Created singleton services in registration order; an instance registered under several types appears once
    private func singletonServices() -> [Service] {
        var seen = Set<ObjectIdentifier>()
        return registrationOrder.compactMap { key -> Service? in
            guard case .instance(let value)? = entries[key], let service = value as? Service else { return nil }
            if type(of: value) is AnyClass {
                let identity = ObjectIdentifier(value as AnyObject)
                guard seen.insert(identity).inserted else { return nil }
            }
            return service
        }
    }

    // MARK: - Utilities

    /// Removes every registration, e.g. between tests. Doesn't stop services; call `stopServices()` first.
    public func clear() {
        lock.withLock {
            entries.removeAll()
            registrationOrder.removeAll()
            servicesStarted = false
        }
    }

    private func set<T>(_ entry: Entry, for type: T.Type) {
        lock.withLock {
            let key = ObjectIdentifier(type)
            if entries[key] == nil {
                registrationOrder.append(key)
            }
            entries[key] = entry
        }
    }
}

/// A type the container can build with no arguments, so `registerRepository` can create it
public protocol Repository {
    init()
}

public extension DependencyContainer {
    /// Registers one new instance of `type` as a singleton
    func registerRepository<T: Repository>(_ type: T.Type) {
        registerSingleton(type, instance: type.init())
    }
}
