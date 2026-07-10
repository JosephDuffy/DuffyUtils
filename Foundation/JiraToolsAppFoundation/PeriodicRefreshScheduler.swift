import Foundation

public actor PeriodicRefreshScheduler {
    private var task: Task<Void, Never>?

    public init() {}

    deinit {
        task?.cancel()
    }

    public var isRunning: Bool {
        task != nil
    }

    public func start(
        every interval: Duration,
        refresh: @escaping @Sendable () async -> Void,
    ) throws {
        guard interval > .zero else {
            throw PeriodicRefreshSchedulerError.nonPositiveInterval
        }

        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                await refresh()
                do {
                    try await Task.sleep(for: interval)
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}

public enum PeriodicRefreshSchedulerError: Error, Equatable, Sendable {
    case nonPositiveInterval
}
