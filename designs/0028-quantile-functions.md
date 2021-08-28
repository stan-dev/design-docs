- Feature Name: Quantile Functions
- Start Date: September 1, 2021
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

I intend to add many quantile functions to Stan Math, at least for univariate continuous probability distributions, that would eventually be exposed in the Stan language. For a univariate continuous probability distribution, the quantile function is the inverse of the Cumulative Density Function (CDF), i.e. the quantile function is an increasing function from $\left[0,1\right]$ to the parameter space, $\Theta$. The quantile function can be used to _define_ a probability distribution, although for many well-known probability distributions (e.g. the standard normal) the quantile function cannot be written as an explicit function.

# Motivation
[motivation]: #motivation

The primary motivation for implementing quantile functions in Stan Math is so that users can call them in the `transformed parameters` block of a Stan program to express their prior beliefs about a parameter. The argument (in the mathematical sense) of a quantile function is a cumulative probability between $0$ and $1$ that would be declared in the `parameters` block and have an implicit standard uniform prior. Thus, if $\theta$ is defined in the `transformed parameters` block by applying the quantile function to this cumulative probability, then the distribution of $\theta$ under the prior is the probability distribution defined by that quantile function. When data is conditioned on, the posterior distribution of the cumulative probability becomes non-uniform but we still obtain MCMC draws from the posterior distribution of $\theta$.

If we were to unnecessarily restrict ourselves to quantile functions for common probability distributions, this method of expressing prior beliefs about $\theta$ is no easier than declaring $\theta$ in the `parameters` block and using a prior Probability Density Function (PDF) to express beliefs about $\theta$ in the `model` block. However, if $\theta$ has a heavy-tailed distribution, then defining it in the `transformed parameters` block may yield more efficient MCMC because the distribution of the cumulative probability (when transformed to the unconstrained space) tends to have tails that are more reasonable. In addition, expressing prior beliefs via quantile functions is necessary if the log-likelihood function is reparameterized in terms of cumulative probabilities, which we intend to pursue for computational speed over the next three years under the same NSF grant.

However, there is no need to restrict ourselves to quantile functions for common probability distributions, and it is conceptually easier for the user to express prior beliefs about $\theta$ using very flexible probability distributions that are defined by explicit quantile functions but lack explicit CDFs and PDFs. Examples include the Generalized Lambda Distribution, the metalog(istic) distribution, the Chebyshev distribution of the first kind, and increasing cubic splines. In each of these cases, the user would specify a few pairs of cumulative probabilities and values of $\theta$, and then an increasing curve would be run through these user-supplied points. In other words, the quantile function would interpolate through the prior median, the prior quartiles, etc. Thus, from the user's perspective, all of the hyperparameters are _location_ parameters --- even though they collectively characterize the shape of the prior distribution for $\theta$ --- and location parameters are easier for user's to think about than other kinds of hyperparameters.

We can support this workflow for specifying prior beliefs about $\theta$ for any univariate continuous probability distribution, although the more flexible distributions include a lot of common probability distributions that have one or two hyperparameters as special cases. I anticipate that once Stan users are exposed to this workflow, many will prefer to use it over the traditional workflow of specifying prior beliefs about $\theta$ via a PDF.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

