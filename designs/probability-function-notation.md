- Feature Name: Stan 3 Density Notation and Increments
- Start Date: 2016-01-28
- RFC PR: ??
- Stan Issue:

Each probability distribution, such as Bernoulli or normal, has functions for its probability density function (PDF), cumulative distribution function (CDF), complementary cumulative distribution function (CCDF), inverse CDFs (ICDF), and pseudo random number generator (RNG)

## Function Suffixes

To distinguish which function for a distribution is being used and which scale.

#### Current Suffixes

scale      | PDF   | PMF     |  CDF     | CCDF     | inverse CDF | PRNG
-----------|-------|---------|----------|----------|-------------|---------
*linear*   | n/a   |  n/a    | cdf      | ccdf     |    n/a      | rng
*log*      | log   |  log    | cdf_log  | ccdf_log |    n/a      | n/a

#### Proposed Suffixes

scale    | PDF   | PMF  |  CDF  | CCDF  | diff of CDFs | inv CDF  | PRNG
---------|-------|------|-------|-------|--------------|----------|-----
*linear* | n/a   | n/a  | n/a   | n/a   | n/a          | inv_cdf  | rng
*log*    | lpdf  | lpmf | lcdf  | lccdf | ldiff_cdf    | n/a      | n/a

Deprecate (not eliminate) existing functions.

##### Discussion

* The `pmf` vs. `pdf` suffix was up in the air after our last discussion.

* For inverse CDF, we may want an alternative parameterization with a logit-scale parameter.

* Andrew suggests we should only supply the log functions where relevant and drop the "l" suffix and "pdf" and "pmf" suffixes, so that's

scale   | PDF   | PMF  |  CDF  | CCDF  | diff of CDFs
--------|-------|------|-------|-------|--------------
*log*   |  ε    |  ε   |   cdf |  ccdf | diff_cdf

where `ε` is the empty string, and then

scale    | RNG | inv CDF
---------|-----|--------
*linear* | rng | inv_cdf



## Vertical Bar Notation

To distinguish conditional densities from joint densities in the notation.

#### Current

`normal_log(y, mu, sigma)`

#### Proposed

For pdfs and pmfs, we use the bar to separate the outcome from the parameters:

```
normal_lpdf(y | mu, sigma)
```

Ditto for cdfs, etc.

```
normal_lccdf(y | mu, sigma);
```

and for multivariate outcomes, we could even write

```
foo_lpdf(y1, y2 | alpha, beta)`
```

#### Discussion

* Unconventional
    * not found in any other programming language
    * users may infer some kind of sampling rather than evaluation

* Not clear how we resolve pmf vs. pdf when it's mixed (e.g., a mixture of a pdf and pmf, as in a proper spike-and-slab)

* Adds one more horizontal space over `,`

## Normalization Control

The current difference between sampling notation and functions is confusing to everyone and it would be nice to be able to control it.

#### Current

Sampling statement does not normalize:
```
y ~ normal(mu, sigma);
```

Function call does normalize:
```
increment_log_prob(normal_log(y, mu, sigma));
```

#### Proposed

The name of the function will get a `_norm` suffix before the `lpdf`, as in:

```
cauchy_norm_lpdf(y | mu, tau);    // normalized
cauchy_lpdf(y | mu, tau);         // unnormalized
```

#### Discussion

* Ideally, everything would be normalized everywhere, but it's a computational burden

* The original proposal was for
    * `cauchy_lpdf<norm=true>(y | mu, tau)` : normalized
    * `cauchy_lpdf<norm=false>(y | mu, tau)` : unnormalized
    * `cauchy_lpdf(y | mu, tau)` : undecided

* Using just `cauchy_lpdf<norm>` rather than `cauchy_lpdf<norm=true>` is suboptimal if we want other arguments with values.

* The default is *unnormalized*
    * this is going to lead to a lot of confusion from users who expect normalization as the default
    * it's going to lead to confusion for users about where normalization is needed

* It would be great to only compute normalizing constants once on outside and use all normalized inside, but
    * won't work if there is branching on parameters
    * need the values on the inside for mixture models

* Aki suggests following Andrew's *BDA* notation with `q()` being unnormalized form of `p()`, so
    * instead of `beta_lpdf(y | a, b)` for the unnormalized pdf, write `beta_lqdf(y | a, b)`
    * would be confusing given `q` usage for quantiles in R


## Scalar/Vector Output Control

Right now, the densities return the sum of log densities for vector inputs;  it'd be nice to be able to control this and produce a vector of outputs, which is necessary for WAIC and other similar calculations.

See:  https://github.com/stan-dev/stan/issues/1697

#### Current

If y is vector (or array) sampling statement and function call compute sum of log densities
```
y ~ normal(mu, sigma);
sum_log_lik <- normal_log(y, mu, sigma)
```

In generative quantities, only the unvectorized form is alllowed.
```
for (n in 1:N)
 log_lik[n] <- normal_log(y[n], mu, sigma)
