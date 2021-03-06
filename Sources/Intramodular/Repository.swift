//
// Copyright (c) Vatsal Manot
//

import Merge
import Swallow
import Task

/// A data repository.
///
/// The combination of a program interface and a compatible request session.
public protocol Repository: ObservableObject {
    associatedtype Interface: ProgramInterface
    associatedtype Session: RequestSession where Session.Request == Interface.Request
    
    typealias Schema = Interface.Schema
    
    var interface: Interface { get }
    var session: Session { get }
}

extension Repository {
    public func task<E: Endpoint>(
        for endpoint: E
    ) -> AnyParametrizedTask<E.Input, E.Output, Interface.Error> where E.Root == Interface {
        return ParametrizedPassthroughTask(body: { (task: ParametrizedPassthroughTask) in
            guard let input = task.input else {
                task.send(.error(.missingInput()))
                
                return .empty()
            }
            
            let endpoint = endpoint
            
            do {
                return try self
                    .session
                    .task(with: endpoint.buildRequest(
                        for: self.interface,
                        from: input
                    ))
                    .success()
                    .sinkResult({ [weak task] result in
                        switch result {
                            case .success(let value): do {
                                do {
                                    task?.send(.success(try endpoint.decodeOutput(from: value)))
                                } catch {
                                    task?.send(.error(.init(runtimeError: error)))
                                }
                            }
                            case .failure(let error): do {
                                task?.send(.error(.init(runtimeError: error)))
                            }
                        }
                    })
            } catch {
                task.send(.error(.init(runtimeError: error)))
                
                return AnyCancellable.empty()
            }
        })
        .eraseToAnyTask()
    }
    
    public func task<E: Endpoint>(
        for endpoint: KeyPath<Interface, E>
    ) -> AnyParametrizedTask<E.Input, E.Output, Interface.Error> where E.Root == Interface {
        task(for: interface[keyPath: endpoint])
    }
    
    public func run<E: Endpoint>(
        _ endpoint: E,
        with input: E.Input
    ) -> AnyTask<E.Output, Interface.Error> where E.Root == Interface {
        let result = task(for: endpoint)
        
        do {
            try result.receive(input)
        } catch {
            return .failure(.init(runtimeError: error))
        }
        
        result.start()
        
        session.cancellables.insert(result)
        
        return result.eraseToAnyTask()
    }
    
    public func run<E: Endpoint>(
        _ endpoint: KeyPath<Interface, E>,
        with input: E.Input
    ) -> AnyTask<E.Output, Interface.Error> where E.Root == Interface {
        run(interface[keyPath: endpoint], with: input)
    }
    
    public func run<E: Endpoint>(
        _ endpoint: KeyPath<Interface.Endpoints.Type, E>,
        with input: E.Input
    ) -> AnyTask<E.Output, Interface.Error> where E.Root == Interface {
        run(Interface.Endpoints.self[keyPath: endpoint], with: input)
    }
}

// MARK: - Auxiliary Implementation -

open class RepositoryBase<Interface: ProgramInterface, Session: RequestSession>: Repository where Interface.Request == Session.Request {
    public let cancellables = Cancellables()
    
    @Published public var interface: Interface {
        didSet {
            session.cancellables.cancel()
        }
    }
    
    @Published public var session: Session {
        didSet {
            session.cancellables.cancel()
        }
    }
    
    public init(interface: Interface, session: Session) {
        self.interface = interface
        self.session = session
    }
}

extension RepositoryBase where Session: Initiable {
    public convenience init(interface: Interface) {
        self.init(interface: interface, session: .init())
    }
}

extension RepositoryBase where Interface: Initiable {
    public convenience init(session: Session) {
        self.init(interface: .init(), session: session)
    }
}

extension RepositoryBase where Interface: Initiable, Session: Initiable {
    public convenience init() {
        self.init(interface: .init(), session: .init())
    }
}

private enum _DefaultRepositoryError: Error {
    case missingInput
    case invalidInput
    case invalidOutput
}

private extension ProgramInterfaceError {
    static func missingInput() -> Self {
        .init(runtimeError: _DefaultRepositoryError.missingInput)
    }
    
    static func invalidInput() -> Self {
        .init(runtimeError: _DefaultRepositoryError.invalidInput)
    }
    
    static func invalidOutput() -> Self {
        .init(runtimeError: _DefaultRepositoryError.invalidOutput)
    }
}
