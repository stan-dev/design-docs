- Feature Name: Experimental or Unsupported Folders
- Start Date: 2021-02-10

# Summary
[summary]: #summary

This proposes adding `experimental` and `unsupported` folders to all of the projects in `stan-dev`.

# Motivation
[motivation]: #motivation

There have been several instances in the past where researchers have come to Stan with a proposal that was close, but not quite there and after some time these ended up not making it into Stan. While Stan's focus is mostly on end users of the language, the Stan ecosystem is a full stack of tools for developing algorithms which developers can utilize for building out their own projects and experiments. By creating an `unsupported` folder, Stan can accept projects that are good, but the Stan development team does not have the resources to maintain. Similarly, an `experimental` folder will allow projects which are either Unsupported or "almost there" to reach a larger audience.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The `unsupported` folder inside of a Stan project will contain projects that are fully compatiable with the Stan ecosystem but the Stan development team does not have time to maintain.

The `experimental` folder inside of a Stan project can contain projects that work for a subset of Stan but need more research before reaching a more general audience. This could be, for instance, an algorithm used in MCMC sampling that has a full implimentation, but is missing diagnostics that end users would need to assess their model using this algorithm.

Project maintainers can choose to have one or both of these folders in their project and when including them should give a brief description of what is expected for projects to be included.

I don't think it's wise to have an explicit checklist of what needs to happen for each of `unsupported` and `experimental` as maintainers for particular project will have the most knowledge to make these decisions. In general, proposals should first happen on a project's issue tracker where maintainers can then decide whether the project needs an RFC, general discussion, etc.

For users to access features in either folder, the stanc3 can have flags such as `--experimental-foo` or `--unsupported-doo` that includes the appropriate code to access the feature.


One recent example of where this could be used is for the [`laplace-approximations`](https://arxiv.org/pdf/2004.12550.pdf) where the algorithm has a full implimentation, but does not generalize to arbitrary likelihoods and does not yet have diagnostics for inferring bias in the estimates. Having this project in an `experimental` folder would allow the compiler to create a flag `--experimental-laplace` that includes the laplace approximation. This would make is easier for researchers to experiment with diagnostics for laplace and for users to test it out and give feedback.


# Drawbacks
[drawbacks]: #drawbacks

This could be a footgun! It many ways it's good that Stan in general is rather conservative with what it allows users to access from the project. Having unsupported and experimental folders could lead to projects landing there and never making it fully into Stan. Having a high bar for inclusing could give those projects that would normally go into `experimental/unsupported` the extra oomph to get into Stan itself.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The main alternative is to keep our current system, which is fine though a bit too conservative for some projects to be accepted.

# Prior art
[prior-art]: #prior-art

The main prior art for this is Eigen's [unsupported](https://gitlab.com/libeigen/eigen/-/tree/master/unsupported) folder which contains parts of Eigen that are not supported by the main development team.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Which projects should support this?
- Should projects be allowed to go into experimental folders without a plan to full go into Stan? Perhaps proposals to enter the experimental folder should list out what would need to be accomplished for the project to go fully into Stan.
