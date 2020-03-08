- Feature Name: Allow Cmdstan to optionally print out Hessian of posterior when optimization finishes
- Start Date: 2020-03-08
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

When computing a MAP estimate, the Hessian of the log density can be used to construct a normal approximation to the posterior.

# Motivation
[motivation]: #motivation

I have a Stan model that is too slow to practically sample all the time. Because optimization seem to give reasonable results, it would be nice to have the normal approximation to the posterior to give some sense of the uncertainty in the problem as well.

An approximate posterior covariance comes from computing the inverse of the Hessian of log density.

Rstan already supports this via the 'hessian' argument to 'optimizing'.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

I would like to add an argument to the cmdstan interface 'hessian'. So if the model 'diamonds' can be optimized with the command:

```
./diamonds optimize data file=diamonds.data.R
```

I would like to make the version that also computes the hessian:
```
./diamonds optimize hessian=1 data file=diamonds.data.R
```

The option takes two values, 0 (the default) and 1. 0 means don't compute the Hessian. 1 means do compute the Hessian.

Optimizing output currently looks like:
```
# stan_version_major = 2
...
#   refresh = 100 (Default)
lp__,b.1,b.2
3427.64,7.66366,5.33466
```

I would like to print the Hessian of the log density with respect to the model parameters in the constrained space (not the unconstrained space) similarly to how the inverse metric is currently printed at the end of warmup:

```
# stan_version_major = 2
...
#   refresh = 100 (Default)
lp__,b.1,b.2
3427.64,7.66366,5.33466
# Hessian of log density:
# -0.0813676, -0.014598
# -0.014598, -0.112342
```

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

As far as computing the Hessian, because the higher order autodiff doesn't work with the ODE solvers 1D integrator and such, I think we should compute the Hessian with finite differences, and we use the sample finite difference implementation that the test framework does (https://github.com/stan-dev/math/blob/develop/stan/math/prim/functor/finite_diff_hessian_auto.hpp)

# Drawbacks
[drawbacks]: #drawbacks

Printing out the matrix in the comments like this might seem rather crude, but it is the state of the IO

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

Another design would be to print out the Hessian in unconstrained space. This is less interpretable thana constrained space and it would be non-trivial to compute this Hessian into the one in constrained space, so I think the constrained space Hessian should be preferred. We could possibly add another option to Hessian (0, 1, 2) to allow for this functionality.

Rstan actually provides samples from the normal approximation to go along with the normal approximation to the posterior. I think we should not do this because it's not always true that the Hessian is numerically negative definite at the mode. This could be because the MAP estimate has gone to infinity or something (estimating the mode of 8-schools), or just something funny with the numerics. Either way it is quite possible it happens during model development and it would be nice to avoid producing too many errors.

It is fairly straightforward in R and Python to sample from a multivariate normal, and so I think we can reasonably leave this to the user.

# Prior art
[prior-art]: #prior-art

Rstan does a version of this already.
