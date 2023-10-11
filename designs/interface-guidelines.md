- Feature Name: User Interface Guidelines for Developers
- Start Date: 2020-04-18
- RFC PR: 25
- Stan Issue:

*Note: This document from 2018 is being preserved as a design document. In meetings during 2018, RStan and PyStan developers agreed to the recommendations presented here. At the time, the developers intended to release PyStan 3 and RStan 3 at the same time. This plan has since been abandoned. PyStan 3 was released in March 2021 and follows these guidelines. With the exception of this notice, no edits have been made to this document since 2018. It is preserved here as it documents the design decisions present in PyStan 3. It was imported from the decommissioned Stan wiki in 2020.*

---

This page has recommendations on how users will use Stan to compile programs and draw samples. These recommendations are being implemented in "RStan 3" and "PyStan 3". This page is intended for developers of any user interfaces to Stan.

# Significant Changes
1. New user-facing API (see below for examples)
2. Standardize on CmdStan parameter names. For example, use ``num_chains`` (CmdStan) everywhere rather than the current split (PyStan and RStan use ``chains``).
3. ``permuted`` does not exist
4. Replace ``sampling`` with ``sample`` verb, ``optimizing`` with verb ``maximize``
5. Remove generic ``vb`` method, replace with ``experimental_advi_meanfield`` and ``experimental_advi_fullrank``

# Major Unresolved issues

* ~Should the function/method previously known as ``optimize`` be renamed to be ``maximize``? Whatever decision is made, the renaming should take place in all interfaces (including CmdStan). (AR and BG agree on ``maximize``)~ (yes, discussed 2018-07-05)
* ~Should the function/method previously known as ``vb`` be called via ``experimental_advi_meanfield`` and ``experimental_advi_fullrank`` (mirroring the C++ services names)?~ (yes, discussed on 2018-07-05)
* ~To what extent should the steps in the interfaces mirror those of the C++ / CmdStan?~ (User-facing API shown below is OK.)
* ~What should be stand-alone functions and what should be methods, as in `build(config)` vs. `config$build()`?~ (No separate compile / build step.)
* ~Do we need a separate class that only exposes the algorithms in the C++ library or is it better to for the class to expose both algorithms and lower-level functions like `log_prob`?~ (No separate classes. Advanced users will have workarounds.)
* ~How granular should the estimation functions be, as in `$hmc_nuts_diag_e_adapt()` vs. `$hmc(adapt = TRUE, diag = TRUE, metric = "Euclidean")`~ (Decided by the C++ API refactor. 99% of users will just call the ``sample`` method.)

## RStan-specific 
* Eliminate ``stan`` function? (PyStan has removed it.)

# Other Changes and Notes
1. Store draws internally with draws/chains in last dimension (num_params, num_draws, num_chains) with an eye to ragged array support and/or adding additional draws.
2. To the extent possible, RStan and PyStan should use the same names for internal operations and internal class attributes.

# Typical User Sessions

## Typical R session
We plan to use [ReferenceClasses](http://stat.ethz.ch/R-manual/R-devel/library/methods/html/refClass.html) throughout. See the examples section of [this](https://github.com/stan-dev/rstan/blob/develop/rstan3/R/rstan.R) for a canonical R example.

## Typical PyStan session
```python
import pystan
posterior = pystan.build(schools_program_code, data=schools_data)
fit = posterior.sample(num_chains=1, num_samples=2000)
mu = fit["mu"]  # shape (param_stan_dimensions, num_draws * num_chains) NEW!

fit.to_frame()  # shape (num_chains * num_draws, num_flat_params)

estimates = fit.maximize()
estimates = fit.hmc_nuts_diag_e_adapt(delta=0.9)  # advanced users, unlikely to use

# additional features
assert len(fit) == 3  # three parameters in the 8 schools model: mu, tau, eta
```

## Typical CmdStan session

TBD but Julia and MATLAB just call CmdStan and thus would be similar.

## Typical StataStan session

TBD but StataStan also calls CmdStan but would probably have some quirks

# Methods provided by the Stan library to all interfaces

The class would expose the following methods from the abstract base class (that needs to be implemented):

- scalar log_prob(unconstrained_params)
- vector grad(unconstrained_params)
- tuple  log_prob_grad(unconstrained_params)
- matrix hessian(unconstrained_params)
- tuple  log_prob_grad_hessian(unconstrained_params)
- scalar laplace_approx(unconstrained_params)
- vector constrain_params(unconstrained_params = <vector>)
- vector unconstrain_params(constrained_params = <vector>)
- tuple  params_info() would return
    - parameter names
    - lower and upper bounds, if any
    - parameter dimensions
    - declared type (cov_matrix, etc.)
    - which were declared in the parameters, transformed parameters, and generated quantities blocks
 
# MCMC output containers

## RStan

The VarWriter would fill an Rcpp::NumericVector with appropriate dimensions. Then there would be a new (S4) class that is basically an array to hold MCMC output for a particular parameter, which hinges on the params_info() method. The (array slot of a) StanType has dimensions equal to the original dimensions plus two additional trailing dimensions, namely chains and iterations. Thus,
- if the parameter is originally a scalar, on the interface side it acts like a 3D array that is 1 x chains x iterations
- if the parameter is originally a (row) K-vector, on the interface side it acts like a 3D array that is K  x chains x iterations
- if the parameter is originally a matrix, on the interface side it acts like like a 4D array that is rows x cols x chains x iterations
- if the parameter is originally a ``std::vector`` of type ``foo``, on the interface side it acts like a multidimensional array with dimensions equal to the union of the ``std::vector`` dimensions, the ``foo`` dimensions, chains, and iterations

The advantages of having such a class hierarchy are
- can do customized summaries; i.e. a ``cov_matrix`` would not have its upper triangle summarized because that is redundant with the lower triangle and we can separate the variances from the covariances and a ``cholesky_factor_cov`` would not have its upper triangle summarized because its elements are fixed zeros
- can easily call unconstrain methods (in C++) for one unknown rather than having to do it for all unknowns
- can implement probabalistic programming; i.e. if ``beta`` is a estimated vector in Stan, then in R ``mu <- X %*% beta`` is N x chains x iterations and if ``variance`` is a scalar then ``sigma <- sqrt(variance)`` is a can be summarized appropriately (including n_eff, etc.)

## PyStan

TBD. Allen is ambivalent about doing something like a StanType class hierarchy

## CmdStan

Everything gets written to a flat CSV file

## MCMC output bundle

## StanFitMCMC class in R

TBD

## StanFitMCMC class in PyStan

**instance fields**
- param_draws : This needs to be [ params x chains x iterations ] : double in contiguous memory or similar if the C++ API for split_rhat is going to be called directly and fast.
- param_names  params : string
- num_warmup 1 : long
- timestamps: timestamp (long) for each iteration (possibly roll into param_draws)
- mass matrix : NULL | params | params x params : double
- diagnostic draws: diagnostic params x chains x iterations 
- diagnostic names: diagnostic params : string


## Optimize output bundle

### StanFitOptimize
note: computation of the hessian is optional at optimization time
**instance fields**
- param values
- param names
- value (value of function)
- (optinal) hessian
- (optional) diagnostic param values: diagnostic params x iterations
- diagnostic param names: diagnostic params : string

