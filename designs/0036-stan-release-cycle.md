- Feature Name: Release Schedule for Stan
- Start Date: 2025-12-08
- RFC PR:
- Stan Issue:

# Summary

[summary]: #summary

Define a regular release cycle and associated release processes for Stan's core packages.

# Motivation

[motivation]: #motivation

Stan already has a informally defined release cycle. This document seeks to write down what
is currently done and formalize some existing practices while smoothing over rough edges
in the process.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

There are several different code products in the Stan ecosystem which are released in
tandem with each other. These are:

- `stan-dev/math` - the Stan Math library (hereafter "Stan Math").
- `stan-dev/stan` - the Stan algorithms and language support library, which depends on Stan Math.
- `stan-dev/stanc3` - the Stan compiler.
- `stan-dev/cmdstan` - the command line interface to Stan, which depends on `stan` and (built executables of) `stanc3`.

The Stan Math library uses its own versioning scheme based on semantic versioning of the C++ API;
the other three packages use a shared versioning scheme which is primarily based on the
versioning of the Stan _language_ itself.

These packages are released on a triannual pace. A release candidate build of
each will be made available approximately one week before the release for testing.

Within a given release, the packages are released in the order listed above,
though a release is not considered complete until all four packages have been released.
The documentation repository at `stan-dev/docs` is also re-built at the conclusion of the release.

## Release process

The release process proceeds in stages:

### One month before release (3 months after last release)

- Release manager decides on precise release date. Typically a Monday, though considerations
  for holidays or travel of core developers may mean a Tuesday is more appropriate.
- This will naturally imply a start date for the
  _feature freeze_ period, which is approximately one week earlier and allows
  for testing of release candidates without the underlying code changing during
  the release window.
- Developers are notified of the upcoming release date and feature freeze period through
  a post on the Stan forums. This post gives an opportunity for developers to give
  feedback on the dates and highlight any changes that should be considered before the freeze.

### Two weeks before release date

- Release issue filed against CmdStan repository (as the most-downstream of the four packages),
  which tracks the individual release steps in a checklist.
- Release notes are drafted for each package

### One week before release date (start of feature freeze)

- Release candidates are published for each of the four packages.
- A forumn announcement calling for testing of the release candidates is made.

After the release candidates are published, there is a fork in the process depending
on whether any critical issues are found during testing.

- If no critical issues are found, the release proceeds as normal.
- If critical issues are found, the release is paused while the issues are addressed.
  A new release candidate is published once the issues are resolved, and testing
  restarts. The release date is pushed back by at least one week to allow for
  sufficient testing time.

### Release day

- Each package is released in turn, starting with Stan Math and ending with CmdStan.
- Release notes are finalized and published.
- Announcement of the new release is made on the Stan forums and Stan blog.

### Post-release

- The release issue is closed.
- The feature freeze ends, pending changes can be merged again.

# Reference-level explanation

## The Release Manager

The release manager is a volunteer role taken on by a Stan developer.
The release manager is responsible for coordinating the release process
and making administrative decisions such as setting release dates and
deciding on whether to proceed with a release in the face of critical issues.

These decisions are made under the principle of unanimous consent -- if
no other developers object, the release manager's decision stands. If there
are objections, usual conflict resolution processes are followed under
the Stan governance model. Often, the easiest resolution is for the objector
to (perhaps temporarily) volunteer for the release manager role.

## Deciding on release dates

The release manager should pick a release date that is approximately four (but no more than five)
months after the last release. It should come early in the week (Monday or Tuesday),
and avoid major holidays and any of their own commitments that would interfere
with their ability to manage the release.

Similar consideration in terms of holidays or travel should be given to the feature freeze
date, which must be at least one week prior to the intended release date.

## Deciding on what features should be included

By default, the state of the current development branches on the day of the feature freeze
is the contents of the release. During the time before the freeze, the release manager (and
other developers) may wish to prioritize certain changes in order to get them into the release.

If there are known critical issues (such as build failures), the feature freeze can be delayed
to allow for their resolution.

If there are broken or incomplete features that cannot be resolved before the feature freeze,
they should be reverted or disabled prior to the freeze date.

## Critical issues during testing

Defining a critical issue is a difficult judgement call. Generally, to a given user,
whichever problem they are facing in their modelling will be critical to them. This means
that delaying a release in order to fix one issue will necessitate other users
waiting longer for fixes that may have been ready to go for some time.

A simple list of things that should always be considered critical issues is:

- Compilation failures on on supported platforms, especially if the same code previously compiled.
- Major performance regressions in core functionality.
- Incorrect results, particularly if previous releases were correct.

