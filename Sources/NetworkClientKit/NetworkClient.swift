import Alamofire
import Foundation
import NetworkClientInterface

public typealias SessionBuilder = (any NetworkAuthManager) -> Alamofire.Session

public class NetworkClient: NetworkClientInterface.Network {
    public var sessionManager: Alamofire.Session
    public var sessionBuilder: SessionBuilder?
    public var shouldHandelStatusCode: Bool

    public var shouldHandleStatusCode: Bool {
        get { shouldHandelStatusCode }
        set { shouldHandelStatusCode = newValue }
    }

    public let baseURL: String
    public var requestBehaviors: [any RequestBehavior]
    public var responseBehavior: (any ResponseBehavior)?
    public var jsonDecoder: JSONDecoder
    public var jsonEncoder: JSONEncoder

    private var authManager: (any NetworkAuthManager)?
    private var requestInterceptor: (any RequestInterceptor)?
    private let refreshCoordinator = TokenRefreshCoordinator()

    public init(
        sessionManager: Alamofire.Session = Alamofire.Session.default,
        baseURL: String,
        requestBehaviors: [any RequestBehavior] = [],
        responseBehavior: (any ResponseBehavior)? = nil,
        sessionBuilder: SessionBuilder? = nil,
        shouldHandelStatusCode: Bool = true
    ) {
        self.sessionManager = sessionManager
        self.baseURL = baseURL
        self.requestBehaviors = requestBehaviors
        self.responseBehavior = responseBehavior
        self.sessionBuilder = sessionBuilder
        self.shouldHandelStatusCode = shouldHandelStatusCode
        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder()
    }

    public func updateAuthManager(_ authManager: any NetworkAuthManager) {
        self.authManager = authManager

        let adapter = NetworkRequestAdapter(authManager: authManager)
        let retrier = NetworkRequestRetrier(authManager: authManager, refreshCoordinator: refreshCoordinator)
        requestInterceptor = Interceptor(adapter: adapter, retrier: retrier)

        if let sessionBuilder {
            sessionManager = sessionBuilder(authManager)
        }
    }

    public func getData(
        request: any NetworkRequest,
        completion: @escaping (Result<String, NetworkIOError>) -> Void
    ) {
        guard let urlRequest = request.request(baseURL) else {
            completion(.failure(.invalidURL))
            return
        }

        let preparedRequest = prepare(urlRequest)
        let cachePolicy = request.resolvedCachePolicy

        if let cachedResult = readCachedResponse(for: request, urlRequest: preparedRequest, policy: cachePolicy) {
            completion(cachedResult)
            return
        }

        if case .cacheOnly = cachePolicy {
            completion(.failure(.dataError))
            return
        }

        let sessionRequest = requestForSession(preparedRequest)
        sessionManager
            .request(sessionRequest, interceptor: requestInterceptor)
            .validate { _, response, _ in
                Self.validateUnauthorizedStatus(response)
            }
            .responseString { [weak self] response in
                guard let self else { return }
                self.process(request: request, urlRequest: sessionRequest, result: response, completion: completion)
            }
    }

    public func getData<Response>(
        request: any NetworkRequest,
        completion: @escaping (Result<Response, NetworkIOError>) -> Void
    ) where Response: NetworkResponse {
        getData(request: request) { [weak self] result in
            guard let self else { return }
            completion(result.flatMap { self.parseData(request: request, json: $0) })
        }
    }

    public func getData(request: any NetworkRequest) async -> Result<String, NetworkIOError> {
        await withCheckedContinuation { continuation in
            getData(request: request) { result in
                continuation.resume(returning: result)
            }
        }
    }

    public func process(
        request: any NetworkRequest,
        urlRequest: URLRequest,
        result: Alamofire.AFDataResponse<String>,
        completion: @escaping (Result<String, NetworkIOError>) -> Void
    ) {
        completion(process(request: request, urlRequest: urlRequest, result: result))
    }

    public func process(
        request: any NetworkRequest,
        urlRequest: URLRequest,
        result: Alamofire.AFDataResponse<String>
    ) -> Result<String, NetworkIOError> {
        let initialResponse = NetworkClientInterface.DataResponse(
            statusCode: result.response?.statusCode,
            data: result.data,
            request: result.request ?? urlRequest,
            response: result.response
        )
        let modifiedResponse = modify(urlRequest: urlRequest, response: initialResponse)

        if shouldHandelStatusCode, let statusCode = modifiedResponse.statusCode {
            if statusCode == 401 {
                authManager?.sessionExpired(statusCode)
                return .failure(.httpError(statusCode))
            }

            guard (200...299).contains(statusCode) else {
                return .failure(.httpError(statusCode))
            }
        }

        if let error = result.error {
            return .failure(.networkError(error))
        }

        guard let json = responseString(from: modifiedResponse, fallback: result.value) else {
            return .failure(.dataError)
        }

        writeCachedResponseIfNeeded(request: request, response: modifiedResponse)
        return .success(json)
    }

