# NetworkClientKit

Swift Package generic cho networking, kèm runtime và tool generate Swift request/model từ OpenAPI JSON.

Package hiện có các target chính:

- `NetworkClientInterface`: protocol, model, error, request/response contract.
- `NetworkClientKit`: implementation network bằng Alamofire.
- `NetworkClientOpenAPI`: runtime chung cho code sinh từ OpenAPI.

## Install

Trong `Package.swift` của project app/module:

```swift
.package(path: "../Network")
```

Thêm dependency theo nhu cầu:

```swift
.product(name: "NetworkClientInterface", package: "NetworkClientKit")
.product(name: "NetworkClientKit", package: "NetworkClientKit")
.product(name: "NetworkClientOpenAPI", package: "NetworkClientKit")
```

Nếu project dùng generated OpenAPI target riêng, target đó cần import:

```swift
import NetworkClientOpenAPI
```

Feature/app gọi network cần import:

```swift
import NetworkClientKit
import NetworkClientInterface
```

## NetworkClientKit Usage

### Create Network

`baseURL` là host/base path chính của backend. Generated request hoặc request thủ công chỉ cần trả về path.

```swift
let network = NetworkClient(
    baseURL: "https://api.example.com"
)
```

Nếu cần cache:

```swift
let cache = CompositeResponseBehavior(
    memory: MemoryResponseBehavior(),
    disk: DiskResponseBehavior()
)

let network = NetworkClient(
    baseURL: "https://api.example.com",
    responseBehavior: cache
)
```

### Manual Request

```swift
import Foundation
import NetworkClientInterface

struct ProfileRequest: NetworkRequest {
    var cache = true
    let path = "/profile"
    let id = "profile"
    let method = "GET"
    var body = ""

    func request(_ baseUrl: String) -> URLRequest? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}
```

Response DTO:

```swift
struct ProfileResponse: CorrectlySpelledNetworkResponse {
    let isSuccess: Bool
    let errorCode: String
    let statusCode: String
    let messageCode: String
    let name: String
}
```

Call API:

```swift
let result: Result<ProfileResponse, NetworkIOError> =
    await network.getData(request: ProfileRequest())
```

Raw string:

```swift
let result: Result<String, NetworkIOError> =
    await network.getData(request: ProfileRequest())
```

Callback:

```swift
network.getData(request: ProfileRequest()) { (result: Result<ProfileResponse, NetworkIOError>) in
    // handle result
}
```

### Error Mapping

`NetworkClient` maps errors như sau:

- invalid URL: `.invalidURL`
- Alamofire/network failure: `.networkError(error)`
- missing/invalid body: `.dataError`
- HTTP non-2xx: `.httpError(statusCode)`
- decoded `NetworkResponse.isSucces == false`: `.serviceError(...)`

### Auth Refresh

Implement `NetworkAuthManager`:

```swift
final class AuthManager: NetworkAuthManager {
    var accessToken: String?
    var refreshTokenExpiryDate: Date?

    func refreshToken(completion: @escaping (Bool) -> Void) {
        // Call refresh API, update accessToken, then complete.
        completion(true)
    }

    func canNotRefreshToken() {
        // Refresh token expired; route user to login if needed.
    }

    func sessionExpired(_ statusCode: Int) {
        // Called when 401 cannot be recovered.
    }
}

network.updateAuthManager(AuthManager())
```

Behavior:

- Only HTTP `401` triggers refresh/session-expired flow.
- Concurrent `401` responses share one refresh call.
- Each failed request retries once after refresh succeeds.
- If refresh fails, final result is `.httpError(401)` and `sessionExpired(401)` is called.

### Cache

Basic opt-in cache:

```swift
var request = ProfileRequest()
request.cache = true
```

Or:

```swift
let cachedRequest = ProfileRequest().cache(true)
```

Built-in cache behaviors:

- `MemoryResponseBehavior`
- `DiskResponseBehavior`
- `CompositeResponseBehavior`

Cache is written only for HTTP `2xx`.

Advanced policy:

```swift
struct CachedProfileRequest: CachePolicyNetworkRequest {
    var cache = true
    let cachePolicy: NetworkCachePolicy = .maxAge(300)
    let path = "/profile"
    let id = "profile"
    let method = "GET"
    var body = ""

    func request(_ baseUrl: String) -> URLRequest? {
        URL(string: baseUrl + path).map { URLRequest(url: $0) }
    }
}
```

Policies:

- `.disabled`
- `.cacheElseLoad`
- `.reloadIgnoringCache`
- `.cacheOnly`
- `.maxAge(TimeInterval)`

