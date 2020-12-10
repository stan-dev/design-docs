- Feature Name: static_matrices
- Start Date: April 30th, 2020
- RFC PR: [Example Branch](https://github.com/stan-dev/math/compare/feature/var-template)
- Stan Issue: [#1805](https://github.com/stan-dev/math/issues/1805)

# Summary
[summary]: #summary

This proposes a generalization of the reverse mode autodiff type in Stan Math,
`var_value<T>`, where `T` is the underlying storage type of the autodiff variable.
For `T == double`, this type is equivalent to the current Stan Math `var` type.

The usefulness of this type comes from setting `T` to more general data structures,
in particular the Eigen Matrix types. Instead of dealing with matrices of vars,
this allows operations in the Math library to be written in terms of vars that are
themselves matrices.

This makes working with matrix variables in Stan autodiff much faster. This design
is fully backwards compatible with the curren Stan autodiff types and those remain.

For the rest of this proposal, "autodiff" means "reverse mode autodiff".

With optimizations from the compiler the conditions for a `matrix` to be a
constant matrix can be detected and applied to Stan programs automatically
for users.

# Motivation
[motivation]: #motivation

Currently, an `N x M` matrix in Stan is represented as an Eigen matrix holding
a pointer to an underlying array of autodiff objects, each of those holding
a pointer to the underlying autodiff object implementation.

The basic Eigen type used by Stan is `Eigen::Matrix<var, R, C>`. For brevity,
this will be referred to as a "matvar" type (a matrix of vars). There are no
major differences between a matrix of vars or a vector of vars or a row vector
of vars.

This proposal will enable an `N x M` Stan matrix to be defined in terms of one
autodiff object with two separate `N x M` containers, one for its values and
one for its adjoints.

This basic example of this type is `var_value<Eigen::MatrixXd>`. For brevity,
these will be referred to as "varmat" types (a var that is a matrix). Again,
there are no major differences when the matrix is replaced by a vector or a row vector.

The motivation for introducing the varmat type is speed. These types speed up
computations in a number of ways:

1. The values in a varmat are stored separately from the `adjoints` and can
be accessed independently. In a matvar the values and adjoints are interleaved.
With how memory loads work on modern cpus, that means reading the values requires
reading the values and the adjoints.

2. To read all `N x M` values or adjoints of a varmat requires one pointer
dereference and `N x M` double reads. Reading a similar matvar requires
`N x M` pointer dereferences and `N x M` reads.

3. Memory is linear in varmat, and in the best case interleaved in matvar
(though because every element is a pointer, in worse case matvar memory accesses
are entirely random).

4. Because values and adjoints of a varmat are each stored in one place, only
two arena allocations are required to build an `N x M` matrix. matvar requires
`N x M` allocations.

5. varmat is a more suitable datastructure for autodiff variables on a GPU
than matvar because the memory difficulties with pointer-chasing and strided
accesses are more acute on GPUs than CPUs.

See [here](https://github.com/stan-dev/design-docs/pull/21#issuecomment-625352581)
for performance tests on a small subset of gradient evaluations using varmat and
matvar types.

matvar has two advantages that varmat does not duplicate. These are listed
here to motivate the backwards compatibility of this proposal with matvar:

1. matvar types are more compatible with existing Eigen code. For instance, it is possible
to autodiff certain Eigen decompositions and solves with matvar types that will
not work with varmat types.

2. It is easier to assign individual elements of a matvar to another variable -- this
can be done by writing a new pointer over an old pointer. Assigning elements to a varmat
can be done, but it requires either matrix copies (slow, and not implemented), or
adding extra functions on the reverse pass callback stack (implemented and discussed later)

# Math Implementation
[math-implementation]: #math-implementation

At this point versions of `var_value<T>` types have been implemented for `T` being an
Eigen dense type, an Eigen sparse type, an Eigen expression, a double, or a GPU type.

As var previously, `var_value<T>` is a PIMPL (pointer to implementation) type. The
implementation of `var_value<T>` is held in `vari_value<T>`, and the only data a
`var_value<T>` holders is a pointer to a `vari_value<T>` object.

The old `var` and `vari` types are now typdef aliases to `var_value<double>` and
`vari_value<double>` respectively. All `vari_value<T>` types inherit from `vari_base`,
which is a new type used in the autodiff stacks (there are no changes there other than
swapping `vari_base` in for `vari`).

For implementation of `vari_value<T>` where `T` is an Eigen dense type (the basic varmat),
look [here](https://github.com/stan-dev/math/blob/develop/stan/math/rev/core/vari.hpp#L604)

For implementation of `vari_value<T>` where `T = double` (the reimplementation of var),
look [here](https://github.com/stan-dev/math/blob/develop/stan/math/rev/core/vari.hpp#L81)

For implementation of `vari_value<T>` where `T` is an OpenCL type, look
[here](https://github.com/stan-dev/math/blob/develop/stan/math/opencl/rev/vari.hpp#L23)

For implmementation of `vari_value<T>` where `T` is an Eigen sparse type, look
[here](https://github.com/stan-dev/math/blob/develop/stan/math/rev/core/vari.hpp#L746)

## Use and Testing in Functions

Because varmat types are meant for performance, there are no default constructors
for building matvar types from varmat or varmat from matvar (or any of the
the varmat types above from any other). This is done on purpose to avoid implicit
conversions and any accidental slowdowns this may lead to. Everything written for
varmat types is done explicitly, which makes it somewhat less automatic than
matvar. The matvar types are still available for general purpose autodiff.

Testing varmat autodiff types for different functions is done by including a
`stan::test::test_ad_varmat(...)` mixed mode autodiff test along with every
`stan::test::test_ad(...)` test. The tests for `log_determinant`, available
[here](https://github.com/stan-dev/math/blob/develop/test/unit/math/mix/fun/log_determinant_test.cpp)
are typical of what is done.

`test_ad_varmat` checks that the values and Jacobian of a function autodiff'd with
varmat and matvar types behaves the same (and also that the functions throw
errors in the same places). `test_ad_varmat` is not included by default in `test_ad`
because not all functions support varmat autodiff.

`test_ad_varmat` also checks return type conventions. For performance, it is assume
a function takes in a mix of varmat and matvar types should also return a varmat.

A complete list of varmat functions is planned to be developed for the compiler
implementation. As an incomplete substitute, a list of functions with reverse mode
implementations that are being converted to work with varmat is here:
https://github.com/stan-dev/math/issues/2101 . A pull request
([here](https://github.com/stan-dev/math/pull/2214)) is up that adds support for
varmat to all the non-multivariate distribution functions.

## Assigning a varmat

Something in the original design doc that is not necessary anymore is the limitation
that subsets of varmat variables cannot be assigned efficiently.

The efficiency loss was so great in the original design (requiring a copy of the entire
varmat) that this idea was discarded completely.

There is a strategy available now to assign to subsets of varmat variables that is
more efficient than this.

The idea is that when part of a varmat is assigned to, the values in that part of the
varmat are saved into the memory arena before being overwritten, and a call is pushed
onto the chaining stack that will restore the values back from the arena and set the
respective adjoints of the varmat entries to zero.

The assumptions that makes this work is after a subset of a varmat is overwritten,
that part of the varmat cannot be used in any further calculations, and so the adjoints
of that part of the matrix will be zero in the reverse pass at the time of assignment.

This means that assignment into a varmat would invalidate any views into that
varmat's memory.

# Stanc3 implementation
[stanc3-implementation]: #stanc3-implementation

The language implementation of varmat is yet undefined. It was left unresolved because
enough was clear from the initial discussions of how to handle the Math implementation
regardless of how the language was handled.

At this point, the Math maturing to the point that it is possible to compile a model using
varmats values with a development version of the Stanc3 compiler (available
[here](https://github.com/stan-dev/stanc3/pull/755), though it may take some effort to run since
it is a work in progress). This Stanc3 compiler defines any variable with a name ending in
`_varmat` to use a varmat type.

A basic bernoulli MRP model with five population level covariates and seven group terms is available
[here](https://github.com/bbbales2/computations_in_glms/blob/master/benchmark_model/mrp_varmat.stan).

The initial varmat implementation of this model achieves a per-gradient speedup of around two.

Now that varmat variables can be assigned, it is possible that the compiler silently replace every
matvar in Stan with a varmat, and none of the standard Stan use cases would be affected.

There are four major implementation strategies available at the Stanc3 level.

1. Implement a new Stan type to differentiate explicitly between matvar and varmat types

2. Use matvar types whenever there is any function in the Stan program that does not support varmat

3. Use varmat types by default, but if variable assignment is detected, or a varmat is used
in an unsupported function convertion to and from matvar is used automatically.

4. Use varmat types everywhere

The original proposal was leaning towards #1 because it most naturally corresponds to the Math
implementation. However, this leaves the problem of explicitly declaring varmat to the user. To
avoid duplicating the user's manual and function reference for varmat and matvar functions, there
would also need to be some automatic, under the hood conversions between the types. This automatic
converting would make it so that if a varmat is forgotten anywhere, the entire program will be
slowed down. This sort of explicit typing shouldn't be too much of a problem in development models
or generated Stan code, but in large, user-written models this would be error prone to implement
and maintain.

The advantage of #2 is that it would allow programs that can be written using only varmat functions
to be very fast (and not even worry about any conversion to matvar or not). The problem with this
implementation is that, the difference between `varmat` and `matvar` would again need documented
at the user level and some notation would need added to the user manual to indicate if a function
is or is not available for optimization.

The advantage of #3 is that varmat and matvar types could be implemented without any extra
documentation for the user. Similarly to #2, if the user uses functions only available for matvar,
there will be some slowdown as conversions between varmat and matvar are handled, but unlike #2
the slowdown might not be catastrophic. In this case it would not be as crucial to carefully
document the matvar and varmat types. varmat types would simply turn on when available and make
the model faster when they were. The difficulty here is compiler implementation which would need
to be more advanced to detect when it could use varmat and when it would need to convert to matvar.

The advantage of #4 is simplicitly of use and simplicitly of compiler implementation. If varmat
types are used everywhere possible and there is no attempt to balance against the advantages of
varmat against matvar, then the main difficulty will just be making sure to convert varmat
to matvars and back again when used in functions that do not support varmat.

# Prior art
[prior-art]: #prior-art

Discussions:
 - [Efficient `static_matrix` type?](https://discourse.mc-stan.org/t/efficient-static-matrix-type/2136)
 - [Static/immutable matrices w. comprehensions](https://discourse.mc-stan.org/t/static-immutable-matrices-w-comprehensions/12641)
 - [Stan SIMD and Performance](https://discourse.mc-stan.org/t/stan-simd-performance/10488/11)
 - [A New Continuation Based Autodiff By Refactoring](https://discourse.mc-stan.org/t/a-new-continuation-based-autodiff-by-refactoring/5037/2)

[JAX](https://jax.readthedocs.io/en/latest/notebooks/Common_Gotchas_in_JAX.html#%F0%9F%94%AA-In-Place-Updates) is an autodiff library developed by Google whose array type has similar constraints to the constant matrix type proposed here.

[Enoki](https://github.com/mitsuba-renderer/enoki) is a very nice C++17 library for automatic differentiation which under the hood can transform their autodiff type from an arrays of structs to structs of arrays.

[FastAD](https://github.com/JamesYang007/FastAD) very fast C++ autodiff taking advantage of expressions, matrix autodiff types, and a static execution graph.