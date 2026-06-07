import Foundation

open class JSONEncodingHelper {
    open class func encodingParameters<T: Encodable>(forEncodableObject encodableObj: T?) -> [String: Any]? {
        guard let encodableObj else { return nil }

        do {
            return JSONDataEncoding.encodingParameters(jsonData: try CodableHelper.encode(encodableObj).get())
        } catch {
            return nil
        }
    }

    open class func encodingParameters(forEncodableObject encodableObj: Any?) -> [String: Any]? {
        guard let encodableObj else { return nil }

        do {
            let data = try JSONSerialization.data(withJSONObject: encodableObj)
            return JSONDataEncoding.encodingParameters(jsonData: data)
        } catch {
            return nil
        }
    }
}
