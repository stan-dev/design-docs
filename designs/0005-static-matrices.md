- Feature Name: static_matrices
- Start Date: April 30th, 2020
- RFC PR: [Example Branch](https://github.com/stan-dev/math/compare/feature/var-template)
- Stan Issue: [#1805](https://github.com/stan-dev/math/issues/1805)

# Summary
[summary]: #summary

This proposes a constant matrix type in stan that will allow for significant performance opportunities. In Stan Math this will be represented by `var<Eigen::Matrix<double, R, C>>` or `var<matrix_cl<double>>`. The implementation will be fully backwards compatible with current Stan code. With optimizations from the compiler the conditions for a `matrix` to be a constant matrix can be detected and applied to Stan programs automatically for users. The implementation of this proposal suggests a staged approach where a stan language level feature is delayed until type attributes are allowed in the language and constant matrices have support for the same set of methods that the current `matrix` type has.

# Motivation
[motivation]: #motivation

Currently, a differentiable matrix in Stan is represented as an Eigen matrix holding a pointer to an underlying array of autodiff objects, each of those holding a pointer to the underlying autodiff object implementation. These `N*M` autodiff elements are expensive but necessary so the elements of a matrix can be assigned to without copying the entire matrix. However, in instances where the matrix is treated as a whole object such that underlying subsets of the matrix are never assigned to, we can store one autodiff object representing the entire matrix. See [here](https://github.com/stan-dev/design-docs/pull/21#issuecomment-625352581) for performance tests on a small subset of gradient evaluations using matrices vs. constant matrices.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

At the Stan Math level a constant matrix is a `var_value<Eigen::Matrix<double, -1, -1>>` with an underlying pointer to a `vari_value<Eigen::Matrix<double, -1, -1>>`\*.  This means that accessors for the value and adjoint of `var_value` objects can access contiguous chunks of each part of the `vari_value`. Any function that accepts a `var_value<T>` will support static matrices.

At the language and level, a `matrix` can be substituted for a constant matrix if the matrix is only constructed once and never reassigned to.

```stan
const matrix[N, M] A = // Construct matrix A...
A[10, 10] = 5; // illegal!
A[1:10, ] = 5; // illegal!
A[, 1:10] = 5; // illegal!
A[1:10, 1:10] = 5; // illegal!
A = X; // illegal!
```

Any function or operation in the stan language that can accepts a `matrix` as an argument can also accept a constant matrix.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

This feature will be added in the following stages.

1. Replace `var` and `vari` with templated types. This has already been done in the example branch [here](https://github.com/stan-dev/math/compare/feature/var-template) (see [here](https://github.com/stan-dev/math/blob/d2967fe2bf6e0d4729d67a714ef40d95d907b18b/stan/math/rev/core/vari.hpp) for the `vari_value` implementation and [here](https://github.com/stan-dev/math/blob/d2967fe2bf6e0d4729d67a714ef40d95d907b18b/stan/math/rev/core/var.hpp) for `var_value`). `var` and `vari` have been changed to `var_value<T>` and `vari_value<T>` with aliases for the current methods as `using var = var_value<double>` and `using vari = vari_value<double>`. These aliases allow for full backwards compatibility with existing upstream dependencies.

2. Make the stack allocator conform to accept `vari_value<T>` objects. This is done by having `vari_type<T>` inherit from a `vari_base` class and defining the [`ChainableStack`](https://github.com/stan-dev/math/blob/d2967fe2bf6e0d4729d67a714ef40d95d907b18b/stan/math/rev/core/chainablestack.hpp) as

```cpp
using ChainableStack = AutodiffStackSingleton<vari_base, chainable_alloc>;
```

3. Additional PRs for the current arithmetic operators for `var` to accept `vari_value<T>` object types.
   - Since the new operations work on matrix types, `chain()` methods of the current operators will need to be specialized for matrix, vector, and scalar inputs.

4. Add additional specialized methods for constant matrices.
 - All of our current reverse mode specializations require an `Eigen::Matrix<var>`, which then assumes it needs to generate `N * M` `vari`. Specializations will need to be added for `var_type<Eigen::Matrix<var>>`

5. In the stanc3 compiler, support detection and substitution of `matrix/vector/row_vector` types for constant matrix types.

6. Create a design document for allowing type attributes in the stan language.

7. Add a `const` type attribute to the stan language.

Steps (1) and (2) have been completed in the example branch with some work done on (3). Step (5-7) have been chosen specifically to allow more time to discuss the stan language implementation. The compiler can perform an optimization step while parsing the stan program to see if a `matrix/vector/row_vector`:

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
  const vector[Kc] b;  // population-level effects
  // temporary intercept for centered predictors
  real Intercept;
  real<lower=0> sigma;  // residual SD
  const vector<lower=0>[M_1] sd_1;  // group-level standard deviations
  const matrix[M_1, N_1] z_1;  // standardized group-level effects
  // cholesky factor of correlation matrix
  const cholesky_factor_corr[M_1] L_1;
}
transformed parameters {
  // actual group-level effects
  const matrix[N_1, M_1] r_1 = (diag_pre_multiply(sd_1, L_1) * z_1)';
  // using vectors speeds up indexing in loops
  const vector[N_1] r_1_1 = r_1[, 1];
  const vector[N_1] r_1_2 = r_1[, 2];
}
model {
  // predictor terms
  const vector[N] mu = Intercept + Xc * b + r_1_1[J_1] .* Z_1_1 + r_1_2[J_1] * Z_1_2;
  // more stuff
```


Delaying release of the `const` type to the language allows for a slow buildup of the needed methods. Once constant matrices have the same available methods as the `matrix/vector/row_vector` types we can release it as a stan language feature.

# Drawbacks
[drawbacks]: #drawbacks

More templates can be confusing and will lead to longer compile time. The confusion of templates can be mitigated by adding additional documentation and guides for the Stan Math type system. Larger compile times can't be avoided with this implementation, though other forthcoming proposals can allow us to monitor increases in compilation times.

Waiting for type attributes in the Stan language means this feature will be a compiler optimization until both type attributes are allowed in the language and an agreement is made on stan language naming semantics. This is both a drawback and feature. While delaying a `constant_matrix` type as a user facing feature, it avoids the combinatorial problem that comes with additional type names for matrices proposed in the language such as `sparse` and `complex` matrices.

# Prior art
[prior-art]: #prior-art

Discussions:
 - [Efficient `static_matrix` type?](https://discourse.mc-stan.org/t/efficient-static-matrix-type/2136)
 - [Static/immutable matrices w. comprehensions](https://discourse.mc-stan.org/t/static-immutable-matrices-w-comprehensions/12641)
 - [Stan SIMD and Performance](https://discourse.mc-stan.org/t/stan-simd-performance/10488/11)
 - [A New Continuation Based Autodiff By Refactoring](https://discourse.mc-stan.org/t/a-new-continuation-based-autodiff-by-refactoring/5037/2)

[Enoki](https://github.com/mitsuba-renderer/enoki) is a very nice C++17 library for automatic differentiation which under the hood can transform their autodiff type from an arrays of structs to structs of arrays. It's pretty neat! Though implementing something like their methods would require some very large changes to the way we handle automatic differentiation.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?

Whether the staged development process listed in the reference level explanation will suffice.

If the restriction on not allowing assignment to the entire matrix such as `A = X` is too restrictive.

- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

Any intricacies of using the GPU via `var_value<matrix_cl<double>>` should be deferred to a separate discussions or can happen during the implementation.

Methods involving changing the current `matrix` type in the Stan language

*Interestingly, this also means that `var_value<float>` and `var_value<long double>` can be legal.
