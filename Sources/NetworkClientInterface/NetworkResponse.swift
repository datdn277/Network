public protocol NetworkResponse: Decodable, Encodable {
    var isSucces: Bool { get }
    var errorCode: String { get }
    var statusCode: String { get }
    var messageCode: String { get }
}

public extension NetworkResponse {
    var isSuccess: Bool { isSucces }
}

public protocol CorrectlySpelledNetworkResponse: NetworkResponse {
    var isSuccess: Bool { get }
}

public extension CorrectlySpelledNetworkResponse {
    var isSucces: Bool { isSuccess }
}
