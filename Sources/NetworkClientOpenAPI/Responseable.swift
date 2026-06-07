import Foundation
import NetworkClientInterface

public protocol Responseable: NetworkResponse {}

public extension Responseable {
    var isSucces: Bool { true }
    var isSuccess: Bool { true }
    var statusCode: String { "" }
    var errorCode: String { "" }
    var messageCode: String { "" }

    func getData<T>() -> T? {
        self as? T
    }
}