Another consideration is the age of the issue -- if a bug is found during the release process,
but it is one that can be reproduced in previous releases, it may be better to
defer fixing it to a later release in order to avoid delaying the current release:
the primary purpose of the release candidate window is to find issues in **new** or **recently changed** code.

## Releasable artifacts

For `stan-dev/math` and `stan-dev/stan`, the release artifact is a tagged release on GitHub
and a corresponding source tarball uploaded to GitHub releases.

For `stan-dev/stanc3`, the release artifact is a tagged release on GitHub and
pre-built binaries for the following platforms:

- Windows (x86_64)
- macOS (x86_64 and arm64, usually packaged as a single universal binary)
- Linux (x86_64 and the following Debian architectures: arm64, ppc64el, s390x, armhf, armel)

For `stan-dev/cmdstan`, the release artifact is a tagged release on GitHub and
tarballs which contain the C++ source of CmdStan along with pre-built
stanc3 binaries in the `bin/` directory. The primary tarball
contains Windows, macOS, and x86_64 Linux binaries in one. The other
Linux architectures are provided as separate tarballs.

A tarball which contains the built object code of CmdStan when built on
a Google Colab instance is also provided for teaching convenience.

## Release notes

Release notes are prepared in a bulleted list format for each package.
A script in the `stan-dev/ci-scripts` repository is available to start
this process by generating a draft which pulls text from the descriptions
of merged pull requests since the last release date.

These usually need editing for tense and clarity, and are also generally
re-ordered so the most important changes appear first. Small changes, like
updating CI workflows, can often be omitted entirely.

A few important features should be selected for highlighting in the release announcement.

## Patch releases

Patch releases (e.g., 2.30.1 following 2.30.0) are uncommon in Stan;
part of the reason for the regular schedule is to avoid any one
change taking too long to reach users.

However, if a critical issue (using similar criteria to those defined above
for the release candidate window) is found in a release, a patch release
may be warranted. These mechanically work the same as regular releases, but
their announcement is often done via edits to the original release announcement
rather than a standalone announcement.

If non-bugfix changes have been merged after the end of the feature freeze for the release,
preparation of a patch release may require cherry-picking or other manual work
to separate out the fixes for the patch from new features which will wait for the next version.

# Drawbacks

[drawbacks]: #drawbacks

The release cycle described here is by some standards too slow, as it is long
enough between releases that parts of the release process can break or be forgotten.
Some projects release on a monthly or even weekly basis to encourage more automation
around the release cycle and lower the individual risk of each release, as fewer
changes are included and the time before the next release is small.

By other standards, this cycle is too fast, as there may be 4 month periods in which
few or no major changes have been merged. This means some releases may feel insignificant
compared to others, especially when a 'large' and 'small' release both bump version
number in the same way.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

- We could have releases occur without a set schedule. This was used at one point
  in Stan's history, but led to arguments about what was good enough to be released,
  and delays stemming from a desire to get more features merged, since the following
  release could be arbitrarily far away.
- We could have a faster or slower release cycle. A faster cycle would reduce the
  amount of change in each release, but increase the overhead of managing releases
  (assuming more of the existing process was not automated). A slower cycle would
  reduce the overhead, but increase the risk of large changes causing breakages
  that are hard to debug and introduce additional wait time for users to get
  access to new features and bug fixes.
- We could do a mixed release cycle, where we have some cycle defining the maximum
  time between releases (say 6 months), but allow for releases to occur earlier
  if there are sufficient changes merged.

# Prior art

[prior-art]: #prior-art

The existing release process was informally described in [this forum post](https://discourse.mc-stan.org/t/looking-for-a-new-co-release-manager/38396).

The existing release checklist can be seen [here](https://github.com/stan-dev/ci-scripts/blob/ec4e295ccd28ce2f7e3b29315e1ac05ac366a113/release-scripts/checklist.md).

For an example of a faster process, Rust uses a [six-week release cycle](https://blog.rust-lang.org/2014/10/30/Stability/). Note that this
is not exactly comparable, as new features in Rust are often merged but gated behind feature flags until they are later 'stabilized',
and backwards compatibility is not guaranteed for features pre-stablization.

For a slower process, consider Zig, which has had releases between [2 and 8 months apart](https://ziglang.org/download/)
and [are organized around features first](https://ziglang.org/news/what-to-expect-from-release-month/)
and [delayed](https://ziglang.org/news/0.14.0-delayed/) accordingly.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

- Is 4 months the appropriate length of time between releases?
