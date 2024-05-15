- Feature Name: Quantile Functions
- Start Date: September 1, 2021
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

I intend to add many quantile functions to Stan Math for univariate continuous probability distributions that would eventually be exposed in the Stan language. For a univariate continuous probability distribution, the quantile function is the inverse of the Cumulative Density Function (CDF), i.e. the quantile function is an increasing function from a cumulative probability on [0,1] to the parameter space, Θ. The quantile function can be used to _define_ a probability distribution, although for many well-known probability distributions (e.g. the standard normal), the quantile function cannot be written as an explicit function. The partial derivative of a quantile function with respect to the cumulative probability is called the quantile density function, which is also needed in Stan Math but probably is not be worth exposing in the Stan language.

# Motivation
[motivation]: #motivation

The primary motivation for implementing quantile functions in Stan Math is so that users can call them in the `transformed parameters` block of a Stan program to express their prior beliefs about a parameter. The argument (in the mathematical sense) of a quantile function is a cumulative probability between 0 and 1 that would be declared in the `parameters` block and have an implicit standard uniform prior. Thus, if 𝜃 is defined in the `transformed parameters` block by applying the quantile function to this cumulative probability, then the distribution of 𝜃 under the prior is the probability distribution defined by that quantile function. When data is conditioned on, the posterior distribution of the cumulative probability becomes non-uniform but we still obtain MCMC draws from the posterior distribution of 𝜃 that differs from the prior distribution.

As a side note, Stan Math is already using internally this construction in many of its `_rng` functions, where
drawing from a standard uniform and applying a quantile function to it is called "inversion sampling". So,
this design doc is mostly just a plan to make quantile functions available to be called directly. However, it does make the Stan program look more similar to one that draws from the prior predictive distribution in the `transformed data` block for Simulation Based Calibration.

If we were to unnecessarily restrict ourselves to quantile functions for common probability distributions, this method of expressing prior beliefs about 𝜃 is no easier than declaring 𝜃 in the `parameters` block and using a prior Probability Density Function (PDF) to express beliefs about 𝜃 in the `model` block. However, if 𝜃 has a heavy-tailed distribution, then defining it in the `transformed parameters` block may yield more efficient MCMC because the distribution of the cumulative probability (when transformed to the unconstrained space) tends to have tails that are closer to a standard logistic distribution. In addition, expressing prior beliefs via quantile functions is necessary if the log-likelihood function is reparameterized in terms of cumulative probabilities, which we intend to pursue for computational speed over the next three years under the same NSF grant but that will require a separate design doc. 

However, there is no need to restrict ourselves to quantile functions for common probability distributions, and it is conceptually easier for the user to express prior beliefs about 𝜃 using very flexible probability distributions that are defined by explicit quantile functions but lack explicit CDFs and PDFs. Examples include the Generalized Lambda Distribution, the metalog(istic) distribution, the no name distribution of the first kind, and distributions whose quantile function is a spline. In each of these cases, the user would specify a few pairs of cumulative probabilities and values of 𝜃, and then an increasing curve would be run through these user-supplied points. In other words, the quantile function would interpolate through the prior median, the prior quartiles, etc. Thus, from the user's perspective, all of the hyperparameters are _location_ parameters --- even though they collectively characterize the shape of the prior distribution for 𝜃 --- and location parameters are easier for users to think about than other kinds of hyperparameters (especially expectations).

We can support this workflow for specifying prior beliefs about 𝜃 for any univariate continuous probability distribution, although the more flexible distributions include a lot of common probability distributions that have one or two hyperparameters as special cases. I anticipate that once Stan users become familiar with this workflow, many will prefer to use it over the traditional workflow of specifying prior beliefs about 𝜃 via a PDF.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

