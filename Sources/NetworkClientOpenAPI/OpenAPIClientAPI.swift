import Foundation

open class OpenAPIClientAPI {
    public static var basePath = ""
    public static var customHeaders: [String: String] = [:]
    public static var requestID = ""
    public static var pathExtensions: [String: String] = [:]

    public static func pathExtension(_ value: String) -> String {
        pathExtensions[value] ?? ""
    }
}