    public func parseData<Response>(
        request: any NetworkRequest,
        json: String
    ) -> Result<Response, NetworkIOError> where Response: NetworkResponse {
        guard let data = json.data(using: .utf8) else {
            return .failure(.dataError)
        }

        do {
            let response = try jsonDecoder.decode(Response.self, from: data)
            guard response.isSucces else {
                return .failure(.serviceError(
                    errorCode: response.errorCode,
                    statusCode: response.statusCode,
                    messsageCode: response.messageCode,
                    json: json
                ))
            }
            return .success(response)
        } catch {
            return .failure(.dataError)
        }
    }

    public func upload<Response>(
        request: any UploadNetworkRequest,
        completion: @escaping (Result<Response, NetworkIOError>) -> Void
    ) where Response: NetworkResponse {
        upload(request: request) { [weak self] result in
            guard let self else { return }
            completion(result.flatMap { self.parseData(request: request, json: $0) })
        }
    }

    public func upload(
        request: any UploadNetworkRequest,
        completion: @escaping (Result<String, NetworkIOError>) -> Void
    ) {
        guard let urlRequest = request.request(baseURL) else {
            completion(.failure(.invalidURL))
            return
        }

        let preparedRequest = prepare(urlRequest)
        let sessionRequest = requestForSession(preparedRequest)
        sessionManager
            .upload(
                multipartFormData: { [weak self] formData in
                    self?.appendParameters(request.parameters, to: formData)
                    self?.appendFiles(request.files, to: formData)
                },
                with: sessionRequest,
                interceptor: requestInterceptor
            )
            .validate { _, response, _ in
                Self.validateUnauthorizedStatus(response)
            }
            .responseString { [weak self] response in
                guard let self else { return }
                self.process(request: request, urlRequest: sessionRequest, result: response, completion: completion)
            }
    }

    public func upload(request: any UploadNetworkRequest) async -> Result<String, NetworkIOError> {
        await withCheckedContinuation { continuation in
            upload(request: request) { result in
                continuation.resume(returning: result)
            }
        }
    }

    public func download(
        request: any NetworkRequest,
        config: DownloadConfig,
        completion: @escaping (Result<URL?, NetworkIOError>) -> Void
    ) {
        guard let urlRequest = request.request(baseURL) else {
            completion(.failure(.invalidURL))
            return
        }

        let preparedRequest = prepare(urlRequest)
        let sessionRequest = requestForSession(preparedRequest)
        let destination = downloadDestination(request: request, config: config)

        sessionManager
            .download(sessionRequest, interceptor: requestInterceptor, to: destination)
            .validate { _, response, _ in
                Self.validateUnauthorizedStatus(response)
            }
            .response { [weak self] response in
                guard let self else { return }

                if let statusCode = response.response?.statusCode, self.shouldHandelStatusCode {
                    if statusCode == 401 {
                        self.authManager?.sessionExpired(statusCode)
                        completion(.failure(.httpError(statusCode)))
                        return
                    }

                    guard (200...299).contains(statusCode) else {
                        completion(.failure(.httpError(statusCode)))
                        return
                    }
                }

                if let error = response.error {
                    completion(.failure(.networkError(error)))
                    return
                }

                completion(.success(response.fileURL))
            }
    }
}

private extension NetworkClient {
    static func validateUnauthorizedStatus(_ response: HTTPURLResponse) -> Request.ValidationResult {
        if response.statusCode == 401 {
            return .failure(AFError.responseValidationFailed(
                reason: .unacceptableStatusCode(code: response.statusCode)
            ))
        }

        return .success(())
    }

    func prepare(_ urlRequest: URLRequest) -> URLRequest {
        requestBehaviors.reduce(urlRequest) { request, behavior in
            behavior.prepare(request)
        }
    }

    func requestForSession(_ urlRequest: URLRequest) -> URLRequest {
        guard requestInterceptor == nil else {
            return urlRequest
        }

        return removingOpenAPIMarkerHeader(from: urlRequest)
    }

    func removingOpenAPIMarkerHeader(from urlRequest: URLRequest) -> URLRequest {
        var request = urlRequest
        request.setValue(nil, forHTTPHeaderField: "X-NetworkClient-Requires-Authentication")
        return request
    }