In the following minimal Stan program
```
data {
  real median;
  real<lower = 0> scale;
}
parameters {
  real<lower = 0, upper = 1> p; // implicitly standard uniform
}
transformed parameters {
  real theta = median + scale * tan(pi() * (p - 0.5));
} // ^^^ quantile function of the Cauchy distribution
```
the distribution of `p` is standard uniform (because there is no `model` block) and the distribution of 𝜃 is Cauchy because `theta` is defined by the quantile function of the Cauchy distribution. But it would be better for users if the quantile function for the Cauchy distribution were implemented in Stan Math and eventually exposed to the Stan language, so that the even more minimal Stan program could be equivalently rewritten as
```
data {
  real median;
  real<lower = 0> scale;
}
parameters {
  real<lower = 0, upper = 1> p; // implicitly standard uniform
}
transformed parameters {
  real theta = cauchy_qf(p, median, scale);
} // theta = median + scale * tan(pi() * (p - 0.5))
```
However, rarely do users have prior beliefs about 𝜃 that necessitate the Cauchy distribution, i.e. 𝜃 is a ratio of standard normal variates. Rather, when users use the Cauchy distribution as a prior they do so because their prior beliefs about 𝜃 are vaguely heavy-tailed and symmetric. But there are many other probability distributions that are heavy tailed and symmetric that are not exactly Cauchy. 

In that situation, a user may find it preferable to use a more flexible distribution, such as the metalog(istic) distribution, whose quantile function interpolates through _K_ pairs of `depths` (cumulative probabilities) and `quantiles` that the user passes to the `data` block of their Stan program. If _K_ = 3, then the metalog quantile function is `theta = a + b * logit(p) + c * (p - 0.5) * logit(p)`, where `a`, `b`, and `c` are three coefficients whose values are implied by the _K_ = 3 `depths` and `quantiles`. This is a valid quantile function --- i.e. it is strictly increasing over the entire [0,1] interval --- if and only if both b > 0 and |c| / b < 1.66711. Having `depths` and `quantiles` in increasing order is necessary but not sufficient for the quantile function to be valid. But _K_ need not be 3 and its value is specified at runtime in the following Stan program:
```
data {
  int<lower = 1> K;
  ordered[K] depths;
  ordered[K] quantiles;
}
transformed data {
  vector[K] coefficients = metalog_coef(depths, quantiles);
} // maximal validity checking ^^^
parameters {
  real<lower = 0, upper = 1> p; // implicitly standard uniform
}
transformed parameters {
  real theta = metalog_qf(p, coefficients);
} // minimal ^^^ validity checking
```
The mindset of the Stan user could be:

> Before seeing any new data, I believe there is an equal chance that 𝜃 is negative as it is positive. There is a 0.25 chance that 𝜃 < -1 and a 0.25 chance that 𝜃 > 1. Finally, there is a 0.1 chance that 𝜃 < -3 and a 0.1 chance that 𝜃 > 3. So, _K_ = 5, `depths = [0.1, 0.25, 0.5, 0.75, 0.9]'`, and `quantiles = [-3, -1, 0, 1, 3]'`.

The `metalog_qf` interpolates through these _K_ points that the user provides. In this example, the user's prior beliefs about 𝜃 happen to be very close to a standard Cauchy distribution, but if the prior `depths` and `quantiles` were different, then the metalog distribution would still apply. Thus, the user does not need to know about the Cauchy distribution or that you could obtain a distribution with slightly lighter tails by using the Student t distribution with a small degrees of freedom; they just need to specify the prior values of the quantile function at 0.1, 0.9 or other tail `depths`. In other words, this workflow would drastically deemphasize the _name_ of the probability distribution and focus on its main _properties_ like the median, inter-quartile range, and left/right tail heaviness.

The `metalog_coef` function that is called in the `transformed data` block above would output the `coefficients` that are needed to define the metalog quantile function as a weighted sum of basis functions, i.e. a, b, and c if _K_ = 3. These `coefficients` are not particularly interpretable but are implied by the readily-interpretable `depths` and `quantiles`; in other words, they are the `coefficients` that imply `metalog_qf` interpolates through those _K_ `depths` and `quantiles` and are thus a solution to a linear system of _K_ equations. When _K_ = 3, the equations to be solved using linear algebra are

