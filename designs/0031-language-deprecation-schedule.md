- Feature Name: language\_deprecation\_schedule
- Start Date: 2021-09-21
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Introduce a process by which minor features can be removed from the Stan
language following a 1 year (3 minor release) period of deprecation. "Minor
features" is here broadly defined to mean syntactic changes that are one-line
updates, such as replacing `<-` with `=` or renaming a variable/function.

# Motivation
[motivation]: #motivation

Any large project accumulates many changes over time. While backwards
compatibility is a strength of Stan, there are many instances where a small, yet
breaking, change can dramatically improve code quality or maintainability in the
long term. Some examples of this include adding keywords or removing outdated
syntax which complicate parsing. Many of these features are _already_ marked as
deprecated, but have been left for major version change to actually remove. This
Stan 3.0 version seems to consistently be just over the horizon, and as a result
some features, like the above-mentioned `<-` operator, have been deprecated for
5+ years. Having the ability to remove or correct these tiny features allows the
growth of Stan as a language to continue without an ever-increasing amount of
difficulty.

This is not a theoretical problem. Consider [this
issue](https://github.com/stan-dev/stanc3/issues/953) with the parser or [this
discussion](https://discourse.mc-stan.org/t/list-of-stanc3-new-reserved-keywords/12948)
of new keywords.

These are issues that stem from either the inability to make minor changes to
the language, or from the current lack of process to introduce these changes.
The solution to both of them is rather simple from a user perspective - the new
`array[]` syntax can be automatically produced by our pretty-printer, and it is
easy to rename a variable, but this must be clearly and consistently
communicated to our users.

Finally, this process provides an opportunity for feedback on changes. The
deprecation period prior to removal is not only to let users know of our
intentions, but also to let them tell us if our intentions need to be rethought.
By communicating the changes and putting deadlines on them, we create a sort of
community review period during which we can recieve feedback and course-correct
if we have made a poor choice.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Deprecated minor features may be removed from Stan during minor version changes.
Here, "minor change" is restricted to be changes which can be done automatically
through the use of the stanc3 canonicalizer, or a user-driven find and replace
operation. By their very nature, minor changes are syntactic. This is
in contrast to "major changes", which are by their nature semantic, and require
human-in-the-loop reasoning to accommodate. Major changes, such the interface
changes to the differential equation solvers, may be announced via deprecation
warnings in minor versions, but will not be implemented/removed prior to a
version 3.0.0.

A minor feature must be deprecated for one year (approximately three minor
versions on the current release schedule) before removal.

A minor feature is deprecated and a candidate for future removal when:
1. stanc emits a compile-time warning with the following 3 parts:
    1. A description of the deprecated feature, such as "Use of <- for assignment
       is deprecated".
    2. An _action_ the user should take, such as "Use = instead". If stanc3 can
       automate this for them, we should call that out, leading to a full
       message like
       "Use = instead of <- for assignment;  this can be
       automatically changed by running:
       stanc3 --print-canonical <stan-program-file>"
    3. A timeline which includes a date or version after which this feature is
       slated for removal, for example "This deprecation will expire in Stan
       version 2.31.0 (expected Sept. 2022)".
2. It has been added to the [documentation on
   deprecation](https://mc-stan.org/docs/reference-manual/deprecated-features-appendix.html)
   with the same 3 pieces of information, and additional information as needed
   (e.g. reasons for removal, advantages of new behavior, ongoing
   related changes, etc.).
3. Examples in the documentation have been updated to remove any examples of the
   deprecated syntax, except for those referring to its deprecation.

Our goal is to only deprecate a feature when doing so provides a tangible
benefit to users, such as improving error messaging, or drastically simplifies
the developer experience by allowing new features while keeping a low
maintenance burden. Changes should never take users (even those with many or
large  models) long to adjust to.


For any minor features which have been deprecated prior to this proposal's
acceptance, we will consider the first version after this policy is enacted to
be their "deprecation version" after updating the documentation and warnings
accordingly, and remove them 3 minor versions later.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

## Developers
From a developer standpoint, this policy is rather straightforward. When a
change is made, it should identify any deprecation candidates: new keywords that
must be implemented (thus deprecating the use of that word as a identifier),
new syntax which supersedes prior syntax, (such as `=` or `array[]`), or a
similar _syntax-level_ change. If supporting both the new and old way of doing
things requires a "hack" or difficult to maintain code, it is a prime
candidate for this removal process in minor versions. If a change meaningfully
alters the semantics of the language, it must wait until a major version bump to
occur (currently this would mean Stan version 3.0.0), even if the deprecation is
announced during a minor version update.

- Current examples include the use of partial keywords like "offset",
  which are not reserved words but act like them in some contexts, or multiple
  syntaxes which lead to parsing difficulties, like the new array syntax. We would
  like to not only improve the error messaging and implementation of these current
  features, but also avoid introducing new issues of this variety in the long
  term. These can be changed in minor versions following this process.

- Current non-examples include the ODE solver interface changes, which requires
  changes to the user-defined function defining the ODE. These should wait for
  major versions.

Once it has been decided to deprecate a feature, the lexer, parser, or
type checker (whichever is most appropriate) should be updated to emit a
compile-time warning notifying the user. The warning must contain the three
pieces of information specified above:
1. What is deprecated
2. How to adjust code to replace the deprecated feature
3. Which version the deprecated feature will be removed in

The final piece of information should correspond to the version released
approximately one year following the version which first emits the warning.
Given the current Stan release cycle, this time frame should mean three versions
later. For example, a deprecation added in version 2.28.0 should expire in
2.31.0. Note that deprecations should only be added or removed in minor
versions, not bug fix versions.

These three pieces of information must also be added to the documentation in the
accompanying PR to the change.

Finally, developers may weigh in on how the language implementation can be
simplified after the removal of the deprecated feature as part of the text of the pull
request.

## Code reviewers
From a code reviewer standpoint, it is important to ask the following questions.
1. Is this deprecation tied to a useful feature or noticeable improvement to the
   underyling code?
2. Does the new warning contain the required information listed above and
   explain itself clearly?
3. Is there a simple (preferably automated) way for users to accommodate this
   change (e.g., through the `print-canonical` flag to stanc3 or a
   find-and-replace feature of their text editor)?


## Releases
During the release cycle a bullet point should be added to the release
checklist to ensure that the deprecations slated for removal in the coming
version have been properly handled. To accommodate this, the documentation page
on deprecations should be sorted/categorized by removal version.

The release notes should contain a section on **Deprecations** and
**Breaking Changes** (alt. **Removed Features**) for each version. This section
should duplicate the information on the what and how of the change from the
error message and documentation.


# Drawbacks
[drawbacks]: #drawbacks

Backwards compatibility is certainly a virtue, and any breaking change will lead
to some headaches for a portion of the user base, no matter how small.

At the most extreme end of drawbacks, it is possible for changes in a language
to be so large that users prefer not to update. This proposal was crafted with a
limited scope in particular to attempt to avoid this concern.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

 Deprecating features empowers developers to improve the language, without
 introducing breaking changes that sneak up on users.

There are two main alternatives to this proposal:
1. The first is to stick strictly to the semantic versioning standards, and make
   a strong push toward a Stan version 3.0 which makes backwards incompatible
   changes.

   Unless we attempt to systematically release major versions with some
   regularity, we still end up with the same problem of these tiny issues
   accumulating in the meantime. Additionally, saving all such minor changes for
   a major version bump dramatically increases the friction for updating. While
   some may find it preferable to have to update their models only once, the
   smaller and more frequent changes are likely preferable to the many required
   changes intermittent major versions bring.

2. Do not allow the deprecation of features. If we do not plan on actually
   removing deprecations, emitting warnings to the user is simply annoying and
   nonproductive.

   We instead decide to strongly commit to backwards compatibility in all
   cases - no new language keywords, the preservation of current syntax ad
   infinitum, etc. This has benefits to the end user - a Stan program written
   today would still work (assuming we were actually able to meet this high
   standard) on a version of Stan released years from now. The downside is that
   the codebase would bloat over time, and we will run into more and more
   instances where the correct behavior or error message is indiscernible in
   practice. Tools which build around Stan in particular have trouble with our
   treatment of some things as valid identifiers and valid keywords at the same
   time - syntax highlighting especially suffers:
   ```stan
       real<lower=0> x; // notice lower is highlighted
       real<offset=0> y; // notice offset is not
       int offset; // this is (partially) the reason why
   ```

# Prior art
[prior-art]: #prior-art

- The original inspiration for this schedule comes from the Python library
  NumPy, with their deprecation policy laid out in
  [NEP-23](https://numpy.org/neps/nep-0023-backwards-compatibility.html#implementing-deprecations-and-removals).
  The NumPy project provides a similar example of a large open-source code base
  whose minor version number has now exceeded 20 (meaning a large number of
  changes since the last "breaking"/major version).
- Python itself defines a similar policy in
  [PEP-387](https://www.python.org/dev/peps/pep-0387/) which requires warnings
  emitted for 2 minor versions or 1 major version (e.g, a feature deprecated in
  3.10 could be removed in 3.12 **or** 4.0)
- The Java language clarified its [deprecation
  policy](https://docs.oracle.com/javase/9/core/enhanced-deprecation1.htm#JSCOR-GUID-23B13A9E-2727-42DC-B03A-E374B3C4CE96)
  in Java 9 (which is technically a minor version, 1.9, for the JDK). The main
  motivation for clarification was the response of users being unsure if a
  deprecated feature would ever actually be removed. There was a
  [study](https://doi.org/10.1007/S10664-019-09713-W) of this change published
  in 2019. It contains the following relevant passage and some interesting
  discussion of user reactions to a deprecation warning.
  > By not removing deprecated features from an API after a transition period
  > has passed, API producers and the Java JDK developers themselves have
  > cheapened the meaning of deprecation.
- https://semver.org/ - the description of proper "semantic versioning". In the
  strictest interpretation, Stan already deviates from this scheme with some
  regularity, but it is a common understanding of the major.minor.patch
  versioning.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Above I set the term of deprecations at 3 minor versions/1 year. This may be
  too long for some features and too short for others, and is worth discussing.
- This proposal is independent of questions about larger features like the ODE solver
  changes and the when and what of a Stan version 3.0. How to handle the "major"
  or semantic changes to the language is not resolved by this proposal, aside
  from the remark that they require major version bumps.
- At the moment, we tend to not backport bug fixes if we fix them in the next
  minor version. We may want to consider this or some other sort of long-term
  support schedule if we begin introducing any sort of breaking changes.
