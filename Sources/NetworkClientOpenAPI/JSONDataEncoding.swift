import Foundation

public struct JSONDataEncoding {
    public static let jsonDataKey = "jsonData"

    public init() {}

    public func encode(_ urlRequest: URLRequest, with parameters: [String: Any]?) -> URLRequest {
        var urlRequest = urlRequest

        guard let jsonData = parameters?[Self.jsonDataKey] as? Data, !jsonData.isEmpty else {
            return urlRequest
        }

        if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        urlRequest.httpBody = jsonData
        return urlRequest
    }

    public static func encodingParameters(jsonData: Data?) -> [String: Any]? {
        guard let jsonData, !jsonData.isEmpty else { return nil }
        return [jsonDataKey: jsonData]
    }
}
