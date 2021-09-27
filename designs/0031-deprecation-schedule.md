- Feature Name: deprecation_schedule
- Start Date: 2021-09-21
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Introduce a process by which minor features can be removed from the Stan
language following a 1 year (3 minor release) period of deprecation. 'Minor
features' is here broadly defined to mean things that are one-line updates, such
as replacing `<-` with `=` or renaming a variable.

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
`array[]` syntax can be automatically produced by out pretty-printer, and it is
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
Here, 'minor change' is restricted to be changes which can be done automatically
through the use of the stanc3 canonicalizer, or a user-driven find and replace
operation. Major changes, such the interface changes to the differential
equation solvers, may be deprecated in minor versions but will not be removed
prior to a version 3.0.0.

A minor feature must be deprecated for a minimum of 3 minor versions
(approximately 1 year on the current release schedule) before removal. The exact
timeline for a feature's removal will be decided during the development which
would mark it as deprecated.

A minor feature is deprecated and a candidate for future removal when:
1. stanc emits a compile-time warning with the following 3 parts:
  1. A description of the deprecated feature, such as "Use of <- for assignment
      is deprecated".
  2. An _action_ the user should take, such as "Use = instead."
  3. A timeline which includes a date or version after which this feature is
     slated for removal, for example "This deprecation will expire in Stan
     version 2.31.0 (expected Sept. 2022)".
2. It has been added to the [documentation on
   deprecation](https://mc-stan.org/docs/reference-manual/deprecated-features-appendix.html)
   with the same 3 pieces of information, and additional information as needed
   (such as any of: reasoning for removal, advantages of new behavior, ongoing
   related changes, etc).
3. Examples in the documentation have been updated to remove any examples of the
   deprecated syntax, except for those referring to its deprecation. This change
   may lag behind bullets 1 and 2, but must occur before the removal.

Our goal is to only deprecate a feature when doing so provides a tangible
benefit to users, such as improving error messaging or allowing new features to
be added to the language while keeping a low maintenance burden. Changes should
never take users (even those with many or large models) long to adjust to, and
as few such changes should be made in each version as is reasonable.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

## Developers
From a developer standpoint, this policy is rather straightforward. When a
change is made, it should identify any deprecation candidates: new keywords that
must be implemented (thus 'deprecating' the use of that word as a identifier),
new syntax which supsercedes a prior syntax, (such as `=` or `array[]`), or a
similar change. If supporting both the new and old way of doing things requires
a 'hack' or difficult to maintain code, this is a prime candidate for
deprecation.

>Current examples include the use of 'partial keywords' like offset,
>which are not reserved words but act like them in some contexts, or multiple
>syntaxes which lead to parsing difficulties, like the new array syntax. We would
>like to not only improve the error messaging and implementation of these current
>features, but also avoid introducing new issues of this variety in the long term.

Once it has been decided to deprecate a feature, the lexer, parser, or
typechecker (whichever is most apropriate) should be updated to emit a
compile-time warning notifying the user. This must contain the above 3 criteria:
1. What is deprecated
2. How to adjust your code
3. When you need to adjust it by.

The final bullet point should be decided during the review process with 3
versions as a minimum. Many changes, such as reserving a new keyword, will not
require longer periods, but syntax changes which the user may need time to
adjust to could require longer time frames.

This information must also be added to the documentation in the accompanying PR
to the change.

## Code reviewers
From a code reviewer standpoint, it is important to ask the following questions:
1. Is this deprecation tied to a useful feature or noticeable improvement to the
   underyling code (not just 'for the sake of it')?
2. Does the new warning meet the criteria above and explain itself clearly?
3. Is there a simple (preferably automated) way for users to accommodate this
   change, e.g. through the `print-canonical` flag to stanc3 or a
   find-and-replace feature of their text editor.
4. Is the removal timeline appropriate for this change.

## Releases
Finally, during the release cycle an additional bullet point should be added to
the release checklist to ensure that the deprecations slated for removal in the
coming version have been properly handled. To accommodate this, the documentation
page on deprecations should be sorted/categorized by removal version.


# Drawbacks
[drawbacks]: #drawbacks

Drawbacks to this are rather obvious - backwards compatibility is certainly a
virtue, and any breaking change will lead to some headaches for a portion of the
user base, no matter how small. In the limit, we certainly want to avoid any
large enough change that users prefer not to update (a core reason these changes
should be tied to improvements in the language, not just for their own sake) and
any changes which require dedicated rewriting or rethinking of models.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

This design allows for us to care for the long term health of the Stan language
and codebase while clearly communicating our intent to users. Small changes can
be made to make the development of new features easier without "sneaking up on"
anyone or breaking things willy-nilly.

There are two main alternatives to this proposal:
1. The first is to stick strictly to the semantic versioning standards, and make
   a strong push toward a Stan version 3.0 which makes backwards incompatible
   changes.

   Unless we attempt to systematically release major versions with some
   regularity, we still end up with the same problem of these tiny issues
   accumulating in the meantime. Additionally, saving all such minor changes for
   a major version bump dramatically increases the friction for updating. While
   some may find it preferable to have to update their models only once, the
   small requirement of (at most) 1-2 changes per version is likely preferable
   to the many required changes a major version would bring.

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
   time - syntax highlighting in particular suffers:
   ```stan
       real<lower=0> x; // notice lower is highlighted
       real<offset=0> y; // notice offset is not
       int offset; // this is (partially) the reason why
   ```

# Prior art
[prior-art]: #prior-art

- The original inspiration for this schedule comes from the Python library
  NumPy, with their deprecation policy laid out in
  [NEP-23](https://numpy.org/neps/nep-0023-backwards-compatibility.html#implementing-deprecations-and-removals)
  The NumPy project provides a similar example of a large open-source code base
  whose minor version number has now exceeded 20 (meaning a large number of
  changes since the last 'breaking'/major version).
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
- https://semver.org/ - the description of proper 'semantic versioning'. In the
  strictest interpretation, Stan has already deviated from this scheme before,
  but it is a common understanding of the major.minor.patch versioning.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Above I set the term of deprecations at 3 minor versions/1 year. This may be
  too long for some features and too short for others, and is worth discussing.
- We have many existing deprecations which predate this proposed policy. How
  they should be handled or removed is not explicitly covered; the easiest path
  is to consider the first version after this policy is enacted to be their
  'deprecation version', and remove them 3 minor versions later.
- This is independent of questions about larger features like the ODE solver
  changes and the potential of a Stan version 3.0, but these should be
  considered when thinking of the long term health of the project as well.
- At the moment, we tend to not backport bug fixes if we fix them in the next
  minor version. We may want to consider this or some other sort of long-term
  support schedule if we begin introducing any sort of breaking changes.
