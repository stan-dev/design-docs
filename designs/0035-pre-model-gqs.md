- Feature Name: Generated Data Block
- Start Date: 09-30-2024

# Summary
[summary]: #summary


This design doc proposes adding a new block to the Stan language called `generated data`.  It will appear between the transformed parameter and model blocks.  All code in the generated data block is executed based on `double` values like generated quantities and the values it produces are available to the model block

Here is a sample use case which uses the generated data block to generate randomness in sensitivity and specificity value in order to estimate the prevalence of a disease based on positive tests..

```stan
data {
  real<lower=-1, upper=1> rho_ss;
  vector[2] loc_ss;
  vector<lower=0>[2] scale_ss;
  int<lower=0> N;
  int<lower=0, upper=N> n;
}
transformed data {
  cov_matrix[2, 2] Sigma_ss
    = [[scale_ss[1]^2, scale_ss[1] * scale_ss[2] * rho_ss],
       [scale_ss[1] * scale_ss[2] * rho_ss, scale_ss[2]^2]];
}
parameters {
  real<lower=0, upper=1> prevalence;
}
generated data {
  vector<lower=0, upper=1>[2] sens_spec
    = inv_logit(multi_normal_rng(loc_ss, Sigma_ss));
}
model {
  real sens = sens_spec[1];
  real spec = sens_spec[2];
  real pos_test_prob = prev * sens + (1 - prev) * (1 - spec);
  n ~ binomial(pos_test_prob, N);
  prevalence ~ beta(2, 100);
}
```

# Motivation
[motivation]: #motivation

The motivation is to support three new key features for Stan:

* Multiple imputation of missing data
* Cut-based reasoning for random quantities
* Gibbs sampling discrete parameters


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Stan will support a new block, `generated data`, that is required to appear between `transformed parameters` and the `model` block.

Variables may be declared in the same way as for other blocks.  All data types are allowed, including integers.

Within the `generated data` block, all variables and functions declared in earlier blocks (`functions`, `data`, `transformed data`, `parameters`, and `transformed parameters`) will be available.  Variables declared in the `generated data` block will be visible to all later blocks (`model` and `generated quantiries`).

This `generated data` block allows access to all of the standard Stan functions, including random number generator functions ending in `_rng`.  It disallows access to the target log density, so the following operations are not available: target function `target()`, target increment statement `target += <expression>;`, distribution statement `A ~ foo(B);`, and functions ending in `_lp`.

## Example

Here's an example that encodes a normal mixture model by sampling discrete parameters.

```stan
data {
  int<lower=0> N;                  // # observations
  vector[N] y;                     // observations
}
parameters {
  vector[2] mu;                    // component locations
  vector<lower=0>[2] sigma;        // component scales
  real<lower=0, upper=1> lambda;   // mixture ratio
}
generated data {
  // sample z ~ p(z | y, lambda, mu, sigma)
  array[N] int<lower=1, upper=2> z;
  for (n in 1:N) {
    real log_z_eq_1 = log(lambda) + normal_lpdf(y[n] | mu[1], sigma[1]);
    real log_z_eq_2 = log1m(lambda) + normal_lpdf(y[n] | mu[2] sigma[2]);
    real log_p = log_z_eq_1 - log_sum_exp(log_z_eq_1, log_z_eq_2));
    z[n] = 1 + bernoulli_rng(exp(log_p));
  }
}
model {
  // target += p(z | lambda, N)
  sum(z) ~ binomial(lambda, N);

  // target += p(y | mu, sigma, z)
  y ~ normal(mu[z], sigma[z]);

  // target += p(mu, sigma, lambda)
  mu ~ normal(0, 1);
  sigma ~ exponential(1);
  lambda ~ beta(2, 2);
}
```

This is not an efficient way to code this model, but it's the simplest possible example of using the `generated data` block for Gibbs sampling of discrete parameters (i.e., `z`).


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The `generated data` block will be executed in exactly the same way as the `generated quantities` block, i.e., with double precision floating point and single-precision integer types.

Like all of the other blocks, variables are available as soon as they are declared and persist after the block terminates to be available in the `model` and `generated quantities` blocks.


# Drawbacks
[drawbacks]: #drawbacks

It will require additional documentation and tests, increasing Stan's long-term maintenance burden.do things.

Using "cut"-based inference does not perform full Bayesian inference, and there's a risk that this will confuse our users.

Using this block for Gibbs sampling will be less efficient than marginalization and may tempt many users to define poorly mixing models.

There will be no way to test if a Gibbs sampler has defined the correct conditional distribution for variables.

Introducing a `generated data` opens up a back door approach to converting real numbers to integers.  Recall that we do not allow `to_int(real)` to apply to parameters precisely to prevent cutting derivatives and hence inference.  This reintroduces a way to do that by applying `to_int(data real)` because the real values in the `generated data` block will be double precision floating point variables rather than autodiff variables.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Alternatives

To support cut-based inference and multiple imputation, it is possible to run Stan multiple times with data generated in the transformed data block.  This will not be as efficient in that each value will require Stan to be warmed up and sampled.

There is no alternative for the Gibbs-based discrete parameter inference.


- What is the impact of not doing this?

Users will find it impossible to do discrete sampling that interacts with the model and will find it very challenging to do imputation.


# Unresolved questions
[unresolved-questions]: #unresolved-questions


# Citations

* Plummer, Martyn. 2015.  Cuts in Bayesian graphical models.  Statistical Computing 25:37--43.

* Wikipedia.  Gibbs Sampling.  https://en.wikipedia.org/wiki/Gibbs_sampling

