//
// Resolver.swift
//
// Copyright © 2017 Michael Long. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Foundation

public protocol ResolverRegistering {
    static func registerAllServices()
}

public protocol Resolving {
    var resolver: Resolver { get }
}

extension Resolving {
    public var resolver: Resolver {
        return Resolver.root
    }
}
public final class Resolver {

    // MARK: - Defaults

    /// Default registry used by the static Registration functions.
    public static let main: Resolver = Resolver()
    /// Default registry used by the static Resolution functions and by the Resolving protocol.
    public static var root: Resolver = main
    /// Default scope applied when registering new objects.
    public static var defaultScope = Resolver.graph

    // MARK: - Lifecycle

    public init(parent: Resolver? = nil) {
        self.parent = parent
    }

    /// Called by the Resolution functions to perform one-time initialization of the Resolver registries.
    public final func registerServices() {
        guard Resolver.registrationsNeeded else {
            return
        }
        Resolver.registrationsNeeded = false
        if let registering = (Resolver.main as Any) as? ResolverRegistering {
            type(of: registering).registerAllServices()
        }
    }

    // MARK: - Service Registration

    /// Static shortcut function used to register a specifc Service type and its instantiating factory method.
    @discardableResult
    public static func register<Service>(_ type: Service.Type = Service.self, name: String? = nil,
                                         factory: @escaping ResolverFactory<Service>) -> ResolverOptions<Service> {
        return main.register(type, name: name, factory: { (_,_) -> Service? in return factory() })
    }

    /// Static shortcut function used to register a specifc Service type and its instantiating factory method.
    /// The factory signature allows argments to be passed to the factory during resolution.
    @discardableResult
    public static func register<Service>(_ type: Service.Type = Service.self, name: String? = nil,
                                         factory: @escaping ResolverFactoryArguments<Service>) -> ResolverOptions<Service> {
        return main.register(type, name: name, factory: factory)
    }

    /// Registers a specifc Service type and its instantiating factory method.
    @discardableResult
    public final func register<Service>(_ type: Service.Type = Service.self, name: String? = nil,
                                        factory: @escaping ResolverFactory<Service>) -> ResolverOptions<Service> {
        return register(type, name: name, factory: { (_,_) -> Service? in return factory() })
    }

    /// Registers a specifc Service type and its instantiating factory method.
    /// The factory signature allows argments to be passed to the factory during resolution.
    @discardableResult
    public final func register<Service>(_ type: Service.Type = Service.self, name: String? = nil,
                                        factory: @escaping ResolverFactoryArguments<Service>) -> ResolverOptions<Service> {
        let key = ObjectIdentifier(Service.self).hashValue
        if let name = name {
            let registration = ResolverRegistration(resolver: self, key: key, factory: factory)
            if let container = registrations[key] as? ResolverRegistration<Service> {
                container.addRegistration(name, registration: registration)
            } else {
                let container = ResolverRegistration(resolver: self, key: key, factory: factory)
                container.addRegistration(name, registration: registration)
                registrations[key] = container
            }
            return registration
        } else if let registration = registrations[key] as? ResolverRegistration<Service> {
            registration.factory = factory
            return registration
        } else {
            let registration = ResolverRegistration(resolver: self, key: key, factory: factory)
            registrations[key] = registration
            return registration
        }
    }

    // MARK: - Service Resolution

    /// Static function calls the root registry to resolve a given Service type.
    static func resolve<Service>(_ type: Service.Type = Service.self, name: String? = nil, args: Any? = nil) -> Service {
        return root.resolve(type, name: name, args: args)
    }

    /// Resolves and returns an instance of the given Service type from the current registry or from its parent registries.
    public final func resolve<Service>(_ type: Service.Type = Service.self, name: String? = nil, args: Any? = nil) -> Service {
        if let registration = lookup(type, name: name),
            let service = registration.scope.resolve(resolver: self, registration: registration, args: args) {
            return service
        }
        fatalError("RESOLVER: '\(Service.self):\(name ?? "")' not resolved")
    }