### Upload

```swift
struct AvatarUploadRequest: UploadNetworkRequest {
    var cache = false
    let path = "/avatar"
    let id = "avatar-upload"
    let method = "POST"
    var body = ""
    var files: [FileUpload]
    var parameters: [String: Any]? = nil

    func request(_ baseUrl: String) -> URLRequest? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}

let request = AvatarUploadRequest(
    files: [
        FileUpload(
            withName: "file",
            fileName: "avatar.png",
            mimeType: "image/png",
            path: imageURL.path
        )
    ],
    parameters: ["displayName": "Main Avatar"]
)

let result: Result<String, NetworkIOError> =
    await network.upload(request: request)
```

### Download

```swift
network.download(request: ProfileRequest(), config: DownloadConfig()) { result in
    // Result<URL?, NetworkIOError>
}
```

Custom destination behavior:

```swift
let config = DownloadConfig(
    directory: .cachesDirectory,
    domain: .userDomainMask,
    options: [.createIntermediateDirectories, .removePreviousFile]
)
```

### Request/Response Behaviors

`RequestBehavior` allows request preparation and response modification.

```swift
struct TraceBehavior: RequestBehavior {
    func prepare(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Trace-ID")
        return request
    }

    func modify(request: URLRequest, response: DataResponse) -> DataResponse {
        response
    }
}

let network = NetworkClient(
    baseURL: "https://api.example.com",
    requestBehaviors: [TraceBehavior()]
)
```

### Compatibility Notes

Legacy typo API is still available for source compatibility:

- `FileUpload.mineType`
- `NetworkResponse.isSucces`
- `NetworkClient.shouldHandelStatusCode`
- `NetworkIOError.serviceError(..., messsageCode: ...)`

Correctly spelled aliases are also available:

- `FileUpload.mimeType`
- `CorrectlySpelledNetworkResponse.isSuccess`
- `NetworkClient.shouldHandleStatusCode`

## OpenAPI Generate Tool

Goal: from one or more OpenAPI JSON files, generate Swift DTO models and API functions that return `RequestBuilder<T>`. `RequestBuilder<T>` conforms to `UploadNetworkRequest`, so it can be passed directly to `NetworkClient`.

Example generated usage:

```swift
let request = ProfileAPI.getProfile(
    profileDetailCriteriaDto: ProfileDetailCriteriaDto(accountNo: "123")
)

let result: Result<ProfileDetailDto, NetworkIOError> =
    await network.getData(request: request)
```

### Tool Files

```text
Tools/OpenAPICodegen/
  generate-openapi.sh
  preprocess-openapi.py
  openapi-codegen.json
  templates/swift5-network-client/
```

Example generated output:

```text
Examples/ProfileOpenAPI/OpenApi/
  Apis/
  Models/
```

### Prerequisites

Required commands:

```sh
openapi-generator-cli
jq
python3
```

Typical install:

```sh
npm install -g @openapitools/openapi-generator-cli
brew install jq
```

Pinning generator version is recommended for deterministic output. The local setup used during development resolved `openapi-generator-cli` to `7.21.0`.

### Generate

Run with default config:

```sh
Tools/OpenAPICodegen/generate-openapi.sh
```

Run with custom config:

```sh
Tools/OpenAPICodegen/generate-openapi.sh path/to/openapi-codegen.json
```

The default config reads:

```text
references/OpenApi/profile.json
```

and writes:

```text
Examples/ProfileOpenAPI/OpenApi/Apis
Examples/ProfileOpenAPI/OpenApi/Models
```

### Config Format

Default config:

```json
{
  "generatorName": "swift5",
  "templateDir": "Tools/OpenAPICodegen/templates/swift5-network-client",
  "projectName": "OpenAPIClient",
  "typeMappings": {
    "number": "Decimal"
  },
  "additionalProperties": {
    "hideGenerationTimestamp": "true",
    "useJsonEncodable": "true",
    "hashableModels": "true",
    "validatable": "false",
    "generateModelAdditionalProperties": "false"
  },
  "modules": [
    {
      "name": "ProfileOpenAPI",
      "inputDir": "references/OpenApi",
      "outputDir": "Examples/ProfileOpenAPI/OpenApi",
      "tagStrategy": "fileName"
    }
  ]
}
```

Important fields:

