import Foundation

final public class DataResponse: CustomStringConvertible, CustomDebugStringConvertible, Equatable {
    /// The status code of the response.
    public let statusCode: Int?

    /// The response data.
    public let data: Data?

    /// The original URLRequest for the response.
    public let request: URLRequest?

    /// The HTTPURLResponse object.
    public let response: HTTPURLResponse?

    /// Time the response object was created or restored from cache.
    public let createdAt: Date

    public init(
        statusCode: Int?,
        data: Data?,
        request: URLRequest? = nil,
        response: HTTPURLResponse? = nil,
        createdAt: Date = Date()
    ) {
        self.statusCode = statusCode
        self.data = data
        self.request = request
        self.response = response
        self.createdAt = createdAt
    }

    /// A text description of the `Response`.
    public var description: String {
        let status = statusCode.map(String.init) ?? "nil"
        let dataLength = data?.count ?? 0
        return "DataResponse(statusCode: \(status), dataLength: \(dataLength))"
    }

    /// A text description of the `Response`. Suitable for debugging.
    public var debugDescription: String {
        let requestDescription = request.map(Self.describeRequest) ?? "nil"
        let responseDescription = response.map(Self.describeResponse) ?? "nil"
        return "\(description), request: \(requestDescription), response: \(responseDescription), createdAt: \(createdAt)"
    }

    public static func == (lhs: DataResponse, rhs: DataResponse) -> Bool {
        lhs.statusCode == rhs.statusCode &&
            lhs.data == rhs.data &&
            Self.describeRequest(lhs.request) == Self.describeRequest(rhs.request) &&
            Self.describeResponse(lhs.response) == Self.describeResponse(rhs.response)
    }

    private static func describeRequest(_ request: URLRequest?) -> String {
        guard let request else { return "nil" }
        let method = request.httpMethod ?? "nil"
        let url = request.url?.absoluteString ?? "nil"
        let body = request.httpBody?.base64EncodedString() ?? "nil"
        let headers = request.allHTTPHeaderFields ?? [:]
        return "\(method) \(url) headers: \(headers) body: \(body)"
    }

    private static func describeResponse(_ response: HTTPURLResponse?) -> String {
        guard let response else { return "nil" }
        let url = response.url?.absoluteString ?? "nil"
        return "\(response.statusCode) \(url) headers: \(response.allHeaderFields)"
    }
}
