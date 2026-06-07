import Alamofire
import Foundation
import NetworkClientInterface

public struct NetworkRequestRetrier: RequestRetrier, @unchecked Sendable {
    private let authManager: any NetworkAuthManager
    private let refreshCoordinator: TokenRefreshCoordinator
    private let retryAttemptTracker: RetryAttemptTracker

    public init(authManager: any NetworkAuthManager) {
        self.init(authManager: authManager, refreshCoordinator: TokenRefreshCoordinator())
    }

    public init(authManager: any NetworkAuthManager, refreshCoordinator: TokenRefreshCoordinator) {
        self.authManager = authManager
        self.refreshCoordinator = refreshCoordinator
        self.retryAttemptTracker = RetryAttemptTracker()
    }

    public func retry(
        _ request: Alamofire.Request,
        for session: Alamofire.Session,
        dueTo error: any Error,
        completion: @escaping (Alamofire.RetryResult) -> Void
    ) {
        guard request.response?.statusCode == 401,
              request.retryCount == 0,
              retryAttemptTracker.markAttemptedIfNeeded(requestID: request.id) else {
            completion(.doNotRetry)
            return
        }

        if let expiryDate = authManager.refreshTokenExpiryDate, expiryDate <= Date() {
            authManager.canNotRefreshToken()
            completion(.doNotRetry)
            return
        }

        refreshCoordinator.refreshToken(using: authManager) { success in
            if success {
                completion(.retry)
            } else {
                completion(.doNotRetry)
            }
        }
    }
}

private final class RetryAttemptTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var attemptedRequestIDs = Set<UUID>()

    func markAttemptedIfNeeded(requestID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !attemptedRequestIDs.contains(requestID) else {
            return false
        }

        attemptedRequestIDs.insert(requestID)
        return true
    }
}