- `templateDir`: custom template that imports `NetworkClientOpenAPI`.
- `typeMappings`: OpenAPI type mapping, for example `number -> Decimal`.
- `additionalProperties`: options forwarded to `openapi-generator-cli`.
- `modules`: one entry per feature/module.
- `inputDir`: directory containing `.json` OpenAPI specs.
- `outputDir`: generated `Apis` and `Models` destination.
- `tagStrategy`: `fileName` or `preserve`.

### Preprocess Rules

`preprocess-openapi.py` runs before generator:

- Reads OpenAPI JSON using `utf-8-sig`.
- Removes schema `"format": "date"` and `"format": "date-time"` by default.
- If `tagStrategy == "fileName"`, derives API tag from filename.
- Rewrites operation tags so one JSON file generates one API class.

Example:

```text
profile.json -> ProfileAPI.swift
```

### Single Module Project

Recommended structure:

```text
MyApp/
  Resources/OpenApi/
    account.json
    profile.json
  Sources/OpenApi/
    Apis/
    Models/
```

Config:

```json
{
  "modules": [
    {
      "name": "AppOpenAPI",
      "inputDir": "Resources/OpenApi",
      "outputDir": "Sources/OpenApi",
      "tagStrategy": "fileName"
    }
  ]
}
```

Generated use:

```swift
let request = ProfileAPI.getProfile()
let result: Result<ProfileResponseDto, NetworkIOError> =
    await network.getData(request: request)
```

### Multi Module Project

Recommended structure:

```text
Features/
  Profile/
    Resources/OpenApi/
      profile.json
    Sources/OpenApi/
      Apis/
      Models/
  Dashboard/
    Resources/OpenApi/
      dashboard.json
    Sources/OpenApi/
      Apis/
      Models/
```

Config:

```json
{
  "modules": [
    {
      "name": "ProfileOpenAPI",
      "inputDir": "Features/Profile/Resources/OpenApi",
      "outputDir": "Features/Profile/Sources/OpenApi",
      "tagStrategy": "fileName"
    },
    {
      "name": "DashboardOpenAPI",
      "inputDir": "Features/Dashboard/Resources/OpenApi",
      "outputDir": "Features/Dashboard/Sources/OpenApi",
      "tagStrategy": "fileName"
    }
  ]
}
```

Each feature module should depend on:

```swift
.product(name: "NetworkClientOpenAPI", package: "NetworkClientKit")
```

The app or feature that executes requests should also depend on:

```swift
.product(name: "NetworkClientKit", package: "NetworkClientKit")
```

### Base URL And Path Prefix

Set host/base URL on `NetworkClient`:

```swift
let network = NetworkClient(baseURL: "https://api.example.com")
```

Generated API produces paths, not hosts:

```text
/profile/detail/1.0
```

Optional per-API path prefix:

```swift
OpenAPIClientAPI.pathExtensions["ProfileAPI"] = "/profile-service"
```

Final URL:

```text
https://api.example.com/profile-service/profile/detail/1.0
```

### Authentication In Generated Requests

Generated `RequestBuilder` includes `requiresAuthentication`.

The template currently sets:

```swift
requiresAuthentication: true
```

when the OpenAPI operation has auth methods, otherwise:

```swift
requiresAuthentication: false
```

`NetworkRequestAdapter` removes the internal marker header before sending the request. If `requiresAuthentication == false`, it skips the bearer token.

### Regeneration Rules

Generated folders are disposable:

```text
OpenApi/Apis
OpenApi/Models
```

Do not hand-edit files under these folders. Put custom code in separate folders:

```text
Sources/OpenApiOverrides/
Sources/Extensions/
```

The generator script deletes and recreates `Apis` and `Models` for each configured module.

### Verify Generated Code

After generation:

```sh
swift build
swift test
```

The package includes runtime tests that prove `RequestBuilder` output can be passed directly to `NetworkClient`:

```text
Tests/NetworkClientOpenAPITests/NetworkClientOpenAPITests.swift
```

### Troubleshooting

If `mapfile: command not found` appears, use the current script version. It supports macOS default bash.

If `AnyCodable` is missing, use `NetworkClientOpenAPI.AnyCodable`. The runtime provides a fallback so generated models do not need an extra `AnyCodable` package.
If `AnyCodable` is missing, use `NetworkClientOpenAPI.AnyCodable`. The runtime provides a fallback so generated models do not need an extra `AnyCodable` package.

```text
Tools/OpenAPICodegen/templates/swift5-network-client
```

If generated APIs are grouped into unexpected classes, use:

```json
"tagStrategy": "fileName"
```

If a module has type name collisions, prefer one generated target per module. If all APIs must live in one target, use generator options such as model/API name prefixing.
