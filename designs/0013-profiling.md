- *Feature Name:* profiling-stan-AD
- *Start Date:* NA
- *RFC PR(S):*
- *Stan Issue(s):*

# Summary
[summary]: #summary

The goal of this design is a clean and simple interface to profiling Stan models. Specfically, profiling single nodes and subexpressions of the autodiff (AD) expression graph for the model and transformed parameters blocks and function evaluation for the generated quantities and transformed data blocks.

# Motivation
[motivation]: #motivation

1. identifying bottlenecks in a Stan model

Currently, identifying bottlenecks requires a good understanding of both autodiff and its implementation in Stan Math. And even with that knowledge, its not feasible to confirm an assumed bottleneck is a true bottleneck. Optimization of a Stan model for faster per-gradient execution is therefore very difficult.

2. evaluating different approaches for a section of a model

It is very difficult to evaluate how a different approach to a secton of a model influences per-gradient performance as even small numerical differences can lead to different behaviour of the sampler and the entire model must to be run with different seeds for a fair comparison. And even then, the effect of the changes can be difficult to identify in the overall noise of a model execution that includes IO and other parts of a model.

For these cases, profiling a subexpression in the AD expression graph is required. For some functions it can still be seed-dependent, but to a much lesser extent especially with increasing numbers of gradient/function evaluations. 

Examples of cases where evaluating is very useful: evaluating paralleliziation approaches (reduce_sum, map_rect, GPUs), identifying the effect of using a different solver or a different expression.

# Profiling on the Stan model level
[stan-model-profiling]: #stan-model-profiling

A user defines profiling sections inside a model by writing `profile("profile-section-name");`. The argument to `profile()` is always a string literal. A profile will measure execution time and other AD information for all expressions in the Stan lines where the profile is in scope.

An model with examples of its usage is shown below:

```stan
data {
  int<lower=1> N;
  real x[N];
  vector[N] y;
}
transformed data {
  profile("tdata");
  vector[N] mu = rep_vector(0, N);
}
parameters {
  real<lower=0> rho;
  real<lower=0> alpha;
  real<lower=0> sigma;
}
transformed parameters {
  matrix[N, N] L_K;
  matrix[N, N] K;
  {
    profile("gp");
    K = gp_exp_quad_cov(x, alpha, rho);
  }
  real sq_sigma = square(sigma);

  for (n in 1:N) {
    profile("add_diagonal");
    K[n, n] = K[n, n] + sq_sigma;
  }    

  profile("cholesky");
  L_K = cholesky_decompose(K);
}
model { 
  {
    profile("priors");
    rho ~ inv_gamma(5, 5);
    alpha ~ normal(0, 1);
    sigma ~ normal(0, 1);
  }
  
  {
    profile("likelihood");
    y ~ multi_normal_cholesky(mu, L_K);
  }
}
```

The model uses six profiles: 
- `tdata` profiles the only statement in the transformed data block
- `gp` profiles the `gp_exp_quad_cov` function
- `add_diagonal` profiles the for loop. Profiles in a loop will accumulate as will profiles with the same name on different lines.
- `cholesky` profiles the Cholesky decomposition as it goes out of scope at the end of the transformed parameters block.
- `priors` profiles the three prior definitons in the model block
- `likelihood` profiles the `multi_normal_cholesky_lpdf` function

There are no other changes to Stan models or language. 

Note that we can not profile the following as only parameter declarations are allowed in the `parameters` block.
```stan
parameters {
  real<lower=0> rho;
  real<lower=0> alpha;
  real<lower=0> sigma;
}
```
This means that the `lower`, `upper`, `multiply` and `offset` constraints/transforms can not be profiled. Given that these are less likely to be a bottleneck we decided to not change the Stan language rules to allow `profile()` in the parameters block for only this use-case.

# Stanc3 - changes to the generated C++

The C++ code generated from Stan models will be changed accordingly:

- all generated C++ models representing Stan models will gain a private member `profiles__`. This member will represent the map of all profile information.


- C++ call


# The CmdStan interface

- printing after finishing
- `profiling_file = filename.csv`

# The Stan Math implementation


# Disadvantages of this approach
[Disadvantages]: #Disadvantages

The shortcomings of this approach are: 

- we can not profile transforms of the parameters defined in the parameters block

We could allow `profile()` to be the only accepted function call in the parameters block, if we decide we want to support this as well, though that is a significant change to the language rules.

- profiling in recursive functions is limited. The following function would result in a runtime error.
```stan
real fun(real a) {
  profile("recursive-fun");
  real b;
  if (a < 1.0) {
    b = fun(a - 1);
  } else {
    b = 1.0;
  }
  return b;
}
```

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

There are many possible alternatives to this design. Listing some of which came up in the current discusions:

- profile every line of a Stan model automatically

- profile every block inside a Stan program automatically (top-level blocks as well as inner blocks). Label profiles based on line numbers.

- use other Stan language interfaces. Examples:

```stan
start_profiling("profile-name");
function_call();
stop_profiling("profile-name");

profile("profile-name") {
  function_call();
}

@profile("profile-name");
{
  function_call();
}

@profile("profile-name");
function_call();
```

- have profiling be a separate service of Stan, similar to how diagnose is implemented. The drawback of this is that the user profiles their model in a different setting, with one set of parameter values at a time.

# Prior art
[prior-art]: #prior-art

There is no Stan-specific priort art for profiling. For other tools we have the following:

- TensorFlow based tools: https://www.tensorflow.org/guide/profiler with TensorBoard for visualization
- PyMC3: https://docs.pymc.io/notebooks/profiling.html
- PyTorch: https://pytorch.org/tutorials/recipes/recipes/profiler.html
- Pyro: to the best of my knowledge Pyro relies on cPython for profiling. Most profiling information found with regards to Pyro is for their internal function/distribution-level testing and CI.

The Python-based tools mostly suggest using cPython for profiling the low-level functions.

# Unresolved questions
[unresolved-questions]: #unresolved-questions
 - in case of no `profile()` calls, do we want to omit the private member `profiles__` representing an empty `std::map`? 

 - how to stop profiles at the end of transformed parameters? Explicit calls to profile destructors or looping over active profiles and adding a stop var?

 - do we want to split profiling information for different stages of a Stan algorithm (warmup/sampling in MCMC, adaptation/sampling in ADVI)?

 - do we want profiling information for all gradient evaluations in CSV or other forms?

 - do we want to group labels automatically by Stan block? My inclination here is no, as it limits the users freedom.

 - do we want to provide a way to print out the profiling info in a "standard" format that can be used in visualization tools like [Chrome Tracing](https://aras-p.info/blog/2017/01/23/Chrome-Tracing-as-Profiler-Frontend/)?