    func modify(
        urlRequest: URLRequest,
        response: NetworkClientInterface.DataResponse
    ) -> NetworkClientInterface.DataResponse {
        requestBehaviors.reduce(response) { currentResponse, behavior in
            behavior.modify(request: urlRequest, response: currentResponse)
        }
    }

    func responseString(from response: NetworkClientInterface.DataResponse, fallback: String?) -> String? {
        if let data = response.data {
            return String(data: data, encoding: .utf8)
        }
        return fallback
    }

    func readCachedResponse(
        for request: any NetworkRequest,
        urlRequest: URLRequest,
        policy: NetworkCachePolicy
    ) -> Result<String, NetworkIOError>? {
        guard shouldReadCache(policy: policy), let responseBehavior else {
            return nil
        }

        guard let cachedResponse = responseBehavior.read(request) else {
            return nil
        }

        guard isCacheUsable(cachedResponse, policy: policy) else {
            return nil
        }

        let modifiedResponse = modify(urlRequest: urlRequest, response: cachedResponse)
        guard let string = responseString(from: modifiedResponse, fallback: nil as String?) else {
            return .failure(.dataError)
        }

        return .success(string)
    }

    func shouldReadCache(policy: NetworkCachePolicy) -> Bool {
        switch policy {
        case .cacheElseLoad, .cacheOnly, .maxAge:
            return true
        case .disabled, .reloadIgnoringCache:
            return false
        }
    }

    func isCacheUsable(_ response: NetworkClientInterface.DataResponse, policy: NetworkCachePolicy) -> Bool {
        guard let statusCode = response.statusCode, (200...299).contains(statusCode) else {
            return false
        }

        if case .maxAge(let maxAge) = policy {
            return Date().timeIntervalSince(response.createdAt) <= maxAge
        }

        return true
    }

    func writeCachedResponseIfNeeded(request: any NetworkRequest, response: NetworkClientInterface.DataResponse) {
        guard shouldWriteCache(for: request, response: response), let responseBehavior else {
            return
        }

        responseBehavior.write(request: request, response: response)
    }

    func shouldWriteCache(for request: any NetworkRequest, response: NetworkClientInterface.DataResponse) -> Bool {
        guard let statusCode = response.statusCode, (200...299).contains(statusCode) else {
            return false
        }

        switch request.resolvedCachePolicy {
        case .disabled, .cacheOnly:
            return false
        case .cacheElseLoad, .reloadIgnoringCache, .maxAge:
            return true
        }
    }

    func appendParameters(_ parameters: [String: Any]?, to formData: MultipartFormData) {
        guard let parameters else { return }

        for key in parameters.keys.sorted() {
            guard let value = parameters[key] else { continue }
            appendParameter(value, named: key, to: formData)
        }
    }

    func appendParameter(_ value: Any, named name: String, to formData: MultipartFormData) {
        if let data = value as? Data {
            formData.append(data, withName: name)
            return
        }

        if let string = value as? String {
            formData.append(Data(string.utf8), withName: name)
            return
        }

        if let number = value as? NSNumber {
            formData.append(Data(number.stringValue.utf8), withName: name)
            return
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value) {
            formData.append(data, withName: name)
            return
        }

        formData.append(Data(String(describing: value).utf8), withName: name)
    }

    func appendFiles(_ files: [FileUpload], to formData: MultipartFormData) {
        for file in files {
            formData.append(
                uploadURL(for: file),
                withName: file.withName,
                fileName: file.fileName,
                mimeType: file.mimeType
            )
        }
    }

    func uploadURL(for file: FileUpload) -> URL {
        if !file.path.isEmpty {
            return URL(fileURLWithPath: file.path)
        }
        return file.url
    }

    func downloadDestination(
        request: any NetworkRequest,
        config: DownloadConfig
    ) -> DownloadRequest.Destination {
        let options = alamofireDownloadOptions(from: config.options)
        return { temporaryURL, response in
            let directoryURL = FileManager.default.urls(for: config.directory, in: config.domain).first
                ?? temporaryURL.deletingLastPathComponent()
            let filename = response.suggestedFilename
                ?? URL(fileURLWithPath: request.path).lastPathComponent.nonEmpty
                ?? request.id.nonEmpty
                ?? UUID().uuidString
            return (directoryURL.appendingPathComponent(filename), options)
        }
    }

    func alamofireDownloadOptions(from options: [DownloadOption]) -> DownloadRequest.Options {
        var alamofireOptions: DownloadRequest.Options = []
        for option in options {
            switch option {
            case .createIntermediateDirectories:
                alamofireOptions.insert(.createIntermediateDirectories)
            case .removePreviousFile:
                alamofireOptions.insert(.removePreviousFile)
            }
        }
        return alamofireOptions
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
