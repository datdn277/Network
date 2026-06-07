import Foundation

open class CodableHelper {
    public static var jsonDecoder: JSONDecoder = JSONDecoder()
    public static var jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    open class func decode<T>(_ type: T.Type, from data: Data) -> Result<T, any Error> where T: Decodable {
        Result { try jsonDecoder.decode(type, from: data) }
    }

    open class func encode<T>(_ value: T) -> Result<Data, any Error> where T: Encodable {
        Result { try jsonEncoder.encode(value) }
    }
}
