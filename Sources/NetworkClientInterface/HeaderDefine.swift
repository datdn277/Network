public protocol HeaderDefine {
    var contentType: String { get }
    var xForwardedFor: String { get }
    var channel: String { get }
    var xClientID: String { get }
    var clientID: String { get }
    var acceptLanguage: String { get }
}
