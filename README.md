# Stan Design Documents Repository

This repository is where the Stan community puts design documents and functional specifications that describe major changes to our code base. These documents cover many aspects of the Stan ecosystem including the Stan language, interface changes, algorithms, and implementation details.

We welcome proposals and discussion from everyone in the community.

Our process for accepting proposals takes inspiration from [IETF Internet-Drafts](https://www.ietf.org/standards/ids/). We want the process to be lightweight and result in accepting documents that have consensus from the community at the time of approval.


## Submit a Design Document

Anyone can propose a design document. Please write a design document roughly following [the template](0000-template.md) and submit a pull request. The author of the specification has the flexibility to drive the process to getting the document approved. We suggest discussing the proposal in a pull request or on [Discourse](https://discourse.mc-stan.org).

Design documents rarely go through the process unchanged, especially as alternatives and drawbacks are identified. Proposals can go through edits for months as we discuss major changes to Stan. Everyone in the community is welcome to make comments (relevant to the proposal). 

Proposals are accepted and merged into this repository when there is consensus from the community. In practice, this means giving enough time for members of the community to review/comment/request changes on the proposal. Proposals can be accepted if at least one other (non-author) Stan developer endorses the final draft of the design document and there are no denials. 

Stan Developers: please feel free to merge PRs into this repository when they have reached this point. Acceptance into this repository is non-binding; at the time of the merge, we, the community, think it's a good idea.


# Design Review

## When is design necessary?

Most changes can be implemented and reviewed via the [normal pull request workflow](https://github.com/stan-dev/math/wiki/Developer-Doc#pull-requests). Some changes are substantial enough that we ask that these be put through a design review for approval, similar to how an implementation is approved in a pull request.


## What is a design?

A major change to Stan will include at least two designs. The first is a functional specification that defines user-facing changes; an example here might be new proposed syntax for the Stan language, or an alternative architecture around how the interfaces communicate with a Stan model. The functional specification should be specific enough that a user/client would understand the impact of the change and start out summarizing the proposed change at a very high level in a sentence or two, identifying all of the clients, laying out an ontology of objects the change traffics in from the perspective of these clients, and then highlighting any additional concerns.

Once a functional spec has been agreed upon, we next need a design codified as a technical specification that defines how the functional spec will be implemented. The technical specification needs to be specific enough that it can be approved as a plan for implementation. These documents should not include every last detail of an implementation---for example, rarely will code other than function or class signatures be appropriate in either a functional or technical specification. They should include text to support the design and component interaction diagrams such as UML where appropriate.

[This design](https://github.com/stan-dev/design-docs/blob/master/designs/0001-logger-io.md) has a functional spec in the first 5 or 6 pages and then a fairly detailed technical spec following, and should be used as an example.


For user-facing designs, we want to give them a lot of exposure to the world before we implement something, as we rarely take away features and want to maintain backwards compatibility for as long as possible (possibly forever). Once it's in, it's in, and this puts a high bar on new additions and we want to make sure everyone has a chance to look them over.

Even if a change is not user-facing, good software design and architecture goes a long way towards long-term sustainability of a project and is especially important for open-source projects. Software engineering is primarily about how to break up your ideas into easily digestible chunks for communication to others, including yourself in the future.  Computers are not the audience for design documents, people are.

Design review ensures that the high level technical choices are simple, communicable, and robust enough to warrant a lower level implementation.  These design criteria must be applied to the (concepts and models)[https://medium.com/all-things-product-management/conceptual-debt-is-worse-than-technical-debt-5b65a910fd46] used to represent the design components and their interconnections.  Time spent hashing out the design before coding takes place is worth a decent multiple of the time spent after the design has been committed to code. Getting broad community involvement in brainstorming and designs helps remove the ego from the process and allows us to make decisions quickly and reliably.

## The life cycle of a major change

Designs and issues vary in a multitude of details concerning how they are staged.  A successful life cycle for a major issue might include:

* a brainstorming session on Discourse where the underlying problem is raised and broad, preliminary ideas are proposed and discussed,
* one or more members of the community turning these ideas into a design proposal, typically on a shared Wiki page,
* the accepted design and accompanying discussion being summarized and specified at greater detail a GitHub issue, which may host its own lower-level discussion of technical issues,
* the design being implemented on a branch from the development branch of the relevant repositories with sufficient unit test coverage and documentation to release the feature,
* a pull request being made for the issue and goes through normal code review on GitHub, returning to the previous step until it is approved through code review
* the issue being merged into the development branches of the relevant repositories, which will include the feature in the next release.

An approved design does not assign anyone in particular to work on the design, but one should create an issue linking or incorporating the design document.

## What requires a design review?

What exactly constitutes a truly major change is evolving based on community norms and varies depending on what part of the ecosystem you are proposing to change, but may include:
semantic or syntactic changes to the language that is not a bugfix,
adding or removing language features,
changing the interfaces impacting multiple modules, such as math, algorithms, services, and interfaces.

In general, thinking “oh, this might include a large refactor” or “this is really exciting” or “this might not work everywhere” are good indicators you should seek design approval.

Some changes that definitely do not require a design review:
new functionality that closely follows existing patterns, such as adding new functions to the math library and language,
additions that strictly improve objective quality criteria, such as false-positive warning removal, performance improvements, better test coverage, more informative error handling,
bug fixes that touch only a few files.

## Before submitting a design for review

It is generally a good idea to pursue feedback from other project developers beforehand.  The easiest way to do this is in a Discourse post that brings up the problem or issue and perhaps a rough outline of proposed solution at a high level and solicits further ideas and brainstorming. As a rule of thumb, receiving encouraging feedback from longstanding project developers on such a thread is a good indication that the design or issue is worth pursuing.

## Conducting design reviews

Anyone involved may schedule meetings to discuss the design with interested parties over a video chat. A design may be postponed if we don’t want to evaluate the proposal immediately for reasons such as not being urgent or depending on other designs to be completed.  Postponing a design indicates that at least someone thinks we might reasonably consider making the change in the future---otherwise it would just be closed. To close a design request for comments, a reviewer should describe the reasoning in the relevant discourse post.

If the motivation and the design are reasonably sound, a reviewer should interact with the proposer and community to give constructive feedback if the reviewer thinks the design could be accepted in the near term.

## Implementing an accepted design

No one in particular is obligated to implement an accepted design.  There will be an associated issue in the relevant repository that keeps track of anyone working on it. If you see an accepted design and want to work on it, post in that issue and tag the relevant parties.

