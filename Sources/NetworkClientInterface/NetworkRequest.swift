import Foundation

public protocol NetworkRequest {
    var cache: Bool { get set }
    var path: String { get }
    var id: String { get }
    var method: String { get }
    var body: String { get set }

    func request(_ baseUrl: String) -> URLRequest?
}

public extension NetworkRequest {
    func cache(_ value: Bool) -> Self {
        var copy = self
        copy.cache = value
        return copy
    }
}

public enum NetworkCachePolicy: Equatable {
    case disabled
    case cacheElseLoad
    case reloadIgnoringCache
    case cacheOnly
    case maxAge(TimeInterval)
}

public protocol CachePolicyNetworkRequest: NetworkRequest {
    var cachePolicy: NetworkCachePolicy { get }
}

public extension NetworkRequest {
    var resolvedCachePolicy: NetworkCachePolicy {
        if let cachePolicyRequest = self as? any CachePolicyNetworkRequest {
            return cachePolicyRequest.cachePolicy
        }

        return cache ? .cacheElseLoad : .disabled
    }
}
