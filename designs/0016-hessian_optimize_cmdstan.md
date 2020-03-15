- Feature Name: Allow Cmdstan to optionally print out draws from Laplace approximation of posterior when optimizing
- Start Date: 2020-03-08
- RFC PR: 16
- Stan Issue:

# Summary
[summary]: #summary

When computing a MAP estimate, the Hessian of the log density can be used to construct a normal approximation to the posterior.

# Motivation
[motivation]: #motivation

I have a Stan model that is too slow to practically sample all the time. Because optimization seem to give reasonable results, it would be nice to have the normal approximation to the posterior to give some sense of the uncertainty in the problem as well.

An approximate posterior covariance comes from computing the inverse of the Hessian of the negative log density.

Rstan already supports this via the 'hessian' argument to 'optimizing'.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

This adds two arguments to the cmdstan interface.

```laplace_draws``` - The number of draws to take from the posterior approximation. By default, this is zero, and no laplace approximation is done

```laplace_diag_shift``` - A value to add to the diagonal of the hessian approximation to fix small non-singularities (defaulting to zero)

The output is printed after the optimimum.

A model can be called by:
```
./model optimize laplace_draws=100 data file=data.dat
```

or with the diagonal shift:
```
./model optimize laplace_draws=100 laplace_diag_shift=1e-10 data file=data.dat
```

Optimizing output currently looks like:
```
# stan_version_major = 2
...
#   refresh = 100 (Default)
lp__,b.1,b.2
3427.64,7.66366,5.33466
```

The new output would look like:

```
# stan_version_major = 2
...
#   refresh = 100 (Default)
lp__,b.1,b.2
3427.64,7.66366,5.33466
# Draws from Laplace approximation:
b.1,b.2
7.66364,5.33463
7.66367,5.33462
```

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

As far as computing the Hessian, because the higher order autodiff doesn't work with the ODE solvers 1D integrator and such, I think we should compute the Hessian with finite differences, and we use the sample finite difference implementation that the test framework does (https://github.com/stan-dev/math/blob/develop/stan/math/prim/functor/finite_diff_hessian_auto.hpp)

# Drawbacks
[drawbacks]: #drawbacks

Providing draws instead of the Laplace approximation itself is rather inefficient, but it is the easiest thing to code.

We also have to deal with possible singular Hessians. This is why I also added the laplace_diag_shift to overcome these. They'll probably be quite common, especially with the Hessians computed with finite differences.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

Another design would be the print the Hessian on the unconstrained space and let users handle the sampling and the parameter transformation. The issue here is there is no good way for users to do these parameter transformations outside of certain interfaces (at least Rstan, maybe PyStan).

Another design would be to print a Hessian on the constrained space and let users handle the sampling. In this case users would also be expected to handle the constraints, and I don't know how that would work practically rejection sampling maybe?)

# Prior art
[prior-art]: #prior-art

Rstan does a version of this already.
