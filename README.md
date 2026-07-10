# DuffyUtils

This repo contains a set of optinionated utilities that I used in my day-to-day development. They are specifically created for how I work on my own projects, but also have configurations to enable me to use them at my work.

Most of these used to be simple bash/sh scripts. I migrated these to Swift because I like [Swift Argument Parser](https://github.com/apple/swift-argument-parser), having build-in types and functions for things like URLs, and I like to write my tools in the language I use everyday.

## Core Concepts

- I include the Jira ticket ID for the work in the branches I work on.
- Branch names generally take the form `kind/ABC-123_change-description`. `kind` is `feature`, `bugfix`, etc.
- Everything is configured via the git config.
- Things should default to being is relative to the main repo, so you can run these from any worktree and it will produce output in the same place.
- I have a checkout of the production code at `~/Developer/project-name`, active worktrees under `~/Developer/project-name-worktree/ABC-123_change-description`, and PRs I'm reviewing under `~/Developer/project-name-prs/ABC-123_change-description`.
- Script include (somewhat) useful `--help` output.

## Scripts

This repo provides various scripts. The aim is to have some cohension between them, such as using the same prefix for configurations.

## `git-new-branch-and-worktree`

This is probably my most used script. The goal is to _easily_ manage worktrees, which I make very liberal use of. This script specifically creates a new worktree with a name based on the branch. I generally use this as:

```bash
# Could also be `project-name-`; my `~/Developer` is busy enough without all my worktrees.
git config set "duffyutils.worktree-prefix" "project-name-worktrees/"
# Could also be "main" or something else. Will default to the current branch.
git config set "duffyutils.worktree-starting-point" "develop"
# I use iTerm, but you might use Terminal or something else.
git config set --global "duffyutils.open-new-worktrees-with" "iTerm"
```

With this I run e.g.:

```bash
git new-branch-and-worktree feature/ABC-123_add-new-feature
```

And it creates a new worktree at `project-name-worktrees/ABC-123_add-new-feature`, then opens it in iTerm.

## `git-checkout-pr-in-worktree`

This command will checkout a PR from GitHub in a new worktree. It can be configured to use its own directory:

```bash
git config set "duffyutils.pr-worktree-prefix" "project-name-prs/"
```

If not set it will fallback to `duffyutils.worktree-prefix` or the main repo's root.

## `open-in-jira`

This uses the Jira ticket ID from the branch name to open the branch in Jira. It can be setup as:

```bash
git config set "duffyutils.jira-domain" "company.atlassian.net"
```

Then running on the branch `feature/ABC-123_add-new-feature`:

```bash
open-in-jira
```

Will open `https://company.atlassian.net/browse/ABC-123`.

You can also pass an issue ID directly:

```bash
open-in-jira --issue-id ABC-123
```

And override the Jira domain:

```bash
open-in-jira --issue-id ABC-123 --jira-domain "company.atlassian.net"
```

I alias this one to `oij`:

```fish
alias --save oij="open-in-jira"
```

## `git-remove-current-worktree-and-branch`

This is the last step in the process of working on a change or reviewing a PR.

Run

```bash
git remove-current-worktree-and-branch
```

and the current workrtree and branch will be removed. There are some checks for things like uncommitted changes, but remember this is destructive :)

## `export-signed-command`

This builds one of the other local executable products in release mode, signs it with a Developer ID Application identity, zips it, and submits the zip to Apple's notarisation service:

```bash
xcrun notarytool store-credentials duffyutils

swift run export-signed-command open-in-jira \
    --signing-identity "Developer ID Application: Your Name (TEAMID)" \
    --notary-profile duffyutils
```

The generated `.zip` file contains a universal macOS 13+ binary and its required Swift runtime
libraries. After unzipping, keep the directory intact and add it to `PATH` before running the
command.
The signing identity must be a `Developer ID Application` certificate; `Apple Development` and
`Apple Distribution` certificates cannot be used for notarised command-line tools.

## `Jira Tools.app`

`Jira Tools.app` is a macOS 13+ SwiftUI app that currently displays a Hello World window. Its
app target lives in [`Apps/JiraTools`](Apps/JiraTools) and links the `JiraToolsCore` library that
also powers the `jira-tools` command-line product.

To build it locally without signing:

```bash
xcodebuild \
    -project Apps/JiraTools/JiraTools.xcodeproj \
    -scheme JiraToolsApp \
    CODE_SIGNING_ALLOWED=NO \
    build
```

To create a notarised Developer ID disk image, first save a `notarytool` profile, then run:

```bash
xcrun notarytool store-credentials duffyutils

swift run export-signed-app \
    --signing-identity "Developer ID Application: Your Name (TEAMID)" \
    --team-id TEAMID \
    --notary-profile duffyutils
```

The exporter creates a universal app archive, a drag-install DMG, notarises it, staples the
notarization ticket, and validates the resulting disk image.

## Installation

If you don't have Swift installed, first [install Swift](https://www.swift.org/install/). <sup>[Why Swift?](#why-swift)</sup>

### Homebew

Individual scripts can be installed via `brew`:

```bash
brew install josephduffy/duffyutils/git-new-branch-and-worktree
```

If you tap it you can install them in a slightly less verbose way:

```bash
brew tap josephduffy/duffyutils
brew install git-new-branch-and-worktree
brew install git-checkout-pr-in-worktree
brew install open-in-jira
brew install git-remove-current-worktree-and-branch
```

or all at once:

```bash
brew tap josephduffy/duffyutils
brew install git-new-branch-and-worktree git-checkout-pr-in-worktree open-in-jira git-remove-current-worktree-and-branch
```

### Manual

Clone this repository and build using Swift Package Manager:

```bash
git clone https://github.com/josephduffy/DuffyUtils.git
cd DuffyUtils
swift build -c release --product git-new-branch-and-worktree
cp .build/release/git-new-branch-and-worktree /usr/local/bin/
```

## Configuration

Anything that acts on a git repo is configurable via the repo's git config. This ensures that the scripts can reach the same outcome across different repos, such as using the same source branch for a new worktree.

## Why Swift?

I like to write my tools in the language I use every day.

## Why Not Bash?

All the management and string manipulation is a pain.

## Why Not JS/TS?

Ok that's fair. More people will have JS environments installed already? Refer back to [Why Swift?](#why-swift) I guess.

## Caveats

Although I do not anticipate any contributions, I will note that this is a _personal_ project and I do not intend to cater for the use cases of others. If there's a change that would not impact my usage I will accept. There's more chance of it being accepted if we work on the same project.

I will also note that there are no tests and a general lack of documentation. Although I intend for the code to be maintainable I am not aiming for a perfect or exemplorary codebase 🙂
