import Foundation

public extension KeyedDecodingContainer {
    func decodeIfPresent<T>(_ key: Key) throws -> T? where T: Decodable {
        try decodeIfPresent(T.self, forKey: key)
    }
}
