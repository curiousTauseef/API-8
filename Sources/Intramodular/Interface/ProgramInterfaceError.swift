//
// Copyright (c) Vatsal Manot
//

import Swift

public protocol ProgramInterfaceError: Error {
    associatedtype Interface: ProgramInterface
    
    init(_: Interface.Request.Error)
    init(runtimeError: Error)
}

public enum DefaultProgramInterfaceError<Interface: ProgramInterface>: ProgramInterfaceError {
    case badRequest(Interface.Request.Error)
    case runtime(Error)
    
    public init(_ error: Interface.Request.Error) {
        self = .badRequest(error)
    }
    
    public init(runtimeError: Error) {
        self = .runtime(runtimeError)
    }
}