    /// Static function calls the root registry to resolve an optional Service type.
    static func optional<Service>(_ type: Service.Type = Service.self, name: String? = nil, args: Any? = nil) -> Service? {
        return root.optional(type, name: name, args: args)
    }

    /// Resolves and returns an optional instance of the given Service type from the current registry or from its parent registries.
    public final func optional<Service>(_ type: Service.Type = Service.self, name: String? = nil, args: Any? = nil) -> Service? {
        if let registration = lookup(type, name: name),
            let service = registration.scope.resolve(resolver: self, registration: registration, args: args) {
            return service
        }
        return nil
    }

    // MARK: - Internal

    /// Lookup searches the current and parent registries for a ResolverRegistration<Service> that matches the supplied type and name.
    private final func lookup<Service>(_ type: Service.Type, name: String?) -> ResolverRegistration<Service>? {
        if Resolver.registrationsNeeded {
            registerServices()
        }
        if let registration = registrations[ObjectIdentifier(Service.self).hashValue] as? ResolverRegistration<Service> {
            if let name = name {
                if let registration = registration.namedRegistrations?[name] as? ResolverRegistration<Service> {
                    return registration
                }
            } else {
                return registration
            }
        }
        if let parent = parent, let registration = parent.lookup(type, name: name) {
            return registration
        }
        return nil
    }

    private let parent: Resolver?
    private var registrations = [Int : Any]()
    private static var registrationsNeeded = true
}

// Registration Internals

public typealias ResolverFactory<Service> = () -> Service?
public typealias ResolverFactoryArguments<Service> = (_ resolver: Resolver, _ args: Any?) -> Service?
public typealias ResolverFactoryMutator<Service> = (_ resolver: Resolver, _ service: Service) -> Void
public typealias ResolverFactoryMutatorArguments<Service> = (_ resolver: Resolver, _ args: Any?, _ service: Service) -> Void

/// A ResolverOptions instance is returned by a registration function in order to allow additonal configuratiom. (e.g. scopes, etc.)
public class ResolverOptions<Service> {

    // MARK: - Parameters

    var scope: ResolverScope

    fileprivate var factory: ResolverFactoryArguments<Service>
    fileprivate var mutator: ResolverFactoryMutatorArguments<Service>?
    fileprivate weak var resolver: Resolver?

    // MARK: - Lifecycle

    public init(resolver: Resolver, factory: @escaping ResolverFactoryArguments<Service>) {
        self.factory = factory
        self.resolver = resolver
        self.scope = Resolver.defaultScope
    }

    // MARK: - Fuctionality

    @discardableResult
    public final func implements<Protocol>(_ type: Protocol.Type, name: String? = nil) -> ResolverOptions<Service> {
        resolver?.register(type.self, name: name) { r,_ in r.resolve(Service.self) as? Protocol }
        return self
    }

    @discardableResult
    public final func resolveProperties(_ block: @escaping ResolverFactoryMutator<Service>) -> ResolverOptions<Service> {
        mutator = { r,_,s in block(r, s) }
        return self
    }

    @discardableResult
    public final func resolveProperties(_ block: @escaping ResolverFactoryMutatorArguments<Service>) -> ResolverOptions<Service> {
        mutator = block
        return self
    }

    @discardableResult
    public final func scope(_ scope: ResolverScope) -> ResolverOptions<Service> {
        self.scope = scope
        return self
    }

}

/// ResolverRegistration stores a service definition and its
public final class ResolverRegistration<Service>: ResolverOptions<Service> {

    // MARK: Parameters

    public var key: Int
    public var namedRegistrations: [String : Any]?

    // MARK: Lifecycle

    public init(resolver: Resolver, key: Int, factory: @escaping ResolverFactoryArguments<Service>) {
        self.key = key
        super.init(resolver: resolver, factory: factory)
    }

    // MARK: Functions

    public final func addRegistration(_ name: String, registration: Any) {
        if namedRegistrations == nil {
            namedRegistrations = [name:registration]
        } else {
            namedRegistrations?[name] = registration
        }
    }

