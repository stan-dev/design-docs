- Feature Name: Latent Data Block
- Start Date: 09-30-2024

# Summary
[summary]: #summary

This design doc proposes adding a new block to the Stan language
called `latent data` with a range of proposed uses.  The new block
will appear between the transformed parameter and model blocks and be
executed once at the beginning of each iteration using `double` values
for all parameters and transformed parameters.  The `latent data`
variables will then be in scope for the rest of the program, but
cannot be modified.

# Motivation
[motivation]: #motivation

The motivation is to support three new key features for Stan:

* Cut-based reasoning for random quantities 
* Multiple imputation of missing data
* Gibbs sampling discrete parameters


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Stan will support a new block, `latent data`, that is required to
appear between `transformed parameters` and the `model` block.
Variables may be declared in the same way as for other blocks.  All
data types are allowed, including integers.

Within the `latent data` block, all variables and functions
declared in earlier blocks (`functions`, `data`, `transformed data`,
`parameters`, and `transformed parameters`) will be available.
Variables declared in the `latent data` block will be visible to
all later blocks (`model` and `generated quantities`).

The `latent data` block allows access to any function not involving
the target density, including random number generators. It disallows
access to the target log density, so the following operations are not
available: target function `target()`, target increment statement
`target += <expression>;`, distribution statement `A ~ foo(B);`, and
functions ending in `_lp`.


## Gibbs sampling discrete parameters

