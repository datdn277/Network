import Foundation

public enum NetworkIOError: Error {
    case networkError((any Error)?)
    case invalidURL
    case dataError
    case serverError((any Error)?)
    case httpError(Int)
    case serviceError(errorCode: String, statusCode: String = "", messsageCode: String, json: String?)
}

public extension NetworkIOError {
    var statusCode: Int? {
        switch self {
        case .httpError(let statusCode):
            return statusCode
        case .serviceError(_, let statusCode, _, _):
            return Int(statusCode)
        default:
            return nil
        }
    }

    var isUnauthorized: Bool {
        statusCode == 401
    }
}
