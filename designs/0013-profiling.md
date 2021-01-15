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
the potential randomness (there are single model gradients timings output by CmdStan, but
these are not very accurate).

# Profiling on the Stan model level
[stan-model-profiling]: #stan-model-profiling

The proposed profile interface is the addition of a new Stan language construct, the 
`profile` statement. The `profile` statement takes one string argument (a name) and is followed by a
code block. `profile` measures the performance of code in the block and summarizes it
under the given profile name.

For instance, in a simple linear regression the `profile` command could be used to
measure the cost of the joint density:

```stan
model {
  profile("model block") {
    sigma ~ normal(0, 1);
    b ~ normal(0, 1);
    y ~ normal(X * b, sigma);
  }  
}
```

It could also be used to measure just the likelihood component and ignore the priors:
```stan
model {
  sigma ~ normal(0, 1);
  b ~ normal(0, 1);
  profile("likelihood") {
    y ~ normal(X * b, sigma);
  }  
}
```

For brevity, examples of the major use-cases of `profile` are included below,
but the use cases themselves are here:

1. `profile` statements can be used in user-defined functions, in the
`transformed data`, `transformed parameters`, `model`, and `generated quantities`
blocks.

2. `profile` statements that time non-autodiff code will be recorded in the
same way as statements that times autodiff code (just the autodiff cost will be
zero).

3. There can be multiple `profile` statements with the same name. The name of
the profile statement has global scope - they all accumulate to one set of timers
and so will be reported in aggregate. This means profiles with the same name in
different blocks record in the same place.

4. Timing statements can be nested, but they must have different names. The following will 
result in a runtime error:
```stan
model {
  profile("likelihood") {
    sigma ~ normal(0, 1);
    profile("likelihood") {
      b ~ normal(0, 1);
      y ~ normal(X * b, sigma);
    }    
  }
}
```
## Duplicate names

All timers with the same name record to the same place. Be aware, timing two
blocks with the same name is different than timing the code together.

In this case, the profile `model` records information about the evaluation of
the model block:
```stan
model {
  profile("model") {
    sigma ~ normal(0, 1);
    b ~ normal(0, 1);
    y ~ normal(X * b, sigma);
  }  
}
```

In this case, the profile `model` records information about the evaluation of
the prior and the likelihood separately, but saves the results in the same
timing profile. This may make the timing summary statistics tricky to interpret
but is legal code:

```stan
model {
  profile("model") {
    sigma ~ normal(0, 1);
    b ~ normal(0, 1);
  }
  profile("model") {
    y ~ normal(X * b, sigma);
  }  
}
```

## Blocks and loops

As an extended example of how a `profile` statement works with blocks and loops,
consider the construction of the Cholesky factor of a Gaussian process kernel:

```stan
transformed parameters {
  matrix[N, N] L_K;
  matrix[N, N] K;
  profile("gp"){
    K = gp_exp_quad_cov(x, alpha, rho);
  }
  real sq_sigma = square(sigma);

  for (n in 1:N) {
    profile("add diagonal") {
      K[n, n] = K[n, n] + sq_sigma;
    }
  }
  profile("cholesky") {
    L_K = cholesky_decompose(K);
  }  
}
```

There are three profiles here. The first profile, `gp`, will time the
statement `K = gp_exp_quad_cov(x, alpha, rho)`. The second profile,
`add diagonal`, will measure the cost of each iteration of the for loop 
and accumulate that under the `add diagonal` profile name.

The third profile, `cholesky`, measures the cost of
`cholesky_decompose`.

## Nested profiles

Nested profiles can be used when the overall cost and the individual cost
of operations are interesting. In this case:

```stan
model {
  profile("model");
  {
    profile("prior") {
      sigma ~ normal(0, 1);
      b ~ normal(0, 1);
    }    
  }
  profile("likelihood") {
    y ~ normal(X * b, sigma);
  }  
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
    profile("myfunc") {
      ...;
    }    
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
  profile("myfunc - model") {
    x = myfunc(alpha);
  }
  ...
}
...
generated quantities {
  real x;
  profile("myfunc - generated quantities") {
    x = myfunc(alpha);
  }
  ...
}
```

## Note on parameters block

Because only parameter declaration statements are allowed in the `parameters`
block, `profile` cannot be used there. This means that the `lower`, `upper`,
`multiply` and `offset` constraints/transforms can not be profiled.

# The Stan Math implementation

The `profile` functionality in Stan is implemented with two functions, `profile_start`
and `profile_stop` which handle intrumenting the code. A C++ `std::map` is to
store the accumulated timing results of each profile by name and thread ID.

The two functions `profile_start` and `profile_stop` are implemented with the
signatures:

```
template <typename T>
inline void profile_start(std::string name, profile_map& profiles);
template <typename T>
inline void profile_stop(std::string name, profile_map& profiles);
```

The first argument is the profile name, and the second argument is the map
in which to store timing results.