For univariate continuous probability distributions, the quantile function is the inverse of the CDF, or equivalently, the CDF is the inverse of the quantile function. For example, in the following minimal Stan program
```
data {
  real median;
  real<lower = 0> scale;
}
parameters {
  real<lower = 0, upper = 1> p;
}
transformed parameters {
  real theta = median + scale * tan(pi() * (p - 0.5));
} // quantile function of the Cauchy distribution
```
the distribution of `p` is standard uniform (because there is no `model` block) and the distribution of $\theta$ is Cauchy because `theta` is defined by the quantile function of the Cauchy distribution, $\theta = m + s \tan\left(\pi * \left(p - \frac{1}{2}\right)\right)$. But it would be better for users if the quantile function for the Cauchy distribution were implemented in Stan Math and (eventually) exposed to the Stan language, so that this minimal Stan program could be equivalently rewritten as
```
data {
  real median;
  real<lower = 0> scale;
}
parameters {
  real<lower = 0, upper = 1> p;
}
transformed parameters {
  real theta = cauchy_qf(p, median, scale);
}
```
However, rarely do user's have prior beliefs about $\theta$ that necessitate the Cauchy distribution, i.e. $\theta$ is a ratio of centered normals. Rather, when users use the Cauchy distribution as a prior they do so because their beliefs about $\theta$ are heavy-tailed and symmetric. But there are many other probability distributions that are heavy tailed and symmetric that are not exactly Cauchy. In that situation, a user may find it preferable to use a more flexible distribution, such as the metalog(istic) distribution, whose quantile function interpolates through $K$ pairs of `quantiles` and `depths` (cumulative probabilities) that the user passes to the `data` block of their Stan program.
```
data {
  int<lower = 1> K;
  ordered[K] quantiles;
  ordered[K] depths;
}
parameters {
  real<lower = 0, upper = 1> p;
}
transformed parameters {
  real theta = metalog_qf(p, quantiles, depths);
}
```
The mindset of the Stan user could be:

> Before seeing any new data, I believe there is an equal chance that $\theta$ is negative as positive. There is a $\frac{1}{4}$ chance that $\theta < -1$ and a $\frac{1}{4}$ chance that $\theta > 1$. Finally, there is a $\frac{1}{10}$ chance that $\theta < -3$ and a $\frac{1}{10}$ chance that $\theta > 3$. Thus, `quantiles = [-3, -1, 0, 1, 3]'` and `depths = [0.1, 0.25, 0.5, 0.75, 0.9]'`.

Then, the `metalog_qf` interpolates through these $K = 5$ points that the user provides. In this case, the user's prior beliefs about $\theta$ happen to be very close to a standard Cauchy distribution, but if the prior `quantiles` and `depths` were different, then the metalog distribution would still apply. Thus, the user does not need to know about the Cauchy distribution or that you could obtain a distribution with slightly lighter tails by using the Student t distribution with a small number of degrees of freedom; they just need to specify the prior values of the quantile function at $\frac{1}{10}$, $\frac{9}{10}$ or other tail `depths`.

An exception is thrown by any quantile function if a purported cumulative probability is negative or greater than $1$, although $0$ and $1$ are valid edge cases. Similarly, for quantile functions like `metalog_qf` that input `quantiles` and `depths` an exception is thrown if these vectors are not strictly increasing. Finally, for some quantile functions like `metalog_qf`, it is difficult to tell whether it is strictly increasing over the entire $\left[0,1\right]$ interval; thus, an exception is thrown if the derivative of the quantile function (called the quantile density function) evaluated at `p` is negative. In the usual case where `quantiles` and `depths` are declared in the `data` block, it could be possible to call some sort of validity function in the `transformed data` block that would return $1$ if the quantile function is strictly increasing over the entire $\left[0,1\right]$ interval (and $0$ otherwise) by checking whether the quantile density function lacks a root on $\left[0,1\right]$.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