    public final func resolve(resolver: Resolver, args: Any?) -> Service? {
        if let service = factory(resolver, args)  {
            self.mutator?(resolver, args, service)
            return service
        }
        return nil
    }
}

// Scopes

extension Resolver {

    // MARK: - Scopes

    public static let application = ResolverScopeApplication()
    public static let cached = ResolverScopeCache()
    public static let graph = ResolverScopeGraph()
    public static let shared = ResolverScopeShare()
    public static let unique = ResolverScopeUnique()

}

/// Resolver scopes exist to control when resolution occurs and how resolved instances are cached. (If at all.)
public protocol ResolverScope: class {
    func resolve<Service>(resolver: Resolver, registration: ResolverRegistration<Service>, args: Any?) -> Service?
}

/// All application scoped services exist for lifetime of the app. (e.g Singletons)
public class ResolverScopeApplication: ResolverScope {

    public final func resolve<Service>(resolver: Resolver, registration: ResolverRegistration<Service>, args: Any?) -> Service? {
        pthread_mutex_lock(&mutex)
        if let service = cachedServices[registration.key] as? Service {
            pthread_mutex_unlock(&mutex)
            return service
        }
        if let service = registration.resolve(resolver: resolver, args: args) {
            cachedServices[registration.key] = service
            pthread_mutex_unlock(&mutex)
            return service
        }
        pthread_mutex_unlock(&mutex)
        return nil
    }

    fileprivate var cachedServices = [Int : Any](minimumCapacity: 32)
    fileprivate var mutex = pthread_mutex_t()
}

/// Cached services exist for lifetime of the app or until their cache is reset.
public final class ResolverScopeCache: ResolverScopeApplication {

    public final func reset() {
        pthread_mutex_lock(&mutex)
        cachedServices.removeAll()
        pthread_mutex_unlock(&mutex)
    }
}

/// Graph services are initialized once and only once during a given resolution cycle. This is the default scope.
public final class ResolverScopeGraph: ResolverScope {

    public final func resolve<Service>(resolver: Resolver, registration: ResolverRegistration<Service>, args: Any?) -> Service? {
        pthread_mutex_lock(&mutex)
        if let service = graph[registration.key] as? Service {
            pthread_mutex_unlock(&mutex)
            return service
        }
        resolutionDepth = resolutionDepth + 1
        let service = registration.resolve(resolver: resolver, args: args)
        resolutionDepth = resolutionDepth - 1
        if resolutionDepth == 0 {
            graph.removeAll()
        } else {
            graph[registration.key] = service
        }
        pthread_mutex_unlock(&mutex)
        return service
    }

    private var graph = [Int : Any?](minimumCapacity: 32)
    private var resolutionDepth: Int = 0
    private var mutex = pthread_mutex_t()
}

/// Shared services persist while strong references to them exist. They're then deallocated until the next resolve.
public final class ResolverScopeShare: ResolverScope {

    public final func resolve<Service>(resolver: Resolver, registration: ResolverRegistration<Service>, args: Any?) -> Service? {
        pthread_mutex_lock(&mutex)
        if let service = cachedServices[registration.key]?.service as? Service {
            pthread_mutex_unlock(&mutex)
            return service
        }
        if let service = registration.resolve(resolver: resolver, args: args) {
            if type(of:service) is AnyClass {
                cachedServices[registration.key] = BoxWeak(service: service as AnyObject)
            } else {
                fatalError("RESOLVER: '\(registration.key)' not a class/reference type")
            }
            pthread_mutex_unlock(&mutex)
            return service
        }
        pthread_mutex_unlock(&mutex)
        return nil
    }

    struct BoxWeak {
        weak var service: AnyObject?
    }

    private var cachedServices = [Int : BoxWeak](minimumCapacity: 32)
    private var mutex = pthread_mutex_t()
}

/// Unique services are created and initialized each and every time they're resolved.
public final class ResolverScopeUnique: ResolverScope {

    public final func resolve<Service>(resolver: Resolver, registration: ResolverRegistration<Service>, args: Any?) -> Service? {
        return registration.resolve(resolver: resolver, args: args)
    }

}