`profile_start` starts a timer for the given profile name and
`profile_stop` stops the timer and saves the accumulated time in the profile.

It is an error if `profile_start` is called with the same name twice before
a `profile_stop` is called.

If the template argument `T` is a `var`, then `profile_start` and
`profile_stop` push varis onto the chaining autodiff stack. On the reverse
pass, the vari produced by `profile_stop` starts a timer and the vari
produced by `profile_start` stops it and records the results. In this way
the forward and reverse pass calculations can both be timed.
`profile_start` and `profile_stop` also record the number of varis on
the chaining and non-chaining stacks.

If the template argument `T` is `double`, then `profile_start` and
`profile_stop` only record timing information. They do not push any
varis onto the chaining autodiff stack or record information about the
number of varis on the chaining and non-chaining autodiff stacks.

A helper profile class is used to wrap `profile_start` and `profile_stop`
with RAII semantics to make it easier to use.

# Stanc3 - changes to the generated C++

The C++ code generated from Stan models will be changed accordingly:

- All generated C++ models representing Stan models will gain a private member
`profiles__`. This member will represent the map of all profile information.

- C++ calls to profile will be generated as:

    ```cpp
    {
      profile<T__> profile("literal", const_cast<profile_map&>(profiles__));
      ... statements
    }    
    ```
    The `const_cast` is required because log_prob and other model functions are const.

# The CmdStan interface

- After the fitting in CmdStan finishes, the profiling information is stored in a 
  CSV file. By default, the CSV file is named `profile.csv`. An example of a CSV file
  is given below.

```
name,thread_id,time_total,forward_time,reverse_time,chain_stack_total,nochain_stack_total,no_autodiff_passes,autodiff_passes
glm,140475847071552,0.0378336,0.0375202,0.000313417,12192,0,1,12192
priors,140475847071552,0.00485089,0.00391626,0.000934627,48768,0,1,12192
```

# Disadvantages of this approach
[Disadvantages]: #Disadvantages

The shortcomings of this approach are: 

- Profiling in recursive functions is not allowed.

- Though timers can be nested, they do not report their results as such (the
nesting has to be understood and intepreted from the results manually)

- There is no separation between warmup and non-warmup timing (for sampling
or ADVI)

- We can not profile top-level declarations in any of the blocks and can thus also not profile
any transforms defined in such declarations. As top-level declarations are the only allowed 
statements in the `parameters` block, this also means that profiling is not allowed in the
parameters block.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

There are many possible alternatives to this design. Listing some of which came
up in the current discusions:

- Profile every line of a Stan model automatically. The downside of this is the
profiling overhead is large compared to some Stan statements.

- Profile every block inside a Stan program automatically (top-level blocks as
well as inner blocks). It is fairly easy to add profile statements where they
are needed manually, so this seemed unnecessary even if it is occasionally
handy.

- Sample based timers are another way of instrumenting code (stop the code 100
times a second and record the stack). This sort of timing would not work with
the reverse pass though.

- There were a variety of other Stan language interfaces that were proposed. The
current one was chosen for simplicity.

    The special block statements may seem unnecessarily verbose. The profile
    statement could mimic the C++ RAII, in this case profile statements would
    go inside already existing blocks and time from the statement itself to
    the end of that block:

    ```stan	
    {
      profile("profile-name");
      function_call();	
    }	
    ```

    The first problem with this is that `profile` looks like a function call,
    but it behaves like a variable -- it has variable scope, but no name! This
    could be confusing as it is would be relatively unique in the language.
    The second, which is more of a minor technical detail, is that the
    `transformed parameters` block in Stan is actually not a C++ block in and
    of itself and so some special code would be needed to make the profile stop
    early.

    Manual start stops are more verbose and require the start stop string to match
    exactly (or it is an error):

    ```stan
    start_profiling("profile-name");
    function_call();
    stop_profiling("profile-name");
    ```

    Decorators for blocks or function calls would be a new syntax for, which
    seemed unnecessary:

    ````
    @profile("profile-name");
    {
      function_call();
    }

    @profile("profile-name");
    function_call();
    ```

- There are ways to generate profiling information that can further be analyzed
by external visualization tools like
[Chrome Tracing](https://aras-p.info/blog/2017/01/23/Chrome-Tracing-as-Profiler-Frontend/).
This was not implemented.

# Prior art
[prior-art]: #prior-art

There is no Stan-specific priort art for profiling. For other tools we have the
following:

- TensorFlow based tools: https://www.tensorflow.org/guide/profiler with
TensorBoard for visualization

- PyMC3: https://docs.pymc.io/notebooks/profiling.html

- PyTorch: https://pytorch.org/tutorials/recipes/recipes/profiler.html

- Pyro: to the best of my knowledge Pyro relies on cPython for profiling. Most
profiling information found with regards to Pyro is for their internal
function/distribution-level testing and CI.

The Python-based tools mostly suggest using cPython for profiling the low-level
functions.
