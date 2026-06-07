import Foundation
import NetworkClientInterface

public typealias CacheKeyProvider = (any NetworkRequest) -> String

public enum NetworkCacheKey {
    public static func requestID(_ request: any NetworkRequest) -> String {
        request.id
    }
}