Unlike the `_cdf` and `_lpdf` functions in Stan Math that return scalars even if their arguments are not scalars, the quantile functions should return a scalar only if all of the arguments are scalars and otherwise should return something whose size is equivalent to the size of the argument with the largest size. In C++, `cauchy_qf` could be implemented in `prim/prob` roughly like
```
template <typename T_p, typename T_loc, typename T_scale>
return_type_t<T_p, T_loc, T_scale> cauchy_qf(const T_p& p, const T_loc& mu,
                                             const T_scale& sigma) {
  static const char* function = "cauchy_qf";                                             
  check_consistent_sizes(function, "Depth", p, "Location parameter",
                         mu, "Scale Parameter", sigma);
  check_probability(function, "Depth", p);
  check_finite(function, "Location parameter", mu);
  check_positive_finite(function, "Scale parameter", sigma);
  using T_partials_return = partials_return_t<T_p, T_loc, T_scale>;  
  T_partials_return quantiles;
  for (int n = 0; n < size(quantiles); n++) { // if mu and sigma are scalars
    quantiles[n] = mu + sigma * tan(stan::math::pi() * (p[n] - 0.5));
  }
  return quantiles;
}
```
In the actual implementation, we would want to handle the partial derivatives analytically rather than using autodiff, at least in cases like `cauchy_qf` where the quantile function is explicit. In this case, if `p[n]` is $1$ or $0$, then $\tan\left(\pm \frac{\pi}{2}\right)$ is $\pm \infty$, which is correct.

The `normal_qf` would be almost the same, even though it relies on `inv_Phi` which is not an explicit function of the depth:
```
template <typename T_p, typename T_loc, typename T_scale>
return_type_t<T_p, T_loc, T_scale> normal_qf(const T_p& p, const T_loc& mu,
                                             const T_scale& sigma) {
  static const char* function = "normal_qf";                                             
  check_consistent_sizes(function, "Depth", p, "Location parameter",
                         mu, "Scale Parameter", sigma);
  check_probability(function, "Depth", p);
  check_finite(function, "Location parameter", mu);
  check_positive_finite(function, "Scale parameter", sigma);
  using T_partials_return = partials_return_t<T_p, T_loc, T_scale>;  
  T_partials_return quantiles;
  for (int n = 0; n < size(quantiles); n++) { // if mu and sigma are scalars
    quantiles[n] = mu + sigma * inv_Phi(p[n]);
  }
  return quantiles;
}
```
In this case, if `p[n]` is _near_ $1$ or $0$, then `inv_Phi(p[n])` will overflow to $\pm \infty$, which is numerically acceptable even though analytically, it should only be $\pm \infty$ if `p[n]` is _exactly_ $1$ or $0$ respectively.

In the case of the normal distribution, it is rather easy to differentiate with respect to $\mu$ and / or $\sigma$ because they do not enter the implicit function `inv_Phi`. However, in the case of many distributions like the gamma distribution, there is no explicit quantile function but the shape hyperparameters enter the implicit function. Thus, we can evaluate the quantile function of the gamma distribution rather easily via Boost:
```
template <typename T_p, typename T_shape, typename T_inv_scale>
return_type_t<T_p, T_shape, T_inv_scale> gamma_qf(const T_p& p,
                                                  const T_shape& alpha,
                                                  const T_inv_scale& beta) {
  // argument checking
  auto dist = boost::gamma_distribution<>(value_of(alpha), 1 / value_of(beta));
  return quantile(dist, value_of(p));
}
```
but differentiating the quantile function with respect to the shape hyperparameters would be as difficult as differentiating the CDF with respect to the shape hyperparameters. So, I might start by requiring the hyperparameters to be fixed data for distributions that lack explicit quantile functions, and then allow the hyperparameters to be unknown `var` later.

Boost also has "complimentary" quantile functions that have greater numerical accuracy when the depth is close to $1$. Hopefully, we can just utilize these inside Stan Math rather than exposing them to the Stan language. It would look something like
```
template <typename T_p, typename T_shape, typename T_inv_scale>
return_type_t<T_p, T_shape, T_inv_scale> gamma_qf(const T_p& p,
                                                  const T_shape& alpha,
                                                  const T_inv_scale& beta) {
  // argument checking
  auto dist = boost::gamma_distribution<>(value_of(alpha), 1 / value_of(beta));
  if (p > 0.999) return quantile(complement(dist, value_of(p)));
  else return quantile(dist, value_of(p));
}
```

