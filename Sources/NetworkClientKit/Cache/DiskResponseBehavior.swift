import Foundation
import NetworkClientInterface

public final class DiskResponseBehavior: ResponseBehavior {
    private struct StoredResponse: Codable {
        var statusCode: Int?
        var data: Data?
        var createdAt: Date
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let keyProvider: CacheKeyProvider
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public convenience init(
        directory: FileManager.SearchPathDirectory = .cachesDirectory,
        domain: FileManager.SearchPathDomainMask = .userDomainMask,
        folderName: String = "NetworkClientCache",
        fileManager: FileManager = .default,
        keyProvider: @escaping CacheKeyProvider = NetworkCacheKey.requestID
    ) {
        let baseURL = fileManager.urls(for: directory, in: domain).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.init(
            directoryURL: baseURL.appendingPathComponent(folderName, isDirectory: true),
            fileManager: fileManager,
            keyProvider: keyProvider
        )
    }

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        keyProvider: @escaping CacheKeyProvider = NetworkCacheKey.requestID
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.keyProvider = keyProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func read(_ request: any NetworkRequest) -> DataResponse? {
        let fileURL = cacheFileURL(for: request)
        guard let storedData = try? Data(contentsOf: fileURL),
              let storedResponse = try? decoder.decode(StoredResponse.self, from: storedData) else {
            return nil
        }

        return DataResponse(
            statusCode: storedResponse.statusCode,
            data: storedResponse.data,
            createdAt: storedResponse.createdAt
        )
    }

    public func write(request: any NetworkRequest, response: DataResponse) {
        guard let statusCode = response.statusCode, (200...299).contains(statusCode) else {
            return
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let storedResponse = StoredResponse(
                statusCode: response.statusCode,
                data: response.data,
                createdAt: response.createdAt
            )
            let storedData = try encoder.encode(storedResponse)
            try storedData.write(to: cacheFileURL(for: request), options: .atomic)
        } catch {
            return
        }
    }

    public func remove(_ request: any NetworkRequest) {
        try? fileManager.removeItem(at: cacheFileURL(for: request))
    }

    public func removeAll() {
        try? fileManager.removeItem(at: directoryURL)
    }

    private func cacheFileURL(for request: any NetworkRequest) -> URL {
        directoryURL.appendingPathComponent(stableHash(keyProvider(request))).appendingPathExtension("json")
    }

    private func stableHash(_ key: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
