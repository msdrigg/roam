import Foundation

public struct NSExceptionError: Swift.Error, Sendable {
    public let exception: String
    public let stackTrace: String

    public init(exception: NSException) {
        self.exception = exception.description
        self.stackTrace = exception.callStackSymbols.joined(separator: "\n")
    }
}

public func catchObjc<T>(_ workItem: () -> T) throws -> T {
    var result: T?
    let exception = ExecuteWithObjCExceptionHandling {
         result = workItem()
    }
    if let exception = exception {
        throw NSExceptionError(exception: exception)
    }
    return result!
}

public func catchObjc<T>(_ workItem: () throws -> T ) throws -> T {
    var result: T?
    var regularError: (any Error)?
    let exception = ExecuteWithObjCExceptionHandling {
        do {
            result = try workItem()
        } catch {
            regularError = error
        }
    }
    if let error = regularError {
        throw error
    }

    if let exception = exception {
        throw NSExceptionError(exception: exception)
    }
    return result!
}
