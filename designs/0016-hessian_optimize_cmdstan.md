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

I have a Stan model that is too slow to sample. I would like to do something
better than optimization. Laplace approximations are a pretty standard way
of doing this.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The `laplace` algorithm would work by forming a Laplace approximation to the
unconstrained posterior density.

Assuming `u` are the unconstrained variables, `c` are the constrained variables,
and `c = g(u)`, the log density sampled by Stan is:

```
log(p(u)) = log(p(g(u))) + log(det(jac(g)))
```

In the Laplace approximation, we search for a mode (a maximum) of
```log(p(u))```. Call this `u_mode`. This is not the same optimization that is
done in the `optimizing` algorithm. That searches for a mode of `log(p(g(u)))`
(or the equation above without the `log(det(jac(g)))` term. These are not the
same optimizations.

We can form a second order Taylor expansion of `log(p(u))` around `u_mode`:

```
log(p(u)) = log(p(u_mode))
          + gradient(log(p), u_mode) * (u - umode)
	  + 0.5 * (u - u_mode)^T * hessian(log(p), u_mode) * (u - u_mode)
          + O(||u - u_mode||^3)  
```

where `gradient(log(p), u)` is the gradient of `log(p)` at `u` and
`hessian(log(p), u)` is the hessian of `log(p)` at `u`. Because the gradient
is zero at the mode, the linear term drops out. Ignoring the third order
terms gives us a new distribution `p_approx(u)`:

```
log(p_approx(u)) = K + 0.5 * (u - u_mode)^T * hessian(log(p), u_mode) * (u - u_mode)
```

where K is a constant to make this normalize. `u_approx` (`u` sampled from
`p_approx(u)`) takes the distribution:
```
u_approx ~ N(u_mode, -(hessian(log(p), u_mode))^{-1})
```

Taking draws from `u_approx` gives us draws from our distribution on Stan's
unconstrained space. Once constrained, these draws can be used in the same
way that regular draws from the `sampling` algorithm are used.

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

or with the diagonal:
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

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The implementation of this would borrow heavily from the optimization code. The
difference would be that the Jacobian would be turned on for the optimization.

We will also need to implement a way of computing Hessians with finite
differences of gradients. Simple finite differences were not sufficiently
accurate for an example I was working on.

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
bunch of zeros in their follow-up calculations that could mislead them.

Similarly to divergent transitions, we can print to the output information about
how many draws were rejected in any case.

In the earlier part of the design document I assume #3 was implemented, but I
think #2 might be better.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

An alternative that seems appealing at first is printing out the mode and
hessian so that it would be possible for people to make their own posterior
draws. This is not reasonable because the conversion from unconstrained to
constrained space is not exposed in all of the interfaces.

# Prior art
[prior-art]: #prior-art

This is a pretty common Bayesian approximation. It just is not implemented in
Stan.