![system of equations][K3]

The `metalog_coef` function would check that both `depths` and `quantiles` are strictly increasing and that the quantile density function is strictly increasing throughout the [0,1] interval, which is fairly expensive if _K_ > 3 but only needs to be checked once if both `depths` and `quantiles` are constants. Then, the  `metalog_qf` function that is called in the `transformed parameters` block only needs to check that `p` is between 0 and 1.

An exception is thrown by any quantile function if a purported cumulative probability is negative or greater than 1, although 0 and 1 are valid edge cases. This behavior is unlike that of a CDF where it is arguably coherent, for example, to query what is the probability that a Beta random variate is less than or equal to 42? Helper functions like `metalog_coef` function throw an exception if the implied quantile density function is negative at any point in the [0,1] interval by numerically searching this interval for a root (if there is no better way).

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

From a developer's perspective, there are four categories of quantile functions:

1. Explicit functions with a predetermined number of hyperparameters. Examples include the Cauchy distribution, the exponential distribution, and maybe ten other distributions. All of the arguments could easily be templated. For most such distributions, we already have the CDFs and PDFs. An exception is the Generalized Lambda Distribution, which does not have an explicit CDF or PDF. Also, there is a useful Johnson-like system of distributions with explicit quantile functions that do have explicit CDF or PDFs.
2. Explicit functions with a number of hyperparameters that is determined at runtime. Examples include the metalog distribution, the no name distribution of the first kind, and a few other "quantile parameterized distributions". All of the arguments could be templated, but the hyperparameters are vectors of size _K_. None of these distributions currently exist in Stan Math because they do not have explicit CDFs or PDFs.
3. Implicit functions where all the `var` hyperparameters are outside the kernel. Examples include the normal distribution and the Student t distribution with a fixed degrees of freedom. In this case, the partial derivatives are fairly easy to compute.
4. Implicit functions where some of the `var` hyperparameters are inside the kernel. Examples include the gamma distribution, beta distribution, and many others that are not in the location-scale family. In this case, the partial derivative with respect to a hyperparameter is not an explicit function.

Unlike the `_cdf` and `_lpdf` functions in Stan Math that return scalars even if their arguments are not scalars, the quantile (density) functions should return something whose size is the same as that of the first argument. 

## Category (1)

In C++, `cauchy_qf` could be implemented in `prim/prob` basically like
```
template <typename T_p, typename T_loc, typename T_scale>
return_type_t<T_p, T_loc, T_scale> cauchy_qf(const T_p& p, const T_loc& mu,
                                             const T_scale& sigma) {
  // argument checking
  return mu + sigma * tan(pi() * (p - 0.5));
}
```
In the actual implementation, we would want to handle the partial derivatives analytically rather than using autodiff, at least for categories (1) and (2). In this case, if `p` is 1 or 0, then the corresponding returned value is positive infinity or negative infinity respectively, which are the correct limiting values.

The partial derivative of the quantile function with respect to the first argument is called the quantile density function and could be implemented in the Cauchy case like
```
template <typename T_p, typename T_scale>
return_type_t<T_p, T_loc, T_scale> cauchy_qdf(const T_p& p,
                                              const T_scale& sigma) {
  // argument checking
  return pi() * sigma / square(sin(pi() * p));
}
```
Here there is a minor issue of whether the signature of the `cauchy_qdf` should also take `mu` as an argument, even though the quantile density function does not depend on `mu`.

