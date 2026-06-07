import Foundation

public protocol JSONEncodable {
    func encodeToJSON() -> Any
}

public extension JSONEncodable where Self: Encodable {
    func encodeToJSON() -> Any {
        guard let data = try? CodableHelper.jsonEncoder.encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        return object
    }
}

extension Bool: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension Float: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension Int: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension Int32: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension Int64: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension Double: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension Decimal: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension String: JSONEncodable {
    public func encodeToJSON() -> Any { self }
}

extension URL: JSONEncodable {
    public func encodeToJSON() -> Any { absoluteString }
}

extension UUID: JSONEncodable {
    public func encodeToJSON() -> Any { uuidString }
}

extension Array: JSONEncodable {
    public func encodeToJSON() -> Any {
        map { value in
            if let encodable = value as? JSONEncodable {
                return encodable.encodeToJSON()
            }
            return value
        }
    }
}

extension Set: JSONEncodable {
    public func encodeToJSON() -> Any {
        Array(self).encodeToJSON()
    }
}

extension Dictionary: JSONEncodable {
    public func encodeToJSON() -> Any {
        reduce(into: [String: Any]()) { result, item in
            let key = String(describing: item.key)
            if let encodable = item.value as? JSONEncodable {
                result[key] = encodable.encodeToJSON()
            } else {
                result[key] = item.value
            }
        }
    }
}

extension Data: JSONEncodable {
    public func encodeToJSON() -> Any { base64EncodedString() }
}

extension Date: JSONEncodable {
    public func encodeToJSON() -> Any {
        ISO8601DateFormatter().string(from: self)
    }
}
