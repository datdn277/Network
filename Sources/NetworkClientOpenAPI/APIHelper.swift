import Foundation

public struct APIHelper {
    public static func rejectNil(_ source: [String: Any?]) -> [String: Any]? {
        let destination = source.reduce(into: [String: Any]()) { result, item in
            if let value = item.value {
                result[item.key] = value
            }
        }
        return destination.isEmpty ? nil : destination
    }

    public static func rejectNilHeaders(_ source: [String: Any?]) -> [String: String] {
        source.reduce(into: [String: String]()) { result, item in
            if let collection = item.value as? [Any?] {
                result[item.key] = collection.compactMap(convertAnyToString).joined(separator: ",")
            } else if let value = item.value {
                result[item.key] = convertAnyToString(value)
            }
        }
    }

    public static func convertBoolToString(_ source: [String: Any]?) -> [String: Any]? {
        guard let source else { return nil }

        return source.reduce(into: [String: Any]()) { result, item in
            switch item.value {
            case let value as Bool:
                result[item.key] = value.description
            default:
                result[item.key] = item.value
            }
        }
    }

    public static func convertAnyToString(_ value: Any?) -> String? {
        guard let value else { return nil }

        if let rawRepresentable = value as? any RawRepresentable {
            return "\(rawRepresentable.rawValue)"
        }

        return "\(value)"
    }

    public static func mapValueToPathItem(_ source: Any) -> Any {
        if let collection = source as? [Any?] {
            return collection.compactMap(convertAnyToString).joined(separator: ",")
        }

        return source
    }

    public static func mapValuesToQueryItems(
        _ source: [String: (wrappedValue: Any?, isExplode: Bool)]
    ) -> [URLQueryItem]? {
        let destination = source.reduce(into: [URLQueryItem]()) { result, item in
            guard let wrappedValue = item.value.wrappedValue else { return }

            if let collection = wrappedValue as? [Any?] {
                let values = collection.compactMap(convertAnyToString)
                if item.value.isExplode {
                    values.forEach { result.append(URLQueryItem(name: item.key, value: $0)) }
                } else {
                    result.append(URLQueryItem(name: item.key, value: values.joined(separator: ",")))
                }
            } else {
                result.append(URLQueryItem(name: item.key, value: convertAnyToString(wrappedValue)))
            }
        }

        return destination.isEmpty ? nil : destination
    }

    public static func mapValuesToQueryItems(_ source: [String: Any?]) -> [URLQueryItem]? {
        let destination = source.reduce(into: [URLQueryItem]()) { result, item in
            guard let value = item.value else { return }

            if let collection = value as? [Any?] {
                collection
                    .compactMap(convertAnyToString)
                    .forEach { result.append(URLQueryItem(name: item.key, value: $0)) }
            } else {
                result.append(URLQueryItem(name: item.key, value: convertAnyToString(value)))
            }
        }

        return destination.isEmpty ? nil : destination
    }
}