The Generalized Lambda Distribution (GLD) is a flexible probability distribution that can either be bounded or bounded on one or both sides depending on the values of its four hyperparameters. The GLD is not in Stan Math currently but is defined by its explicit quantile function since its CDF and PDF are not explicit functions. There are actually several parameterizations of the GLD quantile function that are not entirely equivalent, but the preferable parameterization looks like this in Stan code
```
     Generalized Lambda Distribution helper function
  
     See equation 11 of
     https://mpra.ub.uni-muenchen.de/37814/1/MPRA_paper_37814.pdf
  
     @param p real cumulative probability
     @param chi real skewness parameter between -1 and 1
     @param xi real steepness parameter between  0 and 1
     @return real number that can be scaled and shifted to ~GLD
   */
  real S(real p, real chi, real xi) {
    real alpha = 0.5 * (0.5 - xi) * inv_sqrt(xi * (1 - xi));
    real beta  = 0.5 * chi * inv_sqrt(1 - square(chi));
    if (chi < -1 || chi > 1) reject("chi must be between -1 and 1");
    if (xi < 0 || xi > 1) reject("xi must be between 0 and 1");
    if (p > 0 && p < 1) {
      if (chi != 0 || xi != 0.5) {
        if (fabs(alpha) != beta) {
          real s = alpha + beta;
          real d = alpha - beta;
          if (alpha == negative_infinity()) return 0;
          return (p ^ s - 1) / s - ( (1 - p) ^ d - 1 ) / d;
        } else if (xi == 0.5 * (1 + chi)) {
          real d = 2 * alpha;
          return log(p) - ( (1 - p) ^ d - 1 ) / d;
        } else {// xi == 0.5 * (1 - chi)
          real s = 2 * alpha;
          return (p ^ s - 1) / s - log1m(p);
        }
      } else return log(p) - log1m(p); // chi == 0 and xi == 0.5
    } else if (p == 0) { // equation 13
      return xi < 0.5 * (1 + chi) ? -inv(alpha + beta) : negative_infinity();
    } else if (p == 1) { // equation 14
      return xi < 0.5 * (1 - chi) ?  inv(alpha - beta) : positive_infinity();
    } else reject("p must be between zero and one");
    return not_a_number(); // never reaches
  }
```
The quantile function of the GLD would then be like
```
real gld_qf(p, real median, real iqr, real chi, real xi) {
  return median + iqr * (S(p, chi, xi) - S(0.5, chi, xi)) 
    / (S(0.75, chi, xi) - S(0.25, chi, xi));
}
```
In this case, the GLD is guaranteed to be strictly increasing if the stated inequality conditions on `chi` and `xi` are satisfied. However, if the user supplies a prior median, prior lower / upper quartiles, and one other pair of a depth and a quantile, it is not guaranteed that there is any GLD quantile function that runs exactly through those four points. We can provide a helper function that takes 

  * Inputs a prior median, prior lower / upper quartiles, and one other pair of a depth and a quantile 
  * Outputs the values of `chi` and `xi` that are consistent with those four points
  * Throws an exception if there are no such values of `chi` and `xi`
  
The main difficulty with that is that the equations are very nonlinear and difficult to solve numerically. The `algebraic_solver` in Stan Math currently sometimes fails to find values of `chi` and `xi` that are consistent with the prior quantiles even when admissible values exist, which is a source of frustration. Another difficult is that sometimes the "right" values of `chi` and `xi` imply a GLD that is bounded on one or both sides even though the user intended for all real numbers to be in the parameter space. There is not a lot that can be done about that, except print a warning.


## Category (2)

