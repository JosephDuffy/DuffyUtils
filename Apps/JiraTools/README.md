# Jira Tools

Jira Tools is a macOS 13+ SwiftUI app for monitoring and acting on Jira data. Its first feature,
Stale Tickets, identifies tickets that need attention and can refresh automatically while the app
is running.

## Project Structure

- `Foundation/JiraToolsFoundation`: Shared models and app infrastructure.
- `Foundation/JiraToolsUI`: Shared application UI.
- `Services/JiraAPI`: Jira authentication, API access, and response models.
- `Features/StaleTickets`: Stale Tickets business logic and UI.
- `Root`, `Credentials`, and `Resources`: App composition, app-owned flows, and resources.

All package dependencies use paths relative to this directory, so the project can be built without
any parent repository.

## Development

Build the app without signing:

```bash
xcodebuild \
    -project JiraTools.xcodeproj \
    -scheme JiraToolsApp \
    CODE_SIGNING_ALLOWED=NO \
    build
```

Run the package tests:

```bash
swift test --package-path Foundation/JiraToolsFoundation
swift test --package-path Services/JiraAPI
swift test --package-path Features/StaleTickets
```

## Roadmap

- [ ] Change to rules-based tools
  - [ ] Provide "derived fields" that can be loaded: latest comment, assignee comment, my comment, etc.
  - [ ] Rules define a set of checks that are performed against one or more fields
  - [ ] Tools include a set of rules and define the severity and tickets that fail a rule
  - [ ] Tools define which fields to display, including the order
  - [ ] Tools can refer to central templates. When modifying tool rules remove the link and pull the rules in
- [ ] Disable tabs
- [ ] Create settings UI, move credentials there
- [ ] Reduce RAM usage
- [ ] Properly handle HTTP 429
- [ ] Add OAuth login
- [ ] Keyboard shortcuts
- [ ] Only refresh when a configuration value that impacts the filter is changed
- [ ] Share tools via a `.jiratool` file
- [ ] Reorder column
- [ ] Show status in sidebar
- [ ] Badge icon for warnings/errors
- [ ] Refresh on open
- [ ] Open at login
- [ ] Automatic build and publish on GitHub
- [ ] Add update mechanism via Sparkle
- [ ] Menu bar icon with a summary UI available
- [ ] Snooze tickets
- [ ] Misc UI and UX improvements
- [ ] Integrate with local LLMs that ship with macOS 27 Golden Gate
- [ ] Support renaming from sidebar
- [ ] Move extra fields to a global setting
