import Foundation
import NetworkClientInterface

public final class TokenRefreshCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var isRefreshing = false
    private var completions: [(Bool) -> Void] = []

    public init() {}

    public func refreshToken(
        using authManager: any NetworkAuthManager,
        completion: @escaping (Bool) -> Void
    ) {
        lock.lock()
        if isRefreshing {
            completions.append(completion)
            lock.unlock()
            return
        }

        isRefreshing = true
        completions.append(completion)
        lock.unlock()

        authManager.refreshToken { [weak self] success in
            self?.completeRefresh(success: success)
        }
    }

    private func completeRefresh(success: Bool) {
        lock.lock()
        let pendingCompletions = completions
        completions = []
        isRefreshing = false
        lock.unlock()

        pendingCompletions.forEach { $0(success) }
    }
}