For distributions like the metalog, there would be an exposed helper function with a `_coef` postfix that inputs vectors (or real arrays) of `depths` and `quantiles` and outputs the implied vector of `coefficients` after thoroughly checking for validity (and throwing an exception otherwise)
```
template <typename T_d, typename T_q>
return_type_t<T_d, T_q> metalog_coef(const T_q& depths,
                                     const T_d& quantiles) {
  // check that both depths and quantiles are ordered
  // check that all elements of depths are between 0 and 1 inclusive
  // solve linear system for coefficients derived by Tom Keelin
  // check that metalog_qdf with those coefficients has no root on [0,1]
  return coefficients;
}
```
Then, the quantile and quantile density functions can be defined with `coefficients` as the hyperparameter vector:
```
template <typename T_p, typename T_c>
return_type_t<T_p, T_c> metalog_qf(const T_p& p,
                                   const T_c& coefficients) {
  // check that p is between 0 and 1 inclusive
  // calculate quantiles via dot_product
  return quantiles;
}

template <typename T_p, typename T_c>
return_type_t<T_p, T_c> metalog_qdf(const T_p& p,
                                    const T_c& coefficients) {
  // check that p is between 0 and 1 inclusive
  // calculate slopes via dot_product
  return slopes;
}
```
If the `_qdf` can be written as a polynomial in `p`, then it is possible for the `_coef` function to quickly check whether the `_qdf` has any root on the [0,1] interval using Budan's [theorem](https://en.wikipedia.org/wiki/Budan%27s_theorem). If the `_qdf` is not a polynomial, then the `_coef` function would have to call one of the root-finding [functions](https://www.boost.org/doc/libs/1_76_0/libs/math/doc/html/root_finding.html) in Boost to verify that the `_qdf` has no root on the [0,1] interval. Alternatively, we could approximate a non-polynomial with a Chebyshev interpolant and write the interpolant as a polynomial in `_p` as advocated by John Boyd and others.

