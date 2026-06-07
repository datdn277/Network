import Foundation

public protocol RequestBehavior {
    func prepare(_ request: URLRequest) -> URLRequest
    func modify(request: URLRequest, response: DataResponse) -> DataResponse
}

public protocol ResponseBehavior {
    func read(_ request: any NetworkRequest) -> DataResponse?
    func write(request: any NetworkRequest, response: DataResponse)
}

public protocol UploadNetworkRequest: NetworkRequest {
    var files: [FileUpload] { get set }
    var parameters: [String: Any]? { get }
}
