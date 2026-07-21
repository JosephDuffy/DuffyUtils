import Testing
@testable import JiraToolsFoundation

@Suite
struct JiraToolsErrorTests {
    @Test
    func hasAUserFacingDescription() {
        let error = JiraToolsError("The Jira token was rejected.")

        #expect(error.localizedDescription == "The Jira token was rejected.")
    }
}