For any probability distribution with a conceptually _fixed_ number of hyperparameters, implementing the quantile function is basically like implementing the CDF (except without the reduction to a scalar return value). However, there are useful probability distributions, such as the metalog distribution, where the quantile function can take an _arbitrary_ number of pairs of quantiles and depths whose number is not known until runtime. In that case, some of the trailing arguments to the quantile function will be vectors or real arrays, or perhaps arrays of vectors or arrays of real arrays. The simplest signature would be
```
template <typename T_p>
T_p metalog_qf(const T_p& p, vector_d& quantiles, vector_d& depths);
```
In order to interpolate through the $K$ points given by `quantiles` and `depths`, you have to set up and then solve a system of $K$ linear equations, which is not too difficult. However, in the usual case where both `quantiles` and `depths` are fixed data, it is computationally wasteful to solve a constant system of $K$ linear equations at each leapfrog step. It would be more efficient for the user to solve for the $K$ coefficients once in the `transformed data` block and pass those to `metalog_qf` in the `transformed parameters` block when it is applied to a `var`. If we were willing to distinguish user-facing functions by number of arguments, we could have a variant of the metalog quantile function that takes the coefficients:
```
template <typename T_p>
T_p metalog_qf(const T_p& p, vector_d& coefficients);
```
that were produced by a helper function
```
vector_d metalog_coef(vector_d& quantiles, vector_d& depths);
```
that checked the `quantiles` and `depths` for validity, solved the system of $K$ equations, and returned the resulting coefficients. 

This `metalog_coef` function could also check that the quantile function that interpolates through these $K$ points is, in fact, strictly increasing over the entire $\left[0,1\right]$ interval. If `quantiles` and / or `depths` were not fixed data, then it would be very expensive to check whether the quantile function that interpolates through these $K$ points is strictly increasing over the entire $\left[0,1\right]$ interval, although it is cheap to check whether it is increasing at a _particular_ depth (and we would have to evaluate the derivative anyway if the depth is a `var`). Thus, if `quantiles` and / or `depths` is a `vector_v`, I propose that we check that the quantile function is increasing at the given depth(s) rather than at all possible dephs, which is presumably adequate for MCMC and optimization but could result in an invalid probability distribution if it were used in some other context.

