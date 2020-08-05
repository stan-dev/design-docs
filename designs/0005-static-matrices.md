- Feature Name: static_matrices
- Start Date: April 30th, 2020
- RFC PR: [Example Branch](https://github.com/stan-dev/math/compare/feature/var-template)
- Stan Issue: [#1805](https://github.com/stan-dev/math/issues/1805)

# Summary
[summary]: #summary

This proposes a constant matrix type in stan that will allow for significant performance opportunities. In Stan Math this will be represented by `var_value<Eigen::Matrix<double, R, C>>` or `var_value<matrix_cl<double>>`. The implementation will be fully backwards compatible with current Stan code. With optimizations from the compiler the conditions for a `matrix` to be a constant matrix can be detected and applied to Stan programs automatically for users. The implementation of this proposal suggests a staged approach where a stan language level feature is delayed until type attributes are allowed in the language and constant matrices have support for the same set of methods that the current `matrix` type has.

# Motivation
[motivation]: #motivation

Currently, an `NxM` matrix in Stan is represented as an Eigen matrix holding a pointer to an underlying array of autodiff objects, each of those holding a pointer to the underlying autodiff object implementation. These `N*M` autodiff elements are expensive but necessary so the elements of a matrix can be assigned to without copying the entire matrix. However, in instances where the matrix is treated as a whole object such that underlying subsets of the matrix are never assigned to, we can store one autodiff object representing the entire matrix. See [here](https://github.com/stan-dev/design-docs/pull/21#issuecomment-625352581) for performance tests on a small subset of gradient evaluations using matrices vs. constant matrices.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

At the Stan Math level a constant matrix is a `var_value<Eigen::Matrix<double, -1, -1>>` with an underlying pointer to a `vari_value<Eigen::Matrix<double, -1, -1>>`\*.  The value and adjoint of the matrix are stored separately in memory pointed to by the `vari_value`. Functions that currently support `Eigen::Matrix<var, R, C>` types will be extended to support `var_value<Eigen>` types

At compiler level, a `matrix` can be substituted for a constant matrix if the matrix is only constructed once and it's subslices are never assigned to.

```stan
matrix[N, M] A = // Construct matrix A...
A[10, 10] = 5; // Will be dynamic!
A[1:10, ] = 5; // Will be dynamic!
A[, 1:10] = 5; // Will be dynamic!
A[1:10, 1:10] = 5; // Will be dynamic!
```

However extracting subslices from a matrix will still allow it to be constant.

```stan
matrix[N, M] A = // Construct matrix A...
real b = A[10, 10]; // Will be real
matrix[10, M] C = A[1:10, ]; // Will be static!
row_vector[10] D = A[, 1:10]; // Will be static!
matrix[10, 10] F = A[1:10, 1:10]; // Will be static!
```

Any function or operation in the Stan language that can accepts a `matrix` as an argument can also accept a constant matrix. Functions which can take in multiple matrices will only return a constant matrix if all of the other matrix inputs as well as the return type are static matrices.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

This feature will be added in the following stages.

1. Replace `var` and `vari` with templated types.
   - This has already been done in PR [#1915](https://github.com/stan-dev/math/pull/1915). `var` and `vari` have been changed to `var_value<T>` and `vari_value<T>` with aliases for the current methods as `using var = var_value<double>` and `using vari = vari_value<double>`. These aliases allow for full backwards compatibility with existing upstream dependencies.

2. Add `var_value` and `vari_value` Eigen specializations
   - This has been done in PR [#1952](https://github.com/stan-dev/math/pull/1952)
   - The `vari_value` specialized for Eigen types holds two pointers of scalar arrays `val_mem_` and `adj_mem_` which are then accessed through `Eigen::Map` types `val_` and `adj_`.

3. Update `adj_jac_apply` to work with constant matrices.
   - An example of this exists in [#1928](https://github.com/stan-dev/math/pull/1928). Using `adj_jac_apply` will provide a standardized and efficient API for adding new reverse mode functions for constant matrices.

4. Additional PRs for the current arithmetic operators for `var` to accept `var_value<Eigen>` types.
   - Since the new operations work on matrix types, `chain()` methods of the current operators will need to be specialized for matrix, vector, and scalar inputs.

4. Add additional specialized methods for constant matrices.
 - All of our current reverse mode specializations require an `Eigen::Matrix<var>`, which then assumes it needs to generate `N * M` `vari`. Specializations will need to be added for `var_type<Eigen::Matrix<T>>`

5. Generalize the current autodiff testing framework to work with constant matrices.

6. Add specializations for `operands_and_partials`, `scalar_seq_view`, `value_of` and other helper functions needed for the distributions.

7. In the stanc3 compiler, support detection and substitution of `matrix/vector/row_vector` types for constant matrix types.

Steps (1) and (2) have been completed in the example branch with some work done on (3). Step 7 has been chosen specifically to allow more time to discuss the stan language implementation. The compiler can perform an optimization step while parsing the stan program to see if a `matrix/vector/row_vector`:

1. Does not perform assignment after the first declaration.
2. Uses methods that have constant matrix implementations in stan math.

and then replace `Eigen::Matrix<var, R, C>` with `var_value<Eigen::Matrix<double, R, C>>`.

As an example of when the compiler could detect a constant matrix substitution, brms will normally output code for hierarchical models such as

```stan
parameters {
  vector[Kc] b;  // population-level effects
  // temporary intercept for centered predictors
  real Intercept;
  real<lower=0> sigma;  // residual SD
  vector<lower=0>[M_1] sd_1;  // group-level standard deviations
  matrix[M_1, N_1] z_1;  // standardized group-level effects
  // cholesky factor of correlation matrix
  cholesky_factor_corr[M_1] L_1;
}
transformed parameters {
  // actual group-level effects
  matrix[N_1, M_1] r_1 = (diag_pre_multiply(sd_1, L_1) * z_1)';
  // using vectors speeds up indexing in loops
  vector[N_1] r_1_1 = r_1[, 1];
  vector[N_1] r_1_2 = r_1[, 2];
}
model {
  // initialize linear predictor term
  vector[N] mu = Intercept + Xc * b;
  for (n in 1:N) {
    // add more terms to the linear predictor
    mu[n] += r_1_1[J_1[n]] * Z_1_1[n] + r_1_2[J_1[n]] * Z_1_2[n];
  }
  // more stuff
```

This could be rewritten in brms to do the assignment of `mu` on one line. And because each `vector` and `matrix` do not perform assignment after the first declaration these would all be candidates to become constant matrices. With a type attribute of `const` in the language this would then look like:

```stan
parameters {
  vector[Kc] b;  // population-level effects
  // temporary intercept for centered predictors
  real Intercept;
  real<lower=0> sigma;  // residual SD
  vector<lower=0>[M_1] sd_1;  // group-level standard deviations
  matrix[M_1, N_1] z_1;  // standardized group-level effects
  // cholesky factor of correlation matrix
  cholesky_factor_corr[M_1] L_1;
}
transformed parameters {
  // actual group-level effects
  matrix[N_1, M_1] r_1 = (diag_pre_multiply(sd_1, L_1) * z_1)';
  // using vectors speeds up indexing in loops
  vector[N_1] r_1_1 = r_1[, 1];
  vector[N_1] r_1_2 = r_1[, 2];
}
model {
  // predictor terms
  vector[N] mu = Intercept + Xc * b + r_1_1[J_1] .* Z_1_1 + r_1_2[J_1] * Z_1_2;
  // more stuff
```


Delaying release of the `const` type to the language allows for a slow buildup of the needed methods. Once constant matrices have the same available methods as the `matrix/vector/row_vector` types we can release it as a stan language feature.

# Drawbacks
[drawbacks]: #drawbacks

More templates can be confusing and will lead to longer compile times. The confusion of templates can be mitigated by adding additional documentation and guides for the Stan Math type system. Larger compile times can't be avoided with this implementation, though other forthcoming proposals can allow us to monitor increases in compilation times.

Waiting for type attributes in the Stan language means this feature will be a compiler optimization until both type attributes are allowed in the language and an agreement is made on stan language naming semantics. This is both a drawback and feature. While delaying a `constant_matrix` type as a user facing feature, it avoids the combinatorial problem that comes with additional type names for matrices proposed in the language such as `sparse` and `complex`.

One large consideration is the need for the use of `flto` by compilers in order to not have a performance regression for ODE models because of missed divirtualization from the compiler. All vari created in stan are tracked and stored as pointers in our autodiff reverse mode tape `ChainableStack`. The underlying implementation of `ChainableStack` requires the use of an `std::vector` which is a homogeneous container. so all `vari_value<T>` must inherit from a `vari_base` that is then used as the type for the reverse mode tape in `ChainableStack` as a `std::vector<vari_base*>`. Because of the different underlying structures of each `vari_value<T>` the method `set_zero_adjoint()` of the `vari_value<T>` specializations must be `virtual` so that when calling the reverse pass over the tape via the `vari_base*` we call the proper `set_zero_adjoint()` member function for each type. But because Stan's autodiff tape is a global object, compilers will not devirtualize these function calls unless the compiler can optimize over the entire program (see [here](https://stackoverflow.com/questions/48906338/why-cant-gcc-devirtualize-this-function-call) for more info and a godbolt example).

Multiple other methods were attempted such as
1. boost::variants instead of polymorphism
  - This still leads to a lookup from a function table which causes similar problems to the virtual table lookup
2. A different stack for every vari_base subclass
3.  Don't use the chaining stack for zeroing. Instead of having a chaining/non-chaining stack have a chaining/zeroing stack. Everything goes in the zeroing stack. Only chaining things go in the chaining stack.
  - Both (2) and (3) also lead to performance problems because of having to allocate memory on multiple stacks

 The ODE models are particularly effected by this because of the multiple calls to `set_zero_adjoint()` that are used in the ODE solvers. This means that upstream packages will need to suggest (or automatically apply) the `-flto` flag to Stan programs so that these function calls can be devirtualized.

# Prior art
[prior-art]: #prior-art

Discussions:
 - [Efficient `static_matrix` type?](https://discourse.mc-stan.org/t/efficient-static-matrix-type/2136)
 - [Static/immutable matrices w. comprehensions](https://discourse.mc-stan.org/t/static-immutable-matrices-w-comprehensions/12641)
 - [Stan SIMD and Performance](https://discourse.mc-stan.org/t/stan-simd-performance/10488/11)
 - [A New Continuation Based Autodiff By Refactoring](https://discourse.mc-stan.org/t/a-new-continuation-based-autodiff-by-refactoring/5037/2)

[JAX](https://jax.readthedocs.io/en/latest/notebooks/Common_Gotchas_in_JAX.html#%F0%9F%94%AA-In-Place-Updates) is an autodiff library developed by google whose array type has similar constraints to the constant matrix type proposed here.

[Enoki](https://github.com/mitsuba-renderer/enoki) is a very nice C++17 library for automatic differentiation which under the hood can transform their autodiff type from an arrays of structs to structs of arrays. It's pretty neat! Though implementing something like their methods would require some very large changes to the way we handle automatic differentiation.

*Interestingly, this also means that `var_value<float>` and `var_value<long double>` can be legal.
