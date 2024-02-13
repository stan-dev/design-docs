- Feature Name: `jacobian` target
- Start Date: 01-25-2024

# Summary
[summary]: #summary

This design doc proposes adding a `jacobian` target and `*_jacobian` user defined functions. The `jacobian` target will be accessible directly in `transformed parameters` and the new `*_jacobian` functions.


The examples below show an example use case.

```stan
functions {
  real upper_bound_jacobian(real x, real upper_bound) {
    jacobian += x;
    return upper_bound - exp(x);
  }
}
data {
 real ub;
}
parameters {
 // User defined constraint
 real b_raw;
}
transformed paramters {
  real b = upper_bound_jacobian(b_raw, ub);
}
```

# Motivation
[motivation]: #motivation

Given a function $c$ mapping unconstrained parameters in $Y$ to constrained parameters in $X$, probability density function $\pi$, and a Jacobian determinant function over the constrained space $J(c(y))$, Stan calculates the log transformed density function [1]

$$
\pi^*(y) = \pi\left( c\left(y\right) \right) J_c\left(y\right)
$$

$$
\log\left(\pi^*(y)\right) = \log\left(\pi\left( c\left(y\right) \right)\right) + \log\left(J_c\left(y\right)\right)
$$

The Stan languages has built in constraints constraints such as `lower`, `upper`, `ordered`, etc. to handle $ \log(J_c(y))$. 
A variable (unconstraining) transform is a surjective function $f:\mathcal{X} \rightarrow \mathbb{R}^N$ from a constrained subset $\mathcal{X} \subseteq \mathbb{R}^M$ onto the full space $\mathbb{R}^N$.
The inverse transform $f^{-1}$ maps from the unconstrained space to the constrained space. 
Let $J$ be the Jacobian of $f^{-1}$ so that $J(x) = (\nabla f^{-1})(x).$ and $|J(x)|$ is its absolute Jacobian determinant. A transform in Stan specifies 

- $f(y)$ The unconstraining transform
- $f^{-1}\left(y\right)$ The inverse unconstraining transform
- $\log |J(y)|$ The log absolute Jacobian determinant function for $f^{-1}$ chosen such that the resulting distribution over the constrained variables is uniform
- $V(y)$ that tests that $x \in \mathcal{X}$ (i.e., that $x$ satisfies the constraint defining $\mathcal{X}$).

Having the Stan language define types for transforms from the unconstrained to constrained space allows users to focus on modeling in the constrained space while algorithm developers focus on developing algorithms in the unconstrained space. 
This is very nice for both parties since it is both of their preferred spaces to work in.

Most of the time this encapsulation is very good. 
The main issue is that Stan users either have to write code that either only uses Stan's built-in transforms to stay in the constrained space or have to always have the jacobian calcuations enabled while working in the constrained space.




# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The following section is a draft of the docs for the new constraint and `jacobian` keyword.

### Using the jacobian Keyword

The `jacobian` keyword is introduced within the `transformed parameters` block and the functions ending in `_jacobian` to allow the Jacobian accumulator to be incremented by the log absolute determinant of the Jacobian of the constraining transform. 
This keyword behaves similarly to the `target` keyword, allowing users to account for the change of variables in the probability density function. 
The key difference between the two is that `jacobian` will only be accumulated into for algorithms that request it. Algorithms such as maximum likelihood would request the jacobian to not be accumulated. 
The `jacobian` keyword is available only in the `transformed parameters` block and within functions ending in `_jacobian`.


### Example Usage

The following stan program defines an `upper_bound_jacobian` function for constrainting `real` and `vector` types.

```stan
functions {
real upper_bound_jacobian(real x, real ub) {
  jacobian += x;
  return upper_bound - exp(x);
}
vector upper_bound_jacobian(vector x, real ub) {
  jacobian += x;
  return upper_bound - exp(x);
}
}

data {
 real ub;
 int N;
}

parameters {
  real b_raw;
  vector[N] b_vec_raw;
}

transformed parameters {
  real b = upper_bound_jacobian(b_raw, ub)
  vector[N] b = upper_bound_jacobian(b_vec_raw, ub)
}
```

The following stan program calculates the same constraint and jacobian directly in the transformed parameters block.

```stan
data {
 real ub;
 int N;
}

parameters {
  real b_raw;
}

transformed parameters {
  jacobian += b_raw;
  real b = upper_bound - exp(b_raw);
}
```


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The first thing we would do is add the `jacobian` keyword to the Stan language. 
Like `target`, `jacobian` would only be available on the left hand side of statements to be accumulated into. 
Its domain is restricted to the `transformed parameters` and functions ending in `_jacobian`.
The main difference between `jacobian` and `target` is that the jacobian accumulation is optional for Stan algorithms. If an algorithm wants to do something like maximum likelihood estimation then it is possible to turn off the Jacobian accumulation.

## Transformed Parameters

Inside of transformed parameters we expose `jacobian` like in the functions section listed below. 
Any jacobian accumulation will be wrapped in an `if (Jacobian)` so that the Jacobian increment only happens when requested.

```stan
parameters {
 real b_raw;
}
transformed parameters {
 // (2) Transform and accumulates like stan math directly
 real b = exp(b_raw) + lower_bound;
 // Underneath the hood, only actually calculated if
 // Jacobian bool template parameter is set to true
 jacobian += b_raw;
}
```

## Functions ending in _jacobian

Functions ending in `_jacobian` will operate the same as `_lp` functions, but instead of exposing `target` they will expose `jacobian`.

The generated C++ will reuse a lot of the code from generating the `_lp` functions and will look something like this

```c++
template <bool Jacobian, typename T1, typename T2, typename TJacobian>
auto foo(const T1& x, const T2& ub, TJacobian& jacobian__) {
  if (Jacobian) {
    jacobian__ += x //...;
  }
  return ub - exp(x);
}
```

# Drawbacks
[drawbacks]: #drawbacks

- Making a new keyword `jacobian` will almost surely break current user code.

- Because we do not have the associated function to unconstrain the parameters users will have to initialize from parameters on the unconstrained space. 

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Alternatives

An alternative to this approach would be the `constraints` block as defined in the git history of this proposal's branch. 
That allows for user defined constraints directly in the parameters block.


- What is the impact of not doing this?

Users will have to write programs as they currently do, where jacobian accumulations happen directly in transformed parameters or within the model block. Users will also not be able to turn off jacobian accumulations when using maximum likelihood like algorithms.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

# Citations

[1] https://github.com/stan-dev/stanc3/issues/979#issuecomment-956355020
[2] https://github.com/stan-dev/stanc3/issues/979#issuecomment-932382499
