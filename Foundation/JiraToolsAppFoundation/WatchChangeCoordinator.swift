import Foundation

public struct WatchChangeCoordinator<ID: Hashable & Sendable, State: Equatable & Sendable>: Sendable {
    private var states: [ID: State] = [:]
    private var hasReceivedInitialState = false

    public init() {}

    public mutating func reset() {
        hasReceivedInitialState = false
        states = [:]
    }

    public mutating func replace(with currentStates: [ID: State]) -> [WatchStateChange<ID, State>] {
        defer {
            states = currentStates
            hasReceivedInitialState = true
        }
        guard hasReceivedInitialState else {
            return []
        }

        var changes: [WatchStateChange<ID, State>] = []
        for (id, currentState) in currentStates {
            guard let previousState = states[id] else {
                changes.append(.added(id: id, current: currentState))
                continue
            }
            guard previousState != currentState else {
                continue
            }
            changes.append(.changed(id: id, previous: previousState, current: currentState))
        }
        for (id, previousState) in states where currentStates[id] == nil {
            changes.append(.removed(id: id, previous: previousState))
        }
        return changes
    }
}

public enum WatchStateChange<ID: Hashable & Sendable, State: Equatable & Sendable>: Equatable, Sendable {
    case added(id: ID, current: State)
    case changed(id: ID, previous: State, current: State)
    case removed(id: ID, previous: State)
}