Boost has a well-known monotonic [interpolation](https://www.boost.org/doc/libs/1_76_0/libs/math/doc/html/math_toolkit/pchip.html) function called `pchip` that could be used as a flexible quantile function. It consists of piecewise cubic polynomials that are differentiable at the given points. However, the `pchip` constructor returns a callable, and like in the metalog case, it would be computationally wasteful to reconstruct the spline at every leapfrog step when the points that it is interpolating through are fixed data. But the Stan language currently lacks something useful like
```
data {
  int<lower = 1> K;
  ordered[K] quantiles;
  ordered[K] depths;
}
transformed data { // not valid syntax
  callable my_qf = pchip(depths, quantiles);
}
parameters {
  real<lower = 0, upper = 1> p;
}
transformed parameters {
  real theta = my_qf(p);
}
```
Maybe we could add something like that `transformed data` block when we do lambda functions.

# Drawbacks
[drawbacks]: #drawbacks

Beyond the usual fact that implementing any new function requires documentation, more computer time to unit test, maintainence, etc., this will create a lot of cognitive dissonance for users, even though it is intended to make things easier for them. I think it will be a lot like when we introduced the LKJ distribution, and most users had no idea what to input for the shape parameter because they had not previously thought about a probability distribution over the space of correlation matrices. In this case, almost all users have not previously thought about using a prior _transformation_ of a cumulative probability rather than a prior _PDF_ on the parameter of interest, even though these are the flip sides of the same coin and you could express the same prior beliefs either way. So, there are going to be a lot of misguided questions like "How do I interpret the posterior distribution of `p`?". Also, even if we have quantile functions, there are going to be a lot of users that only want to utilize probability distributions like the normal that they have heard of before, even though they have no idea what to put for the prior standard deviation and even though probability distributions that they have not heard of before are easier because you only have to specify prior quantiles and depths. Also, users are going to run into errors when the quantile function they try to define is not actually increasing over the entire $\left[0,1\right]$ interval and they will not know what to do.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

A quantile function must be an increasing function from the $\left[0,1\right]$ interval to a parameter space, $\Theta$. So, it is not as if there is some other concept of a quantile function to compete with this definition, in the same way that there is essentially only one way to define the concept of a CDF. Thus, the only flexibility in the design is in the details, such as how much time are we willing to spend checking that a metlog quantile function is increasing?

I suppose we do not have to merge the ultimate quantile function pull request(s), but I am obligated to make the branches under a NSF grant. This NSF grant also funds me and Philip to interpolate the log-likelihood as a function of `p`, as opposed to a function of $\theta$. We can potentially interpolate the log-likelihood as a function of `p` much faster than we can evaluate the log-likelihood as a function of $\theta$, but in order to do that, users would need to reparameterize their Stan programs so that `p` is declared in the `parameters` block, in which case they would need to use quantile functions in the `transformed parameters` block to express their prior beliefs about $\theta$. Thus, if we do not implement a lot of quantile functions for users to express their prior beliefs with, then they cannot capture the gains in speed from interpolating the log-likelihood as a function of `p`.

# Prior art
[prior-art]: #prior-art

Quantile functions have been implemented (but presumably not used much) in other languages for decades, such as:

* R: [qcauchy](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/Cauchy.html) and similarly for other common distributions
* Boost: [cauchy_distribution](https://www.boost.org/doc/libs/1_76_0/libs/math/doc/html/math_toolkit/dist_ref/dists/cauchy_dist.html) and similarly for other common distributions
* Mathematica: The quantile function is a standard (but not always explicit) function in the [Ultimate Probability Distribution Explorer](https://blog.wolfram.com/2013/02/01/the-ultimate-univariate-probability-distribution-explorer/)

There is one [textbook](https://www.google.com/books/edition/Statistical_Modelling_with_Quantile_Func/7c1LimP_e-AC?hl=en) on quantile functions that spends a good bit of time pointing out that quantile functions are underutilized even for data (priors or anything to do with Bayesian analysis are not mentioned). Tom Keelin has a number of [papers](http://www.metalogdistributions.com/publications.html) and some Excel workbooks on the metalog distribution, which is defined by its quantile function that are essentially Bayesian but do not involve MCMC. I did a [presentation](https://youtu.be/_wfZSvasLFk) at StanCon and a couple at the Flatiron Institute on these ideas.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Discrete distributions: Quantile functions exist for them, but they are not very useful because they are step functions. For completeness, we might implement them eventually but they are irrelevant to the NSF grant and the proposed workflow.
- Multivariate distributions: Quantile functions are harder to define for multivariate continuous distributions, and you never get any explicit functions. Thus, I doubt we will ever do anything on that front.
- Density quantile functions: These are the reciprocals of the quantile density functions (which are the first derivative of a quantile functions), which can be used for log-likelihoods. There is a Ph.D student at Lund who is working on this using Stan for his dissertation, but we will have to see who or what should implement that for Stan Math.
- Checking that the quantile function is increasing: In many cases, the quantile function is increasing by construction. But for some distributions like the metalog, the quantile function is only increasing over the entire $\left[0,1\right]$ interval only for some pairs of quantiles and depths. If those quantiles and / or depths are not fixed data, then verifying whether it is increasing for all points in $\left[0,1\right]$ is much more expensive than verifying so for a given point in $\left[0,1\right]$. 
- Can we have a three-argument version `metalog_qf(p, quantiles, depths)` and a two-argument version `metalog_qf(p, coefficients)` where the coefficients are produced in the `transformed data` block by `metalog_coef(quantiles, depths)`?
- What to do about derivatives of implicit quantile functions with respect to hyperparameters? We have the implicit function stuff worked out in `algebraic_solver`, but I do not know how accurate the partial derivatives are going to be for probability distributions like the gamma.
