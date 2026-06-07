import Foundation
import NetworkClientInterface

public final class CompositeResponseBehavior: ResponseBehavior {
    private let behaviors: [any ResponseBehavior]

    public init(_ behaviors: [any ResponseBehavior]) {
        self.behaviors = behaviors
    }

    public convenience init(memory: MemoryResponseBehavior, disk: DiskResponseBehavior) {
        self.init([memory, disk])
    }

    public func read(_ request: any NetworkRequest) -> DataResponse? {
        for behavior in behaviors {
            if let response = behavior.read(request) {
                return response
            }
        }
        return nil
    }

    public func write(request: any NetworkRequest, response: DataResponse) {
        behaviors.forEach { $0.write(request: request, response: response) }
    }
}
