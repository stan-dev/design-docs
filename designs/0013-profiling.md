- *Feature Name:* profiling-stan-AD
- *Start Date:* 1-4-2020
- *RFC PR(S):*
- *Stan Issue(s):*

# Summary
[summary]: #summary

The goal of this is design is to make it easier to optimize Stan model performance
by to measuring how computationally expensive different parts of a model are with
a profiling interface.

# Motivation
[motivation]: #motivation

Two motivations for a profiling interface are:

1. Identifying bottlenecks in a Stan model
2. Evaluating different approaches for a section of a model

First, identifying bottlenecks requires a good understanding of both autodiff and its
implementation in Stan Math. For instance, if a function is implemented in Stan Math without
custom autodiff, it might perform slower than an algorithmically cheaper function that does
have custom autodiff. There can also be significant overhead of the autodiff that is hard to
anticipate from the structure of the Stan code itself (for instance, the speedups that
`reduce_sum` gives because of cache locality in the calculations).

Second, even with knowledge of how autodiff is implemented in Stan Math, it is often not
easy to set up an experiment to measure a piece of code or confirm that a code change has made
the model faster. The most reliable timing mechanism currently in Stan is at the model level,
which means to measure performance differences in code it is necessary to measure the
performance differences in MCMC calculations -- this is difficult to rely on because of
the potential randomness (there are single model gradients timings output by cmdstan, but
these are not very accurate).

# Profiling on the Stan model level
[stan-model-profiling]: #stan-model-profiling

The proposed profile interface is the addition of a new stan function, `profile`, which
measures the performance of all code between the statement itself and the end of the
enclosing block. The function `profile` takes one argument, a string, which is used to
summarize the timing results. This is the profile name.

For instance, in a simple linear regression the `profile` command could be used to
measure the cost of the joint density:

```
model {
  profile("model block");
  sigma ~ normal(0, 1);
  b ~ normal(0, 1);
  y ~ normal(X * b, sigma);
}
```

It could also be used to measure just the likelihood component and ignore the priors:
```
model {
  sigma ~ normal(0, 1);
  b ~ normal(0, 1);
  profile("likelihood");
  y ~ normal(X * b, sigma);
}
```

For brevity, examples of the major use-cases of `profile` are included below,
but the use cases themselves are here:

1. A `profile` statement can be used in user-defined functions, in the
`transformed data`, `transformed parameters`, `model`, and `generated quantities`
blocks.

2. A `profile` statement that times non-autodiff code will be recorded in the
same as a statement that times autodiff code (just the autodiff cost will be
zero).

3. There can be multiple `profile` statements with the same name. The name of
the profile statement has global scope - they all accumulate to one set of timers
and so will be reported in aggregate. This means profiles with the same name in
different blocks record in the same place.

4. Stan blocks `{...}` can be used to limit what a `profile` measured (and so
`profile` can be used to measure the expense of different parts of a loop or
branches of a conditional statement).

5. Timing statements can be nested, but they must be different.

6. A timing statement cannot be recursively entered

## Blocks and loops

As an extended example of how a `profile` statement works with blocks and loops,
consider the construction of the Cholesky factor of a Gaussian process kernel:

```
transformed parameters {
  matrix[N, N] L_K;
  matrix[N, N] K;
  {
    profile("gp");
    K = gp_exp_quad_cov(x, alpha, rho);
  }
  real sq_sigma = square(sigma);

  for (n in 1:N) {
    profile("add diagonal");
    K[n, n] = K[n, n] + sq_sigma;
  }    

  profile("cholesky");
  L_K = cholesky_decompose(K);
}
```

There are three profiles here. The first profile, `gp`, will time only the
statement `K = gp_exp_quad_cov(x, alpha, rho)` because its enclosing scope
ends immediately after.

The second profile, `add diagonal`, will measure the cost of each iteration
of the for loop and accumulate that under the `add diagonal` profile name.

The third profile, `cholesky`, measures only the cost of
`cholesky_decompose` before going out of scope.

## Nested profiles

Nested profiles can be used when the overall cost and the individual cost
of operations are interesting. In this case:

