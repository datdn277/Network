import Foundation
import NetworkClientInterface

public enum NetworkClientOpenAPIHeader {
    public static let requiresAuthentication = "X-NetworkClient-Requires-Authentication"
}

public struct RequestBuilder<T>: UploadNetworkRequest {
    public var files: [FileUpload]
    public var path: String
    public var cache: Bool
    public var body: String
    public var bodyData: Data?
    public var id: String
    public var data: String?
    public var recall: Bool

    public let parameters: [String: Any]?
    public let method: String
    public let headers: [String: String]
    public let requiresAuthentication: Bool
    public var onProgressReady: ((Progress) -> Void)?

    public init(
        method: String,
        path: String,
        files: [FileUpload] = [],
        parameters: [String: Any]?,
        headers: [String: String] = [:],
        requiresAuthentication: Bool
    ) {
        self.files = files
        self.method = method
        self.path = path
        self.cache = false
        self.body = ""
        self.bodyData = parameters?[JSONDataEncoding.jsonDataKey] as? Data
        self.id = OpenAPIClientAPI.requestID.isEmpty ? "\(method.uppercased()) \(path)" : OpenAPIClientAPI.requestID
        self.data = nil
        self.recall = false
        self.parameters = parameters
        self.headers = headers
        self.requiresAuthentication = requiresAuthentication
    }

    public func request(_ baseUrl: String) -> URLRequest? {
        guard let url = requestURL(baseUrl: baseUrl) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue(requiresAuthentication.description, forHTTPHeaderField: NetworkClientOpenAPIHeader.requiresAuthentication)
        request = JSONDataEncoding().encode(request, with: parameters)

        if request.httpBody == nil, let bodyData {
            request.httpBody = bodyData
        }

        if request.httpBody == nil, !body.isEmpty {
            request.httpBody = Data(body.utf8)
        }

        return request
    }

    public func addHeader(name: String, value: String) -> RequestBuilder<T> {
        guard !value.isEmpty else { return self }

        var headers = self.headers
        headers[name] = value
        return RequestBuilder(
            method: method,
            path: path,
            files: files,
            parameters: parameters,
            headers: headers,
            requiresAuthentication: requiresAuthentication
        )
    }

    public func addCredential() -> RequestBuilder<T> {
        RequestBuilder(
            method: method,
            path: path,
            files: files,
            parameters: parameters,
            headers: headers,
            requiresAuthentication: true
        )
    }

    private func requestURL(baseUrl: String) -> URL? {
        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            return absoluteURL
        }

        return URL(string: baseUrl.trimmedTrailingSlash + "/" + path.trimmedLeadingSlash)
    }
}

private extension String {
    var trimmedLeadingSlash: String {
        var value = self
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        return value
    }

    var trimmedTrailingSlash: String {
        var value = self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