sum_log_lik <- sum(log_lik);
```

#### Proposed

To be able to use vectorized form in generated quantities (and maybe sometimes elsewhere?) PDF has special arguments for vector output, defaulting to `false`:

```
vector[N] y;
vector[N] ll;
...
ll <- vec_normal_norm_lpdf(y | mu, tau);
```

#### Discussion

* These suffixes are going to start piling up and nobody's going to be able to remember the order.

* Current form is difficult because use vectorized sampling statements, but not in generated quantities with RNGs or evaluation for WAIC, etc.

* Not clear we really are going to keep computing WAIC, etc., given the current focus on cross-validation.


## Increment Log Density Statement

Make it clear that we're incrementing an underlying accumulator rather than forward sampling or defining a directed graph.

#### Current

1.  `increment_log_prob(normal_log(y, mu, sigma));`

1.  `y ~ normal(mu, sigma);`

#### Proposed

Replace both of these with a single version:

1.  `target += normal_lpdf(y | mu, sigma);` where `target` is the target log density.

Furthermore,

1.  Deprecate `<-` for assignment and replace with `=`

1.  Allow general use of `+=` for incrementing variables.

1.  Do not allow general access to `target` --- it only lives on left of `+=`;  we supply an existing function to get its value.

1.  Make `target` a reserved word (minor backward-compatibility breaking)

1.  Do not allow vectors on the right of `+=` meaning to sum them all (currently, `increment_log_prob()` allows that (have to be careful here in our translator).

#### Discussion

* `target` is sufficiently neutral that nobody's going to overanalyze it

* First consideration was to using streaming operator
    * `target << normal_lpdf(y | mu, sigma);`
    * decided it was too confusing because `<<` is unfamiliar and it's not really streaming
    * `<< normal_lpdf(y | mu, sigma)` and just plain `normal_lpdf(y | mu, sigma)` also rejected

* Could avoid streaming altogether and use a new symbol for the prefix like:

```
@normal_lpdf(mu | 0, 1);
@normal_lpdf(beta | mu, sigma);
@cauchy_lpdf(sigma | 0, 2.5);
```

but nobody liked that idea other than me (Bob).

## Link Functions in Density Names

Current approach doesn't scale because we need to mark both link function (type of parameter) and name of function and its output.

#### Current

```
poisson_log(alpha) == poisson(exp(alpha))
bernoulli_logit(alpha) == bernoulli(inv_logit(alpha))
```

#### Proposed

Keep as is.


#### Discussion

* Original plan from Aki was to do this:

```
poisson<link=log>(alpha)
bernoulli<link=logit>(alpha)
```

* But that's verbose and then have to deal with multiple argument type names

* User's may overgeneralize from the general syntax to assume arguments that don't exist
    * so just use `bernoulli_logit` instead of `bernoulli<link=logit>`


## User-Defined Functions

#### Current

Use current versions of function names, with `_log` allowing sampling statement use and "_lp" allowing access to log density.

#### Proposed

1. Use proposed versions of suffixes, with `_lpdf` and `_cdf` and `_ccdf` and `_diff_cdf` (when we get to it) supporting vertical bar notation.

1.  Use `_target` suffix instead of `_lp` (deprecate `_lp`) to allow access to `target`

1. Deprecate (not eliminate for now) use of `_log` and `_lp` suffixes in user-defined functions.

#### Discussion

* I think everyone's OK with this.

## Examples

#### Simple linear regression

```
data {
  int N;
  vector[N] y;
  vector[N] x;
}
paramters {
  real alpha;
  real beta;
  real<lower=0> sigma;
}
model {
  target += normal_lpdf(alpha | 0, 10);
  target += normal_lpdf(beta | 0, 2);
  target += cauchy_lpdf(sigma | 0, 2.5);
  target += normal_lpdf(y | alpha * x + beta, sigma);
}
```

#### Simple Normal Mixture

```
model {
  target += normal_lpdf(mu | 0, 1);
  target += lognormal_lpdf(sigma | 0, 1);
  target += beta_lpdf(lambda | 2, 2);
  for (n in 1:N)
    target += log_sum_exp(log(lambda) + normal_norm_lpdf(y[n] | mu[1], sigma[1]),
                          log1m(lambda) + normal_norm_lpdf(y[n] | mu[2], sigma[2]));
}
```

#### Hurdle

```
model {
  target += beta_lpdf(theta | 2, 2);
  target += gamma_lpdf(lambda | 2, 2);
  for (n in 1:N) {
    target += bernoulli_lpmf(y[n] == 0 | theta);
    if (y[n] > 0)
      target += poisson_lpmf(y[n] | lambda) T[1,];
  }
}
```

#### Measurement Error (Rounding)

```
data {
  int<lower=0> N;
  vector[N] y;
}
parameters {
  real mu;
  real<lower=0> sigma_sq;
  vector<lower=-0.5, upper=0.5>[5] y_err;
}
transformed parameters {
  real<lower=0> sigma;
  vector[N] z;
  sigma = sqrt(sigma_sq);
  z = y + y_err;
}
model {
  target += -2 * log(sigma);
  target += normal_lpdf(z | mu, sigma);
}
```

#### Left Censoring

```
data {
  int<lower=0> N_obs;
  int<lower=0> N_cens;
  real y_obs[N_obs];
}
parameters {
  real<upper=min(y_obs)> L;
  real mu;
  real<lower=0> sigma;
}
model {
  target += normal_lpdf(L | mu, sigma);
  target += normal_lpdf(y_obs | mu, sigma);
  target += N_cens * normal_lcdf(L | mu, sigma);
}
```

#### Occupancy Model

```
functions {
  matrix cov_matrix_2d(vector sigma, real rho) {
    matrix[2,2] Sigma;
    Sigma[1,1] = square(sigma[1]);
    Sigma[2,2] = square(sigma[2]);
    Sigma[1,2] = sigma[1] * sigma[2] * rho;
    Sigma[2,1] = Sigma[1,2];
    return Sigma;
  }

  real lp_observed(int x, int K, real logit_psi, real logit_theta) {
    return log_inv_logit(logit_psi)
      + binomial_logit_lpmf(x | K, logit_theta);
  }

  real lp_unobserved(int K, real logit_psi, real logit_theta) {
    return log_sum_exp(lp_observed(0, K, logit_psi, logit_theta),
                       log1m_inv_logit(logit_psi));
  }

  real lp_never_observed(int J, int K, real logit_psi, real logit_theta,
                         real Omega) {
      real lp_unavailable;
      real lp_available;
      lp_unavailable = bernoulli_lpmf(0 | Omega);
      lp_available = bernoulli_lpmf(1 | Omega)
        + J * lp_unobserved(K, logit_psi, logit_theta);
      return log_sum_exp(lp_unavailable, lp_available);
    }
}
data {
  int<lower=1> J;  // sites within region
  int<lower=1> K;  // visits to sites
  int<lower=1> n;  // observed species
  int<lower=0, upper=K> x[n,J];  // observed count of species i at site j
  int<lower=n> S;  // superpopulation size
}
parameters {
  real alpha;  //  site-level abundance
  real beta;   //  site-level detection
  real<lower=0, upper=1> Omega;  // availability of species

  real<lower=-1,upper=1> rho_uv;  // correlation of (abundance, detection)
  vector<lower=0>[2] sigma_uv;    // sd of (abundance, detection)
  vector[2] uv[S];                // species-level (abundance, detection)
}
transformed parameters {
  vector[S] logit_psi;    // log odds  of occurrence
  vector[S] logit_theta;  // log odds of detection
  for (i in 1:S)
    logit_psi[i] = uv[i,1] + alpha;
  for (i in 1:S)
    logit_theta[i] = uv[i,2] + beta;
}
model {

  // priors
  target += cauchy_lpdf(alpha | 0, 2.5);
  target += cauchy_lpdf(beta | 0, 2.5);
  target += cauchy_lpdf(sigma_uv | 0, 2.5);
  target += beta_lpdf((rho_uv + 1) / 2 | 2, 2);
  target += multi_normal_lpdf(uv | rep_vector(0, 2), cov_matrix_2d(sigma_uv, rho_uv));
  target += beta_lpdf(Omega | 2, 2);

  // likelihood
  for (i in 1:n) {
    target += bernoulli_lpmf(1 | Omega); // observed, so available
    for (j in 1:J) {
      if (x[i,j] > 0)
        target += lp_observed(x[i,j], K, logit_psi[i], logit_theta[i]);
      else
        target += lp_unobserved(K, logit_psi[i], logit_theta[i]);
    }
  }

  for (i in (n + 1):S)
    target += lp_never_observed(J, K, logit_psi[i], logit_theta[i], Omega);
}

generated quantities {
  real<lower=0,upper=S> E_N;   // model-based expected population size
  int<lower=0,upper=S> E_N_2;  // posterior simulated population size
  vector[2] sim_uv;
  real logit_psi_sim;
  real logit_theta_sim;

  E_N = S * Omega; // pure expected by model

  E_N_2 = n;
  for (i in (n+1):S) {
    real lp_unavailable;
    real lp_available;
    real Pr_available;
    lp_unavailable = bernoulli_norm_lpmf(0 | Omega);  // norm doesn't really do anything here
    lp_available = bernoulli_norm_lpmf(1 | Omega)
      + J * lp_unobserved(K, logit_psi[i], logit_theta[i]);
    Pr_available = exp(lp_available
                       - log_sum_exp(lp_unavailable, lp_available));
    E_N_2 += bernoulli_rng(Pr_available);
  }

  sim_uv = multi_normal_rng(rep_vector(0,2),
                            cov_matrix_2d(sigma_uv, rho_uv));
  logit_psi_sim = alpha + sim_uv[1];
  logit_theta_sim = beta + sim_uv[2];
}
```
