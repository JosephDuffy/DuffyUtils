# DuffyUtils

This repo contains a set of optinionated utilities that I used in my day-to-day development. They are specifically created for how I work on my own projects, but also have configurations to enable me to use them at my work.

Most of these used to be simple bash/sh scripts. I migrated these to Swift because I like [Swift Argument Parser](https://github.com/apple/swift-argument-parser), having build-in types and functions for things like URLs, and I like to write my tools in the language I use everyday.

## Configuration

Anything that acts on a git repo is configurable via the repo's git config. This ensures that the scripts can reach the same outcome across different repos, such as using the same source branch for a new worktree.

## Caveats

Although I do not anticipate any contributions, I will note that this is a _personal_ project and I do not intend to cater for the use cases of others. If there's a change that would not impact my usage I will accept. There's more chance of it being accepted if we work on the same project.

I will also note that there are no tests and a general lack of documentation. Although I intend for the code to be maintainable I am not aiming for a perfect or exemplorary codebase 🙂
