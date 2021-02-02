- Feature Name: ode-adjoint
- Start Date: 2021-02-02
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Ordinary differential equations (ODEs) are currently severly costly to
fit in Stan for larger systems. This is due to the multiplicative
scaling of the required computing ressources with the ODE system size
N and the number of parameters M defining the ODE. Currently we
implement in Stan the so-called forward-mode ODE method in order to
obtain in addition to the solution of the ODE the sensitivities of the
ODE. The cost of this method scales as 

$$ N * M . $$

The computational cost of the adjoint method is much more favorable
in comparison which is

$$ 2 * N + M .$$

The advantage of the adjoint methods shows in particular whenever the
number of parameters are relatively large in comparison to the number
of states. Most importantly, the computational cost grows only
linearly in the number of states and parameters (while forward grows
exponentially). Thus, this method can scale to much larger problems
without exponentially increasing computational cost.

# Motivation
[motivation]: #motivation

Stan is currently practically limited to solve problems with ODEs
which are small in the number of states and parameters. If either of
them gets large, the computational cost explodes quickly. With the
adjoint ODE solving method Stan will be able to scale to much larger
problems involving more states and more parameters. Examples are large
pharmacokinetic / pharmacodynamic systems or physiological based
pharmacokinetic models or bigger susceptible infectious & removed
models. As the adjoint ODE method will grow the computational cost
only linearly with states and parameters, the modelers can more freely
increase the complexity of the ODE model without having to worry too
much about infeasible inference times.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The new solver `ode_adjoint` will follow in it's design the variadic
ODE functions. As the new solver is numerically more involved (see
reference level) there are merely more tuning parameters needed for
the solver. The actual impementation will be provided by the CVODES
package which we already include in Stan.

From a more internal stan math perspective, the key difference to the
existing forward mode solvers will be that the gradients are not any
more precomputed. Instead, during the forward sweep of reverse mode
autodiff, the ODE is solved first for the N states (without any
sensitivities). When reverse mode AD then performs the backward sweep,
the adjoints of the input operands are directly computed given the
input adjoints. This involves a backward solve in time with N states
and solving M quadrature problems in addition.

The numerical complexity is higher for the adjoint method in
comparison to the forward method. While most of the complexity is
handled by CVODES, the numerical procedure seems to require more
knowledge about the tuning parameters. At least at the moment it
appears not possible to make an easy to use interface of this
functionality available without most tuning parameters. We need to
first collect some experience before a simpler version can be made
available (if that is feasible at all). The tuning parameters exposed
as proposed are:

- absolute & relative tolerance forward solve; absolute tolerance
  should be a vector of length N, the number of states
- absolute & relative tolerance backward solve
- absolute & relative tolerance quadrature problem
- forward solver: bdf-dense / bdf-iterated / adams - 1 / 2 / 3
- backward solver: bdf-dense / bdf-iterated / adams - 1 / 2 / 3
- checkpointing: number of checkpoints every X steps
- checkpointing: hermite or polynomial approximation - 1 / 2

During an experimental phase of this feature we can hopefully learn
which of these are relevant and which can be dropped for a final
release of the `ode_adjoint` function.

**Leaving the template text here for now**

Explain the proposal as if it was already included in the project and you were teaching it to another Stan programmer in the manual. That generally means:

- Introducing new named concepts.
- Explaining the feature largely in terms of examples.
- Explaining how Stan programmers should *think* about the feature, and how it should impact the way they use the relevant package. It should explain the impact as concretely as possible.
- If applicable, provide sample error messages, deprecation warnings, or migration guidance.
- If applicable, describe the differences between teaching this to existing Stan programmers and new Stan programmers.

For implementation-oriented RFCs (e.g. for compiler internals), this section should focus on how compiler contributors should think about the change, and give examples of its concrete impact. For policy RFCs, this section should provide an example-driven introduction to the policy, and explain its impact in concrete terms.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

Here I would like to document exactly the math of the approach using
the notation of the CVODES manual.

TODO !!!

This is the technical portion of the RFC. Explain the design in sufficient detail that:

- Its interaction with other features is clear.
- It is reasonably clear how the feature would be implemented.
- Corner cases are dissected by example.

The section should return to the examples given in the previous section, and explain more fully how the detailed proposal makes those examples work.

# Drawbacks
[drawbacks]: #drawbacks

It's some work to be done. Other than that there are no alternatives
to my knowledge to get large ODE systems working in Stan. What we are
missing out for now is to exploit the sparsity structure of the
ODE. This would allow for more efficient solvers and even larger
systems, but this is not possible at the moment to figure out
structurally the inter-dependencies of inputs and outputs.

# TODO: Update the rest

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?
- What other designs have been considered and what is the rationale for not choosing them?
- What is the impact of not doing this?

# Prior art
[prior-art]: #prior-art

Discuss prior art, both the good and the bad, in relation to this proposal.
A few examples of what this can include are:

- For language, library, tools, and compiler proposals: Does this feature exist in other programming languages and what experience have their community had?
- For community proposals: Is this done by some other community and what were their experiences with it?
- For other teams: What lessons can we learn from what other communities have done here?
- Papers: Are there any published papers or great posts that discuss this? If you have some relevant papers to refer to, this can serve as a more detailed theoretical background.

This section is intended to encourage you as an author to think about the lessons from other languages, provide readers of your RFC with a fuller picture.
If there is no prior art, that is fine - your ideas are interesting to us whether they are brand new or if it is an adaptation from other languages.

Note that while precedent set by other languages is some motivation, it does not on its own motivate an RFC.
Please also take into consideration that rust sometimes intentionally diverges from common language features.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?
- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?
