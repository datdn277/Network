import Alamofire
import Foundation
import XCTest
@testable import NetworkClientKit
@testable import NetworkClientInterface

final class NetworkClientKitTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testGetDataReturnsRawStringAndReadsCachedSecondCall() async throws {
        let cache = MemoryResponseBehavior()
        let network = NetworkClient(
            sessionManager: makeSession(),
            baseURL: "https://example.com",
            responseBehavior: cache
        )
        let request = TestRequest(cache: true, path: "/profile", id: "profile")
        var hitCount = 0

        StubURLProtocol.handler = { _ in
            hitCount += 1
            return StubResponse(statusCode: 200, body: #"{"value":"network"}"#)
        }

        let first = await network.getData(request: request)
        let second = await network.getData(request: request)

        XCTAssertEqual(try first.get(), #"{"value":"network"}"#)
        XCTAssertEqual(try second.get(), #"{"value":"network"}"#)
        XCTAssertEqual(hitCount, 1)
        XCTAssertNotNil(cache.read(request))
    }

    func testCacheOnlyStoresHTTP2xx() async {
        let cache = MemoryResponseBehavior()
        let network = NetworkClient(
            sessionManager: makeSession(),
            baseURL: "https://example.com",
            responseBehavior: cache
        )
        let request = TestRequest(cache: true, path: "/error", id: "error")

        StubURLProtocol.handler = { _ in
            StubResponse(statusCode: 500, body: #"{"error":true}"#)
        }

        let result = await network.getData(request: request)

        guard case .failure(.httpError(500)) = result else {
            XCTFail("Expected httpError(500), got \(result)")
            return
        }
        XCTAssertNil(cache.read(request))
    }

    func testParseDataReturnsServiceErrorWhenResponseIsNotSuccessful() {
        let network = NetworkClient(baseURL: "https://example.com")
        let request = TestRequest(path: "/service-error", id: "service-error")

        let success: Result<TestResponse, NetworkIOError> = network.parseData(
            request: request,
            json: #"{"isSuccess":true,"errorCode":"","statusCode":"0","messageCode":""}"#
        )
        XCTAssertTrue(try success.get().isSuccess)

        let failure: Result<TestResponse, NetworkIOError> = network.parseData(
            request: request,
            json: #"{"isSuccess":false,"errorCode":"E001","statusCode":"BUSINESS","messageCode":"M001"}"#
        )

        guard case .failure(.serviceError(let errorCode, let statusCode, let messageCode, _)) = failure else {
            XCTFail("Expected serviceError, got \(failure)")
            return
        }
        XCTAssertEqual(errorCode, "E001")
        XCTAssertEqual(statusCode, "BUSINESS")
        XCTAssertEqual(messageCode, "M001")
    }

    func testRequestBehaviorCanPrepareAndModifyResponse() async throws {
        let behavior = HeaderAndResponseBehavior()
        let network = NetworkClient(
            sessionManager: makeSession(),
            baseURL: "https://example.com",
            requestBehaviors: [behavior]
        )
        let request = TestRequest(path: "/behavior", id: "behavior")

        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "prepared")
            return StubResponse(statusCode: 200, body: #"{"value":"original"}"#)
        }

        let result = await network.getData(request: request)

        XCTAssertEqual(try result.get(), #"{"value":"modified"}"#)
    }

    func testUnauthorizedResponseRefreshesTokenAndRetriesOnce() async throws {
        let manager = AuthManagerMock(accessToken: "old")
        let network = NetworkClient(sessionManager: makeSession(), baseURL: "https://example.com")
        network.updateAuthManager(manager)

        let recorder = LockedRecorder<String>()
        var hitCount = 0

        StubURLProtocol.handler = { request in
            hitCount += 1
            recorder.append(request.value(forHTTPHeaderField: "Authorization") ?? "")

            if hitCount == 1 {
                return StubResponse(statusCode: 401, body: #"{"error":"expired"}"#)
            }

            return StubResponse(statusCode: 200, body: #"{"value":"ok"}"#)
        }

        let result = await network.getData(request: TestRequest(path: "/token", id: "token"))

        XCTAssertEqual(try result.get(), #"{"value":"ok"}"#)
        XCTAssertEqual(hitCount, 2)
        XCTAssertEqual(manager.refreshCount, 1)
        XCTAssertEqual(manager.sessionExpiredCount, 0)
        XCTAssertEqual(recorder.values, ["Bearer old", "Bearer new"])
    }

    func testRefreshFailureCallsSessionExpired() async {
        let manager = AuthManagerMock(accessToken: "old")
        manager.refreshSucceeds = false
        let network = NetworkClient(sessionManager: makeSession(), baseURL: "https://example.com")
        network.updateAuthManager(manager)

        StubURLProtocol.handler = { _ in
            StubResponse(statusCode: 401, body: #"{"error":"expired"}"#)
        }

        let result = await network.getData(request: TestRequest(path: "/token", id: "token"))

        guard case .failure(.httpError(401)) = result else {
            XCTFail("Expected httpError(401), got \(result)")
            return
        }
        XCTAssertEqual(manager.refreshCount, 1)
        XCTAssertEqual(manager.sessionExpiredCount, 1)
    }

    func testTokenRefreshCoordinatorCoalescesConcurrentRefreshes() {
        let manager = AuthManagerMock(accessToken: "old")
        manager.autoCompleteRefresh = false
        let coordinator = TokenRefreshCoordinator()
        var completions: [Bool] = []

        coordinator.refreshToken(using: manager) { completions.append($0) }
        coordinator.refreshToken(using: manager) { completions.append($0) }
        coordinator.refreshToken(using: manager) { completions.append($0) }

        XCTAssertEqual(manager.refreshCount, 1)
        XCTAssertTrue(completions.isEmpty)

        manager.finishRefresh(success: true)

        XCTAssertEqual(completions, [true, true, true])
    }

    func testUploadSendsMultipartRequest() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-client-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let network = NetworkClient(sessionManager: makeSession(), baseURL: "https://example.com")
        let request = TestUploadRequest(
            path: "/upload",
            id: "upload",
            files: [
                FileUpload(
                    withName: "file",
                    fileName: "hello.txt",
                    mimeType: "text/plain",
                    path: fileURL.path
                )
            ],
            parameters: ["name": "hello"]
        )

        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
            return StubResponse(statusCode: 200, body: #"{"uploaded":true}"#)
        }

        let result = await network.upload(request: request)

        XCTAssertEqual(try result.get(), #"{"uploaded":true}"#)
    }

    func testDownloadWritesFileAndReturnsURL() async throws {
        let filename = "network-client-\(UUID().uuidString).txt"
        let network = NetworkClient(sessionManager: makeSession(), baseURL: "https://example.com")
        let request = TestRequest(path: "/\(filename)", id: filename)

        StubURLProtocol.handler = { _ in
            StubResponse(statusCode: 200, body: "downloaded")
        }

        let result = await withCheckedContinuation { continuation in
            network.download(request: request, config: DownloadConfig(directory: .cachesDirectory)) { result in
                continuation.resume(returning: result)
            }
        }

        let fileURL = try XCTUnwrap(try result.get())
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(try String(contentsOf: fileURL), "downloaded")
    }

    func testDiskResponseBehaviorPersists2xxResponse() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-client-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let behavior = DiskResponseBehavior(directoryURL: directoryURL)
        let request = TestRequest(cache: true, path: "/cached", id: "cached")
        let response = NetworkClientInterface.DataResponse(
            statusCode: 200,
            data: Data("cached".utf8)
        )

        behavior.write(request: request, response: response)

        XCTAssertEqual(behavior.read(request)?.data, Data("cached".utf8))
    }
}

private func makeSession() -> Alamofire.Session {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return Alamofire.Session(configuration: configuration)
}

private struct StubResponse {
    var statusCode: Int
    var body: Data
    var headers: [String: String]

    init(statusCode: Int, body: String, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = Data(body.utf8)
        self.headers = headers
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> StubResponse)?

    class func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let stub = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct TestRequest: CachePolicyNetworkRequest {
    var cache: Bool
    var path: String
    var id: String
    var method: String
    var body: String
    var cachePolicy: NetworkCachePolicy

    init(
        cache: Bool = false,
        path: String,
        id: String,
        method: String = "GET",
        body: String = "",
        cachePolicy: NetworkCachePolicy? = nil
    ) {
        self.cache = cache
        self.path = path
        self.id = id
        self.method = method
        self.body = body
        self.cachePolicy = cachePolicy ?? (cache ? .cacheElseLoad : .disabled)
    }

    func request(_ baseUrl: String) -> URLRequest? {
        guard let url = URL(string: baseUrl + path) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if !body.isEmpty {
            request.httpBody = Data(body.utf8)
        }
        return request
    }
}

private struct TestUploadRequest: UploadNetworkRequest {
    var cache = false
    var path: String
    var id: String
    var method = "POST"
    var body = ""
    var files: [FileUpload]
    var parameters: [String: Any]?

    func request(_ baseUrl: String) -> URLRequest? {
        guard let url = URL(string: baseUrl + path) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}

private struct TestResponse: CorrectlySpelledNetworkResponse {
    let isSuccess: Bool
    let errorCode: String
    let statusCode: String
    let messageCode: String
}

private final class HeaderAndResponseBehavior: RequestBehavior {
    func prepare(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("prepared", forHTTPHeaderField: "X-Test")
        return request
    }

    func modify(
        request: URLRequest,
        response: NetworkClientInterface.DataResponse
    ) -> NetworkClientInterface.DataResponse {
        NetworkClientInterface.DataResponse(
            statusCode: response.statusCode,
            data: Data(#"{"value":"modified"}"#.utf8),
            request: response.request,
            response: response.response,
            createdAt: response.createdAt
        )
    }
}

private final class AuthManagerMock: NetworkAuthManager {
    private let lock = NSLock()
    private var pendingRefreshCompletion: ((Bool) -> Void)?

    var accessToken: String?
    var refreshTokenExpiryDate: Date?
    var refreshSucceeds = true
    var autoCompleteRefresh = true
    private(set) var refreshCount = 0
    private(set) var canNotRefreshCount = 0
    private(set) var sessionExpiredCount = 0

    init(accessToken: String?, refreshTokenExpiryDate: Date? = Date().addingTimeInterval(3600)) {
        self.accessToken = accessToken
        self.refreshTokenExpiryDate = refreshTokenExpiryDate
    }

    func refreshToken(completion: @escaping (Bool) -> Void) {
        lock.lock()
        refreshCount += 1
        pendingRefreshCompletion = completion
        let shouldAutoComplete = autoCompleteRefresh
        lock.unlock()

        if shouldAutoComplete {
            finishRefresh(success: refreshSucceeds)
        }
    }

    func finishRefresh(success: Bool) {
        lock.lock()
        let completion = pendingRefreshCompletion
        pendingRefreshCompletion = nil
        lock.unlock()

        if success {
            accessToken = "new"
        }
        completion?(success)
    }

    func canNotRefreshToken() {
        lock.lock()
        canNotRefreshCount += 1
        lock.unlock()
    }

    func sessionExpired(_ statusCode: Int) {
        lock.lock()
        sessionExpiredCount += 1
        lock.unlock()
    }
}

private final class LockedRecorder<Value> {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
