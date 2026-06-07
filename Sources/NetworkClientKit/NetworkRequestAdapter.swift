import Alamofire
import Foundation
import NetworkClientInterface

public struct NetworkRequestAdapter: RequestAdapter, @unchecked Sendable {
    private let authManager: any NetworkAuthManager

    public init(authManager: any NetworkAuthManager) {
        self.authManager = authManager
    }

    public func adapt(_ urlRequest: URLRequest) throws -> URLRequest {
        var adaptedRequest = urlRequest

        let requiresAuthenticationHeader = "X-NetworkClient-Requires-Authentication"
        let requiresAuthentication = adaptedRequest.value(forHTTPHeaderField: requiresAuthenticationHeader)
        adaptedRequest.setValue(nil, forHTTPHeaderField: requiresAuthenticationHeader)

        if requiresAuthentication == "false" {
            return adaptedRequest
        }

        if let accessToken = authManager.accessToken, !accessToken.isEmpty {
            adaptedRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return adaptedRequest
    }

    public func adapt(
        _ urlRequest: URLRequest,
        for session: Alamofire.Session,
        completion: @escaping (Result<URLRequest, any Error>) -> Void
    ) {
        completion(Result { try adapt(urlRequest) })
    }

    public func adapt(
        _ urlRequest: URLRequest,
        using state: Alamofire.RequestAdapterState,
        completion: @escaping (Result<URLRequest, any Error>) -> Void
    ) {
        completion(Result { try adapt(urlRequest) })
    }
}
