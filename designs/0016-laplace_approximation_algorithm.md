- Feature Name: Laplace approximation as a new algorithm
- Start Date: 2020-03-08
- RFC PR: 16
- Stan Issue:

# Summary
[summary]: #summary

The proposal is to add a Laplace approximation on the unconstrained space as a
form of approximate inference.

# Motivation
[motivation]: #motivation

Laplace approximations are quick to compute. If a model can be fit with a Laplace
approximation, that will probably be much faster than running full hmc.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The `laplace` algorithm would work by forming a Laplace approximation to the
unconstrained posterior density.

Assuming `u` are the unconstrained variables, `c` are the constrained variables,
and `c = g(u)`, the log density sampled by Stan is:

```
log(p(u)) = log(p(g(u))) + log(det(jac(g, u)))
```

where `jac(g, u)` is the Jacobian of the function `g` at `u`. In the Laplace
approximation, we search for a mode (a maximum) of ```log(p(u))```. Call this
`u_mode`. This is not the same optimization that is done in the `optimizing`
algorithm. That searches for a mode of `log(p(g(u)))` (or the equation above
without the `log(det(jac(g, u)))` term). This is different.

We can form a second order Taylor expansion of `log(p(u))` around `u_mode`:

```
log(p(u)) = log(p(u_mode))
          + gradient(log(p), u_mode) * (u - umode)
	  + 0.5 * (u - u_mode)^T * hessian(log(p), u_mode) * (u - u_mode)
          + O(||u - u_mode||^3)  
```

where `gradient(log(p), u_mode)` is the gradient of `log(p(u))` at `u_mode` and
`hessian(log(p), u_mode)` is the hessian of `log(p(u))` at `u_mode`. Because the
gradient is zero at the mode, the linear term drops out. Ignoring the third
order terms gives us a new distribution `p_approx(u)`:

```
log(p_approx(u)) = K + 0.5 * (u - u_mode)^T * hessian(log(p), u_mode) * (u - u_mode)
```

where K is a constant to make this normalize. `u_approx` (`u` sampled from
`p_approx(u)`) takes the distribution:
```
u_approx ~ N(u_mode, -(hessian(log(p), u_mode))^{-1})
```

Taking draws from `u_approx` gives us draws from the distribution on the
unconstrained space. Once constrained (via the transform `g(u)`), these draws
can be used in the same way that regular draws from the `sampling` algorithm
are used.

The `laplace` algorithm would take in the same arguments as the `optimize`
algorithm plus two additional ones:

```num_samples``` - The number of draws to take from the posterior
approximation. This should be greater than one. (default to 1000)

```add_diag``` - A value to add to the diagonal of the hessian
approximation to fix small non-singularities (defaulting to zero)

The output is printed after the optimimum.

A model can be called by:
```
./model laplace num_samples=100 data file=data.dat
```

or with a small value added to the diagonal:
```
./model laplace num_samples=100 add_diag=1e-10 data file=data.dat
```

The output would mirror the other interfaces and print all the algorithm
specific parameters with two trailing underscores appended to each followed
by all the other arguments.

The three algorithm specific parameters are:
1. ```log_p__``` - The log density of the model itself
2. ```log_g__``` - The log density of the Laplace approximation
3. ```rejected__``` - A boolean data indicating whether it was possible to
evaluate the log density of the model at this parameter value

Reporting both the model and approximate log density allows for importance
sampling diagnostics to be applied to the model.

For instance, the new output might look like:

```
# stan_version_major = 2
...
# Draws from Laplace approximation:
log_p__, log_g__, rejected__, b.1,b.2
-1, -2, 0, 7.66364,5.33463
-2, -3, 0, 7.66367,5.33462
-3, -4, 1, 0, 0
```

There are two additional diagnostics for the `laplace` approximation. The
`log_p__` and `log_q__` outputs can be used to do the Pareto-k
diagnostic from "Pareto Smoothed Importance Sampling" (Vehtari, 2015).

There could also be a diagnostic printout for how many times it is not
possible to evaluate the log density of the model at a certain point from the
approximate posterior (this would indicate the approximation is likely
questionable).

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The implementation of this would borrow heavily from the optimization code. The
difference would be that the Jacobian would be turned on for the optimization.

The Hessians should be computed using finite differences of reverse mode autodiff.
Higher order autodiff isn't possible for general Stan models, but finite differences
of reverse mode autodiff should be more stable than second order finite differences.

# Drawbacks
[drawbacks]: #drawbacks

It is not clear to me how to handle errors evaluating the log density.

There are a few options with various drawbacks:

1. Re-sample a new point in the unconstrained space until one is accepted

With a poorly written model, this may never terminate

2. Quietly reject the sample and print nothing (so it is possible that if someone
requested 200 draws that they only get 150).

This might lead to silent errors if the user is not vigilantly checking the
lengths of their outputs (they may compute incorrect standard errors, etc).

3. Use `rejected__` diagnostic output to indicate a sample was rejected and
print zeros where usually the parameters would be.

If the user does not check the `rejected__` column, then they will be using a
bunch of zeros in their follow-up calculations that could be misleading.

# Prior art
[prior-art]: #prior-art

This is a common Bayesian approximation. It just is not implemented in Stan.
