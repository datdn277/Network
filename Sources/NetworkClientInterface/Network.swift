import Foundation

public protocol Network: AnyObject {
    func getData(request: any NetworkRequest) async -> Result<String, NetworkIOError>
    func getData(request: any NetworkRequest, completion: @escaping (Result<String, NetworkIOError>) -> Void)
    func getData<Response>(
        request: any NetworkRequest,
        completion: @escaping (Result<Response, NetworkIOError>) -> Void
    ) where Response: NetworkResponse
    func upload<Response>(
        request: any UploadNetworkRequest,
        completion: @escaping (Result<Response, NetworkIOError>) -> Void
    ) where Response: NetworkResponse
    func upload(request: any UploadNetworkRequest, completion: @escaping (Result<String, NetworkIOError>) -> Void)
    func upload(request: any UploadNetworkRequest) async -> Result<String, NetworkIOError>
    func download(
        request: any NetworkRequest,
        config: DownloadConfig,
        completion: @escaping (Result<URL?, NetworkIOError>) -> Void
    )
    func updateAuthManager(_ authManager: any NetworkAuthManager)
}

public extension Network {
    func download(
        request: any NetworkRequest,
        config: DownloadConfig = DownloadConfig(),
        completion: @escaping (Result<URL?, NetworkIOError>) -> Void
    ) {
        download(request: request, config: config, completion: completion)
    }
}

public extension Network {
    func getData(request: any NetworkRequest) -> AsyncStream<Result<String, NetworkIOError>> {
        AsyncStream { continuation in
            getData(request: request) { result in
                continuation.yield(result)
                continuation.finish()
            }
        }
    }

    func getResponseData<Response>(
        request: any NetworkRequest
    ) -> AsyncStream<Result<Response, NetworkIOError>> where Response: NetworkResponse {
        AsyncStream { continuation in
            getData(request: request) { (result: Result<Response, NetworkIOError>) in
                continuation.yield(result)
                continuation.finish()
            }
        }
    }

    func upload<Response>(
        request: any UploadNetworkRequest
    ) -> AsyncStream<Result<Response, NetworkIOError>> where Response: NetworkResponse {
        AsyncStream { continuation in
            upload(request: request) { (result: Result<Response, NetworkIOError>) in
                continuation.yield(result)
                continuation.finish()
            }
        }
    }

    func upload(request: any UploadNetworkRequest) -> AsyncStream<Result<String, NetworkIOError>> {
        AsyncStream { continuation in
            upload(request: request) { result in
                continuation.yield(result)
                continuation.finish()
            }
        }
    }
}

public extension Network {
    func parseData<Response>(
        request: any NetworkRequest,
        json: String
    ) -> Result<Response, NetworkIOError> where Response: NetworkResponse {
        guard let data = json.data(using: .utf8) else {
            return .failure(.dataError)
        }

        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
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

    func getData<Response>(
        request: any NetworkRequest
    ) async -> Result<Response, NetworkIOError> where Response: NetworkResponse {
        await withCheckedContinuation { continuation in
            getData(request: request) { (result: Result<Response, NetworkIOError>) in
                continuation.resume(returning: result)
            }
        }
    }

    func uploadData<Response>(
        request: any UploadNetworkRequest
    ) async -> Result<Response, NetworkIOError> where Response: NetworkResponse {
        await withCheckedContinuation { continuation in
            upload(request: request) { (result: Result<Response, NetworkIOError>) in
                continuation.resume(returning: result)
            }
        }
    }
}
