import Foundation
import NetworkClientInterface

public final class MemoryResponseBehavior: ResponseBehavior {
    private let lock = NSLock()
    private var storage: [String: DataResponse]
    private let keyProvider: CacheKeyProvider

    public init(
        storage: [String: DataResponse] = [:],
        keyProvider: @escaping CacheKeyProvider = NetworkCacheKey.requestID
    ) {
        self.storage = storage
        self.keyProvider = keyProvider
    }

    public func read(_ request: any NetworkRequest) -> DataResponse? {
        lock.lock()
        defer { lock.unlock() }
        return storage[keyProvider(request)]
    }

    public func write(request: any NetworkRequest, response: DataResponse) {
        guard let statusCode = response.statusCode, (200...299).contains(statusCode) else {
            return
        }

        lock.lock()
        storage[keyProvider(request)] = response
        lock.unlock()
    }

    public func remove(_ request: any NetworkRequest) {
        lock.lock()
        storage.removeValue(forKey: keyProvider(request))
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}
