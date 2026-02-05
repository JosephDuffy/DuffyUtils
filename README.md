# DuffyUtils

This repo contains a set of optinionated utilities that I used in my day-to-day development. They are specifically created for how I work on my own projects, but also have configurations to enable me to use them at my work.

Most of these used to be simple bash/sh scripts. I migrated these to Swift because I like [Swift Argument Parser](https://github.com/apple/swift-argument-parser), having build-in types and functions for things like URLs, and I like to write my tools in the language I use everyday.

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

I alias this one to `oij`:

```fish
alias --save oij="open-in-jira"
```

## Installation

If you don't have Swift installed, first [install Swift](https://www.swift.org/install/). <sup>[Why Swift?](#why-swift)</sup>

### Homebew

Individual scripts can be installed via `brew`:

```bash
brew install josephduffy/duffyutils/git-new-branch-and-worktree
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