Here's an example that encodes a normal mixture model by sampling
discrete parameters. The generative process for a data item first
generates a random component $z_n \sim \textrm{bernoulli}(\lambda)$ and then
generates a data item $y_n \sim \textrm{normal}(\mu_{z_n},
\sigma_{z_n}).$

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
latent data {
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
  sum(z) ~ binomial(lambda, N);

  y ~ normal(mu[z], sigma[z]);

  mu ~ normal(0, 1);
  sigma ~ exponential(1);
  lambda ~ beta(2, 2);
}
```

The `latent data` block does for `z` does not look like the simple
generative model.  That's because the `latent data` block must code
up the conditional distribution of $z$ given $y, \lambda, \mu,$ and
$\sigma$.  The conditional here requires the same derivation as
marginalization. 

This is not an efficient way to code this model, but it's the simplest
possible example of using the `latent data` block for Gibbs
sampling of discrete parameters, such as $z$ in this example.  More
useful examples might include variable selection with a spike and slab
prior.

## Block Gibbs for hierarchical models

Neal (2011, p. 143) proposes a scheme whereby HMC is only used for the
low-level parameters of a hierarchical model, with the population
parameters being sampled with block Gibbs.  In a simple case, suppose
we have a model with $N$ binary observations in $K$ groups with group
indicator $\text{group}$.  The likelihood will be $y_n \sim
\text{bernoulli}(\textrm{logit}^{-1}(\alpha_{\text{group}[n]}))$ and
the prior $\alpha_k \sim \textrm{normal}(\mu, \sigma)$ with conjugate
priors $\sigma^2 \sim \textrm{invGamma}(a, b)$ and $\mu \sim
\textrm{normal}(0, \sigma)$.

We can use conjugacy to define the posterior for the hyperpriors $\mu,
\sigma^2$ analytically given $\alpha$,

$\sigma^2 \sim \text{invGamma}(a + K/2, b + \text{sum}(\alpha - \overline{\alpha}) / 2 + K \cdot \overline{\alpha} / (2 \cdot (K + 1))),$

where $\overline{\alpha} = \text{mean}(\alpha)$.  The conjugate posterior for
$\mu$ given $\alpha$ and $\sigma^2$ is

$\mu \sim \text{normal}(K \cdot \overline{\alpha} / (K + 1), \sigma /
\sqrt{K + 1}),$

where as usual, we are parameterizing the normal distribution by its scale.

With all of this, we can code Neal's recommendation as follows.

```stan
data {
  int<lower=0> a, b;  // gamma prior on variance of effects
  int<lower=0> K;
  int<lower=0> N;
  array[N] int<lower=1, upper=K> group;
  vector<lower=0, upper=1>[N] y;
}
parameters {
  vector[K] alpha;
}
latent data {
  real alpha_bar = mean(alpha);
  real<lower=0> sigma_alpha
    = sqrt(inv_gamma_rng(a + K / 2,
                         b + 0.5 * sum((alpha - alpha_bar)^2)
                           + K * alpha_bar^2 / (2 * (K + 1))));
  real mu_alpha = normal_rng(K * mean(alpha) / (K + 1),
                             sigma_alpha / sqrt(K + 1));
                      
}
model {
  alpha ~ normal(mu_alpha, sigma_alpha);
  y ~ bernoulli_logit(alpha[group]);
}
```

The latent data block takes a posterior draw for `sigma_alpha` and
`mu_alpha` conditioned on `alpha`, then HMC/NUTS is only used to
update the low-level parameters `alpha` based on the likelihood and
prior as defined in the model block.

## Cut and injected randomness

Here is a simple use case which uses the latent data block to
generate random sensitivity and specificity values from a population
mean and covariance.  The population model is used to generate random
sensitivity and specificity values per iteration, pushing their
uncertainty through the model based inferences.

```stan 
data {
  vector[2] loc_ss; 
  cov_matrix[2, 2] Sigma_ss; 
  int<lower=0> N; 
  int<lower=0, upper=N> n; 
}
parameters {
  real<lower=0, upper=1> prev;
}
latent data {
  vector<lower=0, upper=1>[2] sens_spec 
    = inv_logit(multi_normal_rng(loc_ss, Sigma_ss)); 
}
model {
  real sens = sens_spec[1]; 
  real spec = sens_spec[2]; 
  real pos_test_prob = prev * sens + (1 - prev) * (1 - spec); 
  n ~ binomial(pos_test_prob, N); 
  prev ~ beta(2, 100); 
}
```

This is related to "cut" in Gibbs sampling (Plummer 2015), which
restricts the flow of information during parameter inference.  Cut is
popular in pharmacometric modeling when the pharmacokinetic model is
well understood and well specified, but the pharmacodynamic model is
less well understood, because it prevents the dynamics model from
unduly distorting the kinetic model.

The simplest example of cut would assume we have some calibration data
for sensitivity $(N^\text{sens}, n^\text{sens})$ and for specificity
$(N^\text{spec}, N^\text{spec})$, which we can model as binomial, e.g.,
$n^\text{sens} \sim \textrm{binomial}(\textit{sens}, N^\text{sens})$,
where $\textit{sens} \in (0, 1)$ is the sensitivity parameter.

```stan 
data {
  vector[2] loc_ss; 
  cov_matrix[2, 2] Sigma_ss; 
  int<lower=0> N; 
  int<lower=0, upper=N> n;
  int<lower=0> N_sens;
  int<lower=0, upper=N_sens> n_sens;
  int<lower=0> N_spec;
  int<lower=0, upper=N_spec> n_spec;
}
parameters {
  real<lower=0, upper=1> prev;
  real<lower=0, upper=1> sens_cut;
  real<lower=0, upper=1> spec_cut;
}
latent data {
  // cuts inference to sens and spec
  real sens = sens_cut;
  real spec = spec_cut;
}
model {
  // allows inference for cut parameters from calibration data
  n_sens ~ binomial(N_sens, sens_cut);
  n_spec ~ binomial(N_spec, 1 - spec_cut);

  real pos_test_prob = prev * sens + (1 - prev) * (1 - spec); 
  n ~ binomial(pos_test_prob, N); 
  prev ~ beta(2, 100); 
}
```

In this example, `sens_cut` and `spec_cut` work like ordinary
parameters. Their posterior will be defined by their use in the model
block.  The variables `sens` and `spec`, which are used to define the
positive test probability and hence estimate `prevalence`, do not feed
information back to `sens_cut` and `spec_cut`.  The values of `sens`
and `spec` get updated once at the beginning of each iteration based
on `sens_cut` and `spec_cut` in the previous iteration.  Assigning to
`sens` and to `spec` cuts feedback to `sens_cut` and `spec_cut`.


## Multiple imputation for missing data

One standard approach to multiple imputation is to use an imputation
model on the data, then propgate multiple data sets through to
inference.  That is, we start with a data set $y^\text{inc}$ with
missing data, then impute $y^{\text{miss}(n)}$ for multiple $n$ and
define a total of $N$ complete data sets $y^{(n)} = y^\text{inc},
y^{\text{miss}(n)}$.  For each of these $N$ data sets, we take
$M posterior draws, $\theta^{(n, m)} \sim p(\theta \mid y^{(n)})$.  We
then perform standard plug-in Monte Carlo inference with all $N \cdot
M$ draws.

We will assume that there is a simple missing count data item and we
will deal with the missingness through a Poisson regression.

```stan
data {
  int<lower=0> N;
  vector[N] x1_obs, x2_obs;
  int<lower=0, upper=1>[N] miss1, miss2; 
  vector[N] y;
}
parameters {
  real alpha1, alpha2;
  real<lower=0> sigma1, sigma2;
  real beta1, beta2;
  real<lower=0> sigma;
  
}
latent data {
  vector[N] x1 = x1_obs, x2 = x_obs;
  for (n in 1:N) {
    if (missing1[n]) {
      x1[n] = normal_rng(alpha1 * x2[n], sigma1);
    }
    if (missing2[n]) {
      x2[n] = normal_rng(alpha2 * x1[n], sigma2);
    }
  }
}
model {
  x1 ~ normal(alpha1 * x2, sigma1); 
  x2 ~ normal(alpha2 * x1, sigma2);
  y ~ normal(beta1 * x1 + beta2 * x2, sigma);
}
```

The result will be a multiple imputation, not a coherent joint
Bayesian model.  This will work even if the missing data is discrete
or the conditional distributions are not coherent. 

## Stochastic gradient descent

The usual model in Stan evaluates the likelihood for the given data
set and a prior.  There has, until now, never been a good way to do
stochastic gradient descent over subsampled data.  Now we can do
that.  This is the simplest possible example.  Suppose we start with
this model.

```stan
data {
  int<lower=0> N;
  array[N] int<lower=0, upper=1> y;
}
parameters {
  real<lower=0, upper=1> theta;
}
model {
  theta ~ beta(5, 5);
  y ~ bernoulli(theta);
}
```

We can move to stochastic gradient descent by randomly subsampling `y`
in the `latent data` block.  As we do this, it's traditional to
scale the likelihood to match the original data size.


```stan
data {
  int<lower=0> N;
  int<lower=0> N_sub;
  array[N] int<lower=0, upper=1> y;
}
transformed data {
  real one_over_N_sub = 1.0 / N_sub;
  real N_over_N_sub = N * one_over_N_sub;
  simplex[N_sub] unif = rep_vector(one_over_N_sub, N_sub);
}
parameters {
  real<lower=0, upper=1> theta;
}
latent data {
  array[N_sub] y_sub;
  for (n in 1:N_sub) {
    y_sub[n] = categorical_rng(unif);
  }
}
model {
  theta ~ beta(5, 5);
  # scale data weight to match population size
  target += N_over_N_sub * bernoulli_lpmf(y_sub | theta);
}
```

If you plug this model into optimization, by default it will apply
quasi-Newton steps using stochastic gradient.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation 

## Stan Reference Manual

Stan's block structure and execution model is described in the
reference manual in the
[Program Blocks chapter](https://mc-stan.org/docs/reference-manual/blocks.html)
and the
[Program Execution chapter](https://mc-stan.org/docs/reference-manual/execution.html).
This feature will add a new section to the program blocks chapter,
which will read as follows.

### Program Blocks for latent data

The latent data block appears after the transformed parameters block
but before the odel block.  Like the parameters, transformed
parameters, and generated quantities, the latent data will be included
in the output and the top-level variables will be available in all
later blocks.  Latent data will also have access to the data,
transformed data, parameters, and transformed parameters.

#### Iteration number 

The iteration number can be optionally set in the latent data block 
from the outside.  There will be an `iteration_number__` parameter 
reserved.  It will be set to 0 by default, but can be updated by an 
external algorithm. 

### Program Execution for latent data

For all of our inference algorithms (HMC, ADVI, Pathfinder,
optimization, Laplace), the latent data block should be executed once
at the start of each iteration.  For example, in Hamiltonian Monte
Carlo, the latent data block is executed once based on the initial
parameter values, then the values are used without changing each
leapfrog iteration.  For optimization, each iteration of L-BFGS should
evaluate the latent data block once per iteration and leave it fixed
through the line search. The latent data needs to be executed before
the model block.

By default, the latent data block will be empty and there will be
nothing to compute.  This should be possible to set up so that all of
the inference methods are backwards compatible.

As with blocks other than the parameters block, any constraints on the
declared variables will be checked at the end of the block and an
exception will be raised if they are violated, which will cause the
current iteration in any of the algorithms to be rejected.

## C++ model class  

The `latent data` block will be executed with primitive (`double` and
`int` in C++) variables, just like the `generated quantities` block.
This effectively "cuts" the gradient information from propagating back
through the latent data block.  Nevertheless, computation in the
latent data block can affect what happens in the model block by
defining new variables on which the model block may condition.


### Review of model class design

Stan's transpiler, `stanc3`, converts Stan code to a C++ class
definition along with some helper functions.  In order to provide a
workable interface to the superclass without invoking virtual function
calls, the model class follows the
[curiously recurring template pattern](https://en.wikipedia.org/wiki/Curiously_recurring_template_pattern)
(CRTP). The code generated by the transpiler for the model `foo`
declares a class in the folloiwng way.


```cpp
class foo_model final : public model_base_crtp<foo_model> {

}
```

The `model_base_crtp` then provides CRTP-based implementations of
methods for I/O that depend on features of the model.  It is defined
to extend the `model_base` class, which is used by the external
interfaces.

To deal with construction, the generated C++ code for a model also
includes a generic factory method to return a base model.

```cpp
stan::model::model_base&
new_model(stan::io::var_context& data_context, unsigned int seed,
          std::ostream* msg_stream);
		  ```

This simply creates an instance of `foo_model` with the specified
arguments and returns it.

For reference, here are links to the full definitions from the
`stan-dev/stan` GitHub repository:

* [`model_base.hpp`](https://github.com/stan-dev/stan/blob/develop/src/stan/model/model_base.hpp)
* [`model_base_crtp.hpp`](https://github.com/stan-dev/stan/blob/develop/src/stan/model/model_base_crtp.hpp)

### Representing the latent data

The design is based on an object-based representation of the latent
data using code generation.  For example, suppose the latent data
block is defined as follows.


```cpp
latent data {
  real<lower=0, upper=1> sens = beta_rng(98, 2);
  real<lower=0, upper=1> spec = beta_rng(95, 5);
}
```

This will lead to the code generation of a class in the generated
`.hpp` file for the model following the CRTP.

```cpp
struct latent_data : public latent_data_base_crtp<latent_data> {
  int iteration_number__;  // included by default in all latent_data
  double sens;
  double spec;
};
```

Here, the `latent_data_base_crtp` will extend `latent_data_base`,
following the pattern used for the model class.

### Constructing the latent data generically

Just like the model class, this will require a generic factory method,
though in this case, no arguments are required as it will be used like
a simple `struct`.

```cpp
latent_data_base& new_latent_data();
```

This must then get passed where necessary and cast into the relevant
type in the class definition, as shown in the next section.


### Generating the latent data

An additional method in the model class will be required to populate 
the latent data. 

```cpp
template <typename RNG> inline void
set_latent_data(
    const VectorXd& params_r, 
    latent_data_base& ldb, 
    RNG& base_rng, 
    std::ostream* pstream=nullptr) const {
  latent_data& latent_data__ = static_cast<latent_data&>(ldb);
  ... code generated to populate latent_data__ ...
}
```

Because it does not use anything specific to the specific model class,
this can be implemented inthe `latent_data_base_crtp` class using the
CRTP.

```
template <class Derived>
class latent_data_base_crtp<Derived> {
template <typename RNG> inline void
set_latent_data(
    const VectorXd& params_r, 
    latent_data_base& ldb, 
    RNG& base_rng, 
    std::ostream* pstream=nullptr) const {
	static_cast<Derived&>(ldb).set_latent_data(params_r, ldb,
                                               base_rng, pstream);
};
```

The concrete `latent_data` class implemented along with the model
class will be responsible for holding the memory for any data needed
in latent data, such as `Eigen::Matrix` or `std::vector`
instances. By reusing the same `latent_data` variable (per thread),
variables can be reset rather than allocating and freeing each
evaluation.

### The `latent_data_base` class

The `latent_data_base` class will only know about how to write
iteration numbers and how to write out variables and variable names.

```cpp
class latent_data_base {
  int iteration_number_;
  int get_iteration_number() {
    return iteration_number_;
  }
  void set_iteration_number(int n) {
    iteration_number_ = n;
	}
  virtual void num_variables() const = 0;
  virtual void write_variable_names(std::vector<string>& names) const = 0;
  virtual void write_variable_values(std::vector<double>& values) const = 0;
};
```

The CRTP class will impelement the three virtual functions using the
CRTP in the usual way.  
This uses inheritance from the base class, but the cost is relatively
low in that it is only done once per iteration.  This follows the way
Stan's `model_base` class is designed.


### Generalized `log_prob` method

The existing `log_prob` method must be updated to maintain backward
compatibility: 

```cpp
template <bool propto__, bool jacobian__, typename T_> inline T_
log_prob(Eigen::Matrix<T_,-1,1>& params_r, 
         const latent_data& latent_data__,
         std::ostream* pstream = nullptr) const;
```

In this case, the `log_prob` code generation must be updated to copy
all of the generated data into scope.

```cpp
template <bool propto__, bool jacobian__, typename T_> inline T_ 
log_prob(
    Eigen::Matrix<T_,-1,1>& params_r,  
    const latent_data_base& ldb,
    std::ostream* pstream = nullptr) const {
  const latent_data& latent_data = static_cast<latent_data&>(ldb);
  double sens = latent_data__.sens;
  double spec = latent_data__.spec;
  ... code generate as before with sens/spec in scope ...
}
```

Note that it is implemented generically using `latent_data_base` for
use from outside interfaces.


### Generalized `write_array` method

The existing `write_array` method must be similarly updated, because
now it is going to need to write the generated data.

```cpp
template <typename RNG> inline void
write_array(RNG& base_rng, Eigen::Matrix<double,-1,1>& params_r,
            Eigen::Matrix<double,-1,1>& vars,
            const bool emit_transformed_parameters = true,
			const bool emit_generated_quantities = true,
			std::ostream* pstream = nullptr,
	        const latent_data_base& ldb = dummy_latent_data()) const {
  latent_data& latent_data = static_cast<latent_data&>(ldb);
  ...			
}
```

As with the `log_prob` method, this one also takes a generic
`latent_data_base` as an argument to permit use from the outside.

By making it the last argument and giving it a dummy value (just a
no-data dummy implementation), it will remain backward compatible to
outside interfaces that have not yet been made aware of `latent_data`.


### BridgeStan

BridgeStan can be updated to mimic the updates to the Stan model
class.

# Drawbacks
[drawbacks]: #drawbacks

1. It will require additional documentation and tests, increasing
   Stan's long-term maintenance burden and the overhead required for
   someone to understand what it's doing. 
2. Using "cut"-based inference does not perform full Bayesian
   inference, and there's a risk that this will confuse our users. 
3. Using this block for Gibbs sampling will be less efficient than
   marginalization and may tempt many users to define poorly mixing
   models. 
4. There is nothing enforcing consistency of the conditional
   distributions when doing Gibbs, so this will be easy to get wrong
   and there won't be an easy way to test that this is right.
5.  Introducing a `latent data` block opens up a back door approach to
    converting real numbers to integers, which can be done with
    `to_int(data real)` if the argument is "data" (i.e., a primitive
    rather than autodiff variable). 

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

## Alternatives

To support pure uncertainty propagation and non-interacting forms of
cut (i.e., ones that don't use any of the model parameters), we can
use multiple imputation in the traditional way by running multiple
Stan programs in sequence. This is less efficient and not as general.

There is no alternative for the Gibbs-based discrete parameter
inference. 

## Impact of not implementing

Users will find it impossible to do discrete sampling that interacts
with the model and will find it very challenging to do missing data
imputation.  


# Unresolved questions
[unresolved-questions]: #unresolved-questions

None known.


# Citations

* Plummer, Martyn. 2015.  Cuts in Bayesian graphical models.  *Statistical Computing* 25:37--43.

* Wikipedia.  Gibbs Sampling.  https://en.wikipedia.org/wiki/Gibbs_sampling

* Neal, Radford. 2011.  MCMC using Hamiltonian dynamics. In *Handbook of
  MCMC.* CRC Press.
