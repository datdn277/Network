import Alamofire
import Foundation
import NetworkClientKit
import NetworkClientInterface
import NetworkClientOpenAPI
import XCTest

final class NetworkClientOpenAPITests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testRequestBuilderBuildsNetworkClientRequest() throws {
        let body = AccountDetailCriteriaDto(accountNo: "123456")
        let request = RequestBuilder<AccountDetailResponse>(
            method: "POST",
            path: "/masterdata/user/pmt-account/detail-to-cif/1.0",
            parameters: JSONEncodingHelper.encodingParameters(forEncodableObject: body),
            headers: ["Content-Type": "application/json"],
            requiresAuthentication: false
        )

        let urlRequest = try XCTUnwrap(request.request("https://api.example.com"))

        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.example.com/masterdata/user/pmt-account/detail-to-cif/1.0")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: NetworkClientOpenAPIHeader.requiresAuthentication), "false")

        let bodyData = try XCTUnwrap(urlRequest.httpBody)
        let bodyObject = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(bodyObject?["accountNo"] as? String, "123456")
    }

    func testRequestBuilderCanBeExecutedByNetworkClient() async throws {
        let network = NetworkClient(sessionManager: makeSession(), baseURL: "https://api.example.com")
        let body = AccountDetailCriteriaDto(accountNo: "123456")
        let request = RequestBuilder<AccountDetailResponse>(
            method: "POST",
            path: "/masterdata/user/pmt-account/detail-to-cif/1.0",
            parameters: JSONEncodingHelper.encodingParameters(forEncodableObject: body),
            headers: ["Content-Type": "application/json"],
            requiresAuthentication: false
        )

        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/masterdata/user/pmt-account/detail-to-cif/1.0")
            XCTAssertNil(request.value(forHTTPHeaderField: NetworkClientOpenAPIHeader.requiresAuthentication))

            let body = try XCTUnwrap(bodyData(from: request))
            let bodyObject = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(bodyObject?["accountNo"] as? String, "123456")

            return StubResponse(
                statusCode: 200,
                body: """
                {
                  "status": 200,
                  "code": "OK",
                  "message": "Success",
                  "data": {
                    "accountNo": "123456",
                    "accountName": "Main Account",
                    "availableBalance": 123.45
                  }
                }
                """
            )
        }

        let result: Result<AccountDetailResponse, NetworkIOError> = await network.getData(request: request)
        let response = try result.get()

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.data?.accountNo, "123456")
        XCTAssertEqual(response.data?.accountName, "Main Account")
    }
}

private struct AccountDetailCriteriaDto: Codable {
    let accountNo: String
}

private struct AccountDetailResponse: Responseable {
    let status: Int?
    let code: String?
    let message: String?
    let data: AccountDetailDto?
}

private struct AccountDetailDto: Codable {
    let accountNo: String?
    let accountName: String?
    let availableBalance: Decimal?
}

private func makeSession() -> Alamofire.Session {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return Alamofire.Session(configuration: configuration)
}

private func bodyData(from request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read > 0 {
            data.append(buffer, count: read)
        } else {
            break
        }
    }

    return data
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
