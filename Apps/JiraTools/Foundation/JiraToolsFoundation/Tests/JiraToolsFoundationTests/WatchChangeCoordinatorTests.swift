import JiraToolsFoundation
import Testing

@Suite
struct WatchChangeCoordinatorTests {
    @Test
    func suppressesTheInitialStateAndReportsSubsequentChanges() {
        var coordinator = WatchChangeCoordinator<String, Int>()

        #expect(coordinator.replace(with: ["ABC-1": 1]).isEmpty)
        #expect(coordinator.replace(with: ["ABC-1": 1]).isEmpty)
        #expect(coordinator.replace(with: ["ABC-1": 2]) == [
            .changed(id: "ABC-1", previous: 1, current: 2),
        ])
    }

    @Test
    func reportsAddedAndRemovedStatesAfterTheInitialRefresh() {
        var coordinator = WatchChangeCoordinator<String, Int>()

        _ = coordinator.replace(with: ["ABC-1": 1])

        #expect(coordinator.replace(with: ["ABC-2": 2]) == [
            .added(id: "ABC-2", current: 2),
            .removed(id: "ABC-1", previous: 1),
        ])
    }
}