```stan
model {
  profile("model");
  {
    profile("prior");
    sigma ~ normal(0, 1);
    b ~ normal(0, 1);
  }
  profile("likelihood");
  y ~ normal(X * b, sigma);
}
```

## Different blocks and user-defined functions

`profile` statements are fine to use in user-defined functions, though using
one in a recursive function will result in a runtime error. In the example here,
the user-defined functions is used in multiple blocks. Because of this
the timing results reported for the profile `myfunc` will include timing from
the model block (that has autodiff and runs for every gradient evaluation) and
the generated quantities (that does not have autodiff and only runs once
for every MCMC draw that is printed).

```stan
functions {
  real myfunc(vector alpha) {
    profile("myfunc");
    ...;
  }
}
...
model {
  real x = myfunc(alpha);
  ...
}
...
generated quantities {
  real x = myfunc(alpha);
  ...
}
```

There is ambiguity in what the `myfunc` profile is timing. If in a specific
situation is was important to resolve this ambiguity, then the timing
statements should be moved from inside the function to where the function
is used:

```
model {
  real x;
  {
    profile("myfunc - model");
    x = myfunc(alpha);
  }
  ...
}
...
generated quantities {
  real x;
  {
    profile("myfunc - generated quantities");
    x = myfunc(alpha);
  }
  ...
}
```

## Note on parameters block

Because only parameter declaration statements are allowed in the `parameters`
block, `profile` cannot be used there. This means that the `lower`, `upper`,
`multiply` and `offset` constraints/transforms can not be profiled.

# Stanc3 - changes to the generated C++

The C++ code generated from Stan models will be changed accordingly:

- all generated C++ models representing Stan models will gain a private member `profiles__`. This member will represent the map of all profile information.

- C++ calls to profile will be generated as:

```cpp
profile id_X = profile(const_cast<profile_map&>(profiles__), "literal");
```
where X will be replaced by a unique number. The `const_cast` is required because log_prob and other model functions are const.

- at the end of the generated C++ representing the transformed parameters, a call to a function that stops active profiles in the transformed parameters is placed if profile() is used in the transformed parameters block. This is required because the transformed parameters block does not translate to a separate block in C++ as variables defined in transformed parameters are used in other blocks and we can thus not rely on the profile going out of scope.

# The Stan Math implementation

The Stan Math implementation is centered around the profile C++ class:
```cpp
template <typename T>
class profile {
  std::string name_;
  profile_map* profiles_;

 public:
  profile(std::string name, profile_map& profiles)
      : name_(name), profiles_(&profiles) {
    internal::profile_start<T>(name_, *profiles_);
  }

  ~profile() { internal::profile_stop<T>(name_, *profiles_); }
};
```

In case of `T = var`, the constructor calls the `profile_start` function that places the start `var` on the AD tape. The destructor places the stop `var` on the AD tape. In case of `T = double` no `var` is placed in either calls. This is used for profiling in transformed data, generated quantities blocks and other cases where `log_prob` is called with `T__`, that is when the gradient of the `log_prob` is not required.


`profile_start()` starts the timers for the forward pass and stores AD meta information required to profile the sub-expression, for example the number of elements on the AD tape. It also sets up the reverse callback that stops the reverse pass timers.

`profile_stop()` stops the timers for the forward pass and calculates the differences for the AD meta information, the difference of the number of elements on the AD tape recorder in profile_stop and profile_start is the number of elements placed on the AD tape in the subexpression we are profiling. It also starts the timers for reverse callback.

# The CmdStan interface

- After the fitting in cmdstan finishes, the profiling information is printed to stdout:

profile_name,total_time,fwd_time,rev_time,ad_tape
bernoulli GLM,0.0409984,0.000453154,10
normal_lpdf alpha,0.00238057,0.000497744,1
normal_lpdf beta,0.00349398,0.0005345,1

- If the argument `profiling_file = filename.csv` is provided, the information is stored in a separate CSV and not printed to stdout.

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

- have profiling be a separate service of Stan, similar to how diagnose is implemented

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

