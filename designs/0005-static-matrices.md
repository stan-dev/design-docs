- Feature Name: static_matrices
- Start Date: April 30th, 2020
- RFC PR: [Example Branch](https://github.com/stan-dev/math/compare/feature/var-template)
- Stan Issue: [#1805](https://github.com/stan-dev/math/issues/1805)

# Summary
[summary]: #summary

This proposes a `static_matrix` and `static_vector` type in the Stan language which on the backend will allow for significant performance opportunities. In Stan Math this will be represented by `var<Eigen::Matrix<double, 1, 1>>` or `var<matrix_cl<double>>`. The implementation will be fully backwards compatible with current Stan code. With optimizations from the compiler the conditions for a `matrix` to be a `static_matrix` can be detected and applied to Stan programs automatically for users.

# Motivation
[motivation]: #motivation

Currently, a differentiable matrix in Stan is represented as an Eigen matrix holding a pointer to an underlying array of autodiff objects, each of those holding a pointer to the underlying autodiff object implementation. These `N*M` autodiff elements are expensive but necessary so the elements of a matrix can be assigned to without copying the entire matrix. However, in instances where the matrix is treated as a whole object such that underlying subsets of the matrix are never assigned to, we can store one autodiff object representing the entire matrix. 

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

At the language level, `static_matrix` can replace a `matrix` type if subsets of the matrix are never assigned to. That makes code such as the below illegal.

```stan
static_matrix[N, M] A = // Fill in A...
A[10, 10] = 5;
```

Besides that they can be thought of as standard matrix.

At the Stan Math level a `static_matrix` is a `var_type<Eigen::Matrix<double, -1, -1>>` with an underlying pointer to a `vari_type<Eigen::Matrix<double, -1, -1>>`*. This means that accessors for the value and adjoint of `var_type` objects can access contiguous chunks of each part of the `var_type`. Any function that accept a `var_type<T>` will support static matrices.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

This feature will be added in the following stages.

1. Replace `var` and `vari` with templated types. See the [example branch](https://github.com/stan-dev/math/compare/feature/var-template) here to see how this will be done. `var` and `vari` have been changed to `var_type<T>` and `vari_type<T>` with aliases for the current methods as `using var = var_type<double>` and `using vari = vari_type<double>`. These aliases allow for full backwards compatibility with existing upstream dependencies.

2. Make the stack allocator conform to accept `vari_type<T>` objects.

3. Additional PRs for the current arithmetic operators for `var` to accept `vari_type<T>` object types.

4. Sort out and add any additional specialized methods for static matrix types such as `cholesky_decompose`.

5. Add the `static_matrix` and `static_vector` types to the Stan language along with supported signatures.

6. Support detection and substitution of `matrix` types for `static_matrix` types.

7. ???

8. Done!

# Drawbacks
[drawbacks]: #drawbacks

More templates can be confusing and will lead to larger compile time. The confusion of templates can be mitigated by proper duty of care with documentation and guides for the Stan Math type system. Larger compile times can't be avoided with this implementation, though other forthcoming proposals can allow us to monitor increases in compilation times.

With `sparse_matrix` and `complex_matrix` this will now add _another_ `*_matrix` type proposal to the language. There's no way to get around this in the Stan language currently, though some small side discussions exist to support attributes on types such as

```stan
@(sparse_type, static_type) // can't have static here because of C++ keyword
matrix[N, M] X;

@(complex_type, static_type)
vector[N] Y;
```

though this is far down the line for now.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

Besides the tech burden I'm rather happy with this implementation, though I'm open to any criticisms/alternatives and will add them here. You can see some of the discussion on this as well in issue [#1805](https://github.com/stan-dev/math/issues/1805) and the prior art below.

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

I'm interested in hearing about Stan language semantics and any difficulties I may have missed during the implementation section.

- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

Any intricacies of using the GPU via `var_type<matrix_cl<double>>` should be deferred to a separate discussions or can happen during the implementation.

*Interestingly, this also means that `var_type<float>` and `var_type<long double>` can be legal.