Boost has a well-known monotonic [interpolation](https://www.boost.org/doc/libs/1_76_0/libs/math/doc/html/math_toolkit/pchip.html) function called `pchip` that could be used as a flexible quantile function. It consists of piecewise cubic polynomials that are differentiable at the given points. However, the `pchip` constructor returns a callable, and it would be computationally wasteful to reconstruct the spline at every leapfrog step when the points that it is interpolating through are fixed data. But the Stan language currently lacks something useful like
```
data {
  int<lower = 1> K;
  ordered[K] depths;
  ordered[K] quantiles;
}
transformed data { // not valid syntax
  callable my_qf = pchip(depths, quantiles);
}
parameters {
  real<lower = 0, upper = 1> p; // implicitly standard uniform
}
transformed parameters {
  real theta = my_qf(p);
}
```
Maybe we could add something like that `transformed data` block when we do lambda functions.

## Category (3)

The `normal_qf` would be almost the same as `cauchy_qf`, even though it relies on `inv_Phi` which is not an explicit function of the cumulative probability:
```
template <typename T_p, typename T_loc, typename T_scale>
return_type_t<T_p, T_loc, T_scale> normal_qf(const T_p& p, const T_loc& mu,
                                             const T_scale& sigma) {
  // argument checking
  return mu + sigma * inv_Phi(p);
}
```
In this case, if `p` is too _near_ 1 or 0, then `inv_Phi(p)` will overflow to positive or negative infinity respectively, which is numerically acceptable even though analytically, it should only be infinite if `p` is _exactly_ 1 or 0 respectively. In the case of the normal distribution, or another distribution in category (3), it is rather easy to differentiate with respect to the hyperparameters because they do not enter the kernel of the implicit function, in this case `inv_Phi`.

The `inv_Phi` function currently in Stan Math  [differentiates](https://github.com/stan-dev/math/blob/develop/stan/math/rev/fun/inv_Phi.hpp#L23) with respect to its argument by using the fact that the reciprocal of the quantile density function (called the density quantile function) is the the same expression as the PDF, just in terms of `p`. For the general normal distribution, the quantile density function does not depend on `mu`, so it could be implemented like
```
template <typename T_p, typename T_scale>
return_type_t<T_p, T_loc, T_scale> normal_qdf(const T_p& p,
                                              const T_scale& sigma) {
  // argument checking
  return exp(-normal_lpdf(sigma * inv_Phi(p), 0, sigma));
  
}
```

## Category (4)

In the case of many distributions like the gamma distribution, there is no explicit quantile function but the hyperparameters enter the kernel. We can evaluate the quantile function of the gamma distribution rather easily via Boost, which also has "complimentary" quantile functions that have greater numerical accuracy when the depth is close to 1. It would look something like
```
template <typename T_p, typename T_shape, typename T_inv_scale>
return_type_t<T_p, T_shape, T_inv_scale> gamma_qf(const T_p& p,
                                                  const T_shape& alpha,
                                                  const T_inv_scale& beta) {
  // argument checking
  auto dist = boost::gamma_distribution<>(value_of(alpha), 1 / value_of(beta));
  if (p > 0.5) return quantile(complement(dist, 1 - value_of(p)));
  else return quantile(dist, value_of(p));
}

template <typename T_p, typename T_shape, typename T_inv_scale>
return_type_t<T_p, T_shape, T_inv_scale> gamma_qdf(const T_p& p,
                                                   const T_shape& alpha,
                                                   const T_inv_scale& beta) {
  // argument checking
  return exp(-gamma_lpdf(gamma_qf(p, alpha, beta), alpha, beta));
```
However, the derivative of the quantile function with respect to the shape and inverse scale hyperparameters is not an explicit function. We do have the machinery to differentiate an implicit function in `algebraic_solver` that could be essentially reused in this case. Autodiff could also work if Stan Math would ever make `var` compatible with Boost's real number [concept](https://www.boost.org/doc/libs/1_77_0/libs/math/doc/html/math_toolkit/real_concepts.html).

# Drawbacks
[drawbacks]: #drawbacks

Beyond the usual fact that implementing any new function requires documentation, more computer time to unit test, maintainence, etc., this will create a lot of cognitive dissonance for users, even though it is intended to make things easier for them. I think it will be a lot like when we introduced the LKJ distribution, and most users had no idea what to input for the shape parameter because they had not previously thought about a probability distribution over the space of correlation matrices. In this case, almost all users have not previously thought about using a prior _transformation_ of a cumulative probability rather than a prior _PDF_ on the parameter of interest, even though these are the flip sides of the same coin and you could express the same prior beliefs either way, although that is more difficult in practice if either is not an explicit function. 

Some would say that CDFs and PDFs are the only appropriate way to think about continuous probability distributions because the measure theory that lets you go from discrete to continuous random variables unifies the PMF with the PDF. I think this is, at best, irrelevant to most Stan users because they have not taken any measure theory classes and, at worst, creates unnecessary difficulties when they write Stan programs.

But there are going to be a lot of misguided questions like "How do I interpret the posterior distribution of `p`?". Also, once we expose quantile functions, there are going to be a lot of users that only want to utilize probability distributions like the normal that they have heard of before, even though they have no idea what to put for the prior standard deviation and even though probability distributions that they have not heard of before are easier because you only have to specify prior quantiles and depths. Then, users are going to run into errors when the quantile function they try to define is not actually increasing over the entire [0,1] interval and they will not know what to do.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

A quantile function must be an increasing function from the [0,1] interval to a parameter space, Θ. So, it is not as if there is some other concept of a quantile function with an alternative definition, in the same way that there is essentially only one way to define the concept of a CDF. Thus, the only genuine flexibility in the design is in some of the details.

The scope for alternatives is mostly for distributions in category (2) where the size of the hyperparameter vectors is not known until runtime and there is no cheap way to check whether the implied quantile function is increasing throughout the entire [0,1] interval. This is somewhat similar to `multi_normal_lpdf` having no cheap way to check whether the covariance matrix is positive definite. If the covariance matrix is fixed, users are better served calculating its Cholesky factor once in the `transformed data` block and then calling `multi_normal_cholesky_lpdf` in the model block.

In the workflow proposed above, it would be the user's responsibility to call `vector[K] coefficients = metalog_coef(depths, quantiles)` before calling `metalog_qf(p, coefficients)`. The advantage of this workflow is that `metalog_qf` only needs to check that `p` is between 0 and 1. The disadvantage is that if users somehow make up their own coefficients without first calling `metalog_coef`, then `metalog_qf(p, coefficients)` might not be an increasing function throughout the entire [0,1] interval and thus is not a valid quantile function.

One alternative would be for `metalog_qf` to check that it is increasing every time that it is called, in which case we might as well make a three argument version `metalog_qf(p, depths, quantiles)` and avoid having the two-argument version `metalog_qf(p, coefficients)`. That would be more similar to what `multi_normal_lpdf` does, even if the covariance matrix is fixed. However, `multi_normal_lpdf` is rarely called with a fixed covariance matrix, whereas `metalog_qf` would typically be called with fixed `depths` and `quantiles`, so the redundant checking would be more painful.

An alternative suggested by Brian Ward would be for `metalog_qf` to have the code that checks whether the quantile function is increasing over the entire [0,1] interval be wrapped in a `ifndef X ... endif` statement so that the check could be disabled by a compiler flag. This would ensure validity if that code were executed, but has the disadvantage that it could not be avoided in a precompiled Stan program, such as those that come with rstanarm unless the user were to reinstall it from source every time they wanted to switch the compiler flag on and off.

Another alternative would be for `metalog_qf(p, coefficients)` to check that `metalog_qdf(p, coefficients)` is positive. However, it is conceptually insufficient to establish that the quantile density function is positive at a particular `p`; it needs to be positive for every value in the [0,1] interval. Thus, although this check is cheap, it would not be dispositive on its own. For example, if `depths = [0.4, 0.5, 0.6]'` and `quantiles = [-0.1, 0, 0.5]'`, then `metalog_qf` would be U-shaped with a trough just above `0.4`. In this case, this check would pass if `p` were to the right of the trough even though `metalog_qf` is decreasing (and hence is invalid) to the left of the trough. In a HMC context, if there is any point in [0,1] where `metalog_qdf` is negative, it will undoubtedly be hit at some point, and we would throw a fatal exception. However, in the context of optimization, it is more plausible that no such point will be landed on along the optimization path, even though such points may exist in the [0,1] interval.

We could use the Eigen plugin mechanism to have an addition boolean that is `true` if and only if it has been produced by a `_coef` function that thoroughly checks for validity. Since users would not be able to set it to `true` within the Stan language, they could not call the `metalog_qf` without having called `metalog_coef`. However, that seems heavy-handed, and there could be valid ways to construct the vector of coefficients in a higher-level interface and passing them to the `data` block of their Stan programs.

Steve Bronder suggested that if the user were to call `real theta = metalog_qf(p, metalog_coef(depths, quantiles));` in the `transformed parameters` block but where both `depths` and `quantiles` are fixed, then the parser could elevate the call to `metalog_coef(depths, quantiles)` to the end of the `transformed data` block. If the parser could also disable the check inside `metalog_qf` that the quantile function is increasing throughout the [0,1] interval, that could work as well and be implemented even after `metalog_qf` has been implemented.

It has been suggested that if the `metalog_qf` implied by `depths` and `quantiles` is not strictly increasing over the entire [0,1] interval, then we could drop some of the points so that it becomes strictly increasing. That would not work well in HMC if `depths` and / or `quantiles` were an unknown `var` because of the discontinuities, but even in the case where both `depths` and `quantiles` are fixed data, this would be taking the unprecedented (in Stan) step of conditioning on something other than what the user said to condition on, even though what the user said to condition on makes no sense.

I suppose we do not have to merge the quantile function pull request(s) at all, but I am obligated to make the branches under a NSF grant. This NSF grant also funds me and Philip to interpolate the log-likelihood as a function of `p`, as opposed to a function of 𝜃. We can potentially interpolate the log-likelihood as a function of `p` much faster than we can evaluate the log-likelihood as a function of 𝜃, but in order to do that, users would need to reparameterize their Stan programs so that `p` is declared in the `parameters` block, in which case they would need to use quantile functions in the `transformed parameters` block to express their prior beliefs about 𝜃. Thus, if we do not implement a lot of quantile functions for users to express their prior beliefs with, then they cannot capture the gains in speed from interpolating the log-likelihood as a function of `p`.

# Prior art
[prior-art]: #prior-art

There is no prior art needed in the narrow intellectual property sense because quantile functions are just math and math cannot be patented. However, quantile functions have been implemented (but presumably not used for much besides pseudo-random number generation) in other languages for decades, such as:

* R: [qcauchy](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/Cauchy.html) and similarly for other common distributions
* Boost: [cauchy_distribution](https://www.boost.org/doc/libs/1_76_0/libs/math/doc/html/math_toolkit/dist_ref/dists/cauchy_dist.html) and similarly for other common distributions
* Mathematica: The quantile function is a standard (but not always explicit) function in the [Ultimate Probability Distribution Explorer](https://blog.wolfram.com/2013/02/01/the-ultimate-univariate-probability-distribution-explorer/)

There is one [textbook](https://www.google.com/books/edition/Statistical_Modelling_with_Quantile_Func/7c1LimP_e-AC?hl=en) on quantile functions that spends a good bit of time pointing out that quantile functions are underutilized even for data (priors or anything to do with Bayesian analysis are not mentioned). Tom Keelin has a number of [papers](http://www.metalogdistributions.com/publications.html) and some Excel workbooks on the metalog distribution, which is essentially Bayesian but does not involve MCMC. I did a [presentation](https://youtu.be/_wfZSvasLFk) at StanCon and a couple at the Flatiron Institute on these ideas.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

There are a lot of unresolved questions about the other part of the NSF grant, which involves evaluating the log-likelihood in terms of `p`, rather than in terms of `theta`. However, quantile functions and there use as prior transformations can stand on its own and can be implemented before the rest of the NSF grant.

I am not going to do

  - Quantile functions for discrete distributions because they are not that useful in Stan and are not useful at all for the intended workflow.
  - Empirical quantile functions that for example, could be used to determine the median of a set of data points because they are not relevant to the intended workflow.
  - Any of the `_cdf`, `_lpdf` etc. functions for distributions that have explicit quantile functions but not explicit CDFs because they are not that useful for the intended workflow.
  - Quantile functions for multivariate distributions because they are harder to define and you never get to use any explicit functions.
  - Density quantile functions, which are the reciprocals of the quantile density functions (which are the first derivative of a quantile functions) and can be used for indirect log-likelihoods. There is a Ph.D student at Lund who is working on this using Stan for his dissertation that is interested in implementing this approach for the metalog density quantile function.

As usual, there is a question of naming. I prefer `_qf` suffixes to `_icdf` suffixes for third reasons. First, `_qf` is more coherent if there are also going to be `_qdf`, `_ldqf`, etc. functions. With `_icdf`, then it is less obvious that `_qdf` is the derivative of it. Second, although `_icdf` would perhaps be more descriptive if we were only talking about distributions in category (1) that have explicit CDFs, the `_icdf` suffix is less intuitive for the Generalized Lambda Distribution and distributions in category (2) that have explicit quantile functions but lack explicit CDFs. If anything, the CDF should be called the inverse quantile function when the quantile function is primitive and taken as the definition of the probability distribution, which is how I am trying to get Stan users to think. Third, some of these functions would have an argument that will be documented as `quantiles`, which corresponds better with the `_qf` suffix than with the `_icdf` suffix.

The main substantive question to resolve in the design is whether to have a `metalog_coef` function that would check whether `metalog_qf` is increasing over the entire [0,1] interval by checking whether `metalog_qdf` is positive over the entire [0,1] interval or to implement one of the two alternatives described above.

Two minor questions to resolve in the design are

  - Should quantile density functions for probability distributions in the location-scale family have signatures that involve the location parameter even though the quantile density function does not depend on it?
  - Should we expose "complementary" versions of the quantile (density) functions, like `_cqf` and `_cqdf`? R does not have separate functions put takes a `lower.tail` argument that defaults to `TRUE` but can be specified as `FALSE` to obtain greater numerical precision when the cumulative probability is close to 1. I would say no for now because when the quantile function is explicit, you can usually enhance the numerical precision internally.

There are some questions as to how many pull requests to do, in what order, and which quantile functions should go into which pull request, but those questions can be resolved later.

[K3]: 0028-quantile-functions.png