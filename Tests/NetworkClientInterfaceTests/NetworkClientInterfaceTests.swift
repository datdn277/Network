import Foundation
import XCTest
@testable import NetworkClientInterface

final class NetworkClientInterfaceTests: XCTestCase {
    func testFileUploadMimeTypeAliasUpdatesLegacyMineType() {
        var upload = FileUpload(
            withName: "avatar",
            fileName: "avatar.png",
            mineType: "image/png",
            path: "/tmp/avatar.png"
        )

        XCTAssertEqual(upload.mimeType, "image/png")

        upload.mimeType = "image/jpeg"

        XCTAssertEqual(upload.mineType, "image/jpeg")
    }

    func testCorrectlySpelledNetworkResponseProvidesLegacyIsSucces() {
        let response = SpelledResponse(
            isSuccess: true,
            errorCode: "",
            statusCode: "0",
            messageCode: ""
        )

        XCTAssertTrue(response.isSuccess)
        XCTAssertTrue(response.isSucces)
    }

    func testNetworkRequestCacheReturnsMutatedCopy() {
        let original = TestRequest(cache: false)
        let cached = original.cache(true)

        XCTAssertFalse(original.cache)
        XCTAssertTrue(cached.cache)
    }

    func testNetworkIOErrorUnauthorizedHelper() {
        XCTAssertTrue(NetworkIOError.httpError(401).isUnauthorized)
        XCTAssertFalse(NetworkIOError.httpError(500).isUnauthorized)
    }
}

private struct SpelledResponse: CorrectlySpelledNetworkResponse {
    let isSuccess: Bool
    let errorCode: String
    let statusCode: String
    let messageCode: String
}

private struct TestRequest: NetworkRequest {
    var cache: Bool
    var path = "/hello"
    var id = "hello"
    var method = "GET"
    var body = ""

    func request(_ baseUrl: String) -> URLRequest? {
        URL(string: baseUrl + path).map { URLRequest(url: $0) }
    }
}
