import Foundation

public protocol NetworkAuthManager {
    var accessToken: String? { get }
    var refreshTokenExpiryDate: Date? { get }

    func refreshToken(completion: @escaping (Bool) -> Void)
    func canNotRefreshToken()
    func sessionExpired(_ statusCode: Int)
}
