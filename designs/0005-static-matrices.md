- Feature Name: static_matrices
- Start Date: April 30th, 2020
- RFC PR: [Example Branch](https://github.com/stan-dev/math/compare/feature/var-template)
- Stan Issue: [#1805](https://github.com/stan-dev/math/issues/1805)

# Summary
[summary]: #summary

This proposes two things:

1. Adding a template argument to Stan's C++ reverse mode autodiff type
to allow autodiff variables to have different types of internal storage, for instance
a `double` or an `Eigen::MatrixXd` or something else. Using Eigen matrices as the
internal storage would allow matrices in the Stan language to have a much nicer memory
layout which then also generates more performant programs. This scheme can be fully
backwards compatible with current Stan code.

2. A design for exposing these autodiff variables at the Stan language level

An autodiff type that allows customization of the underlying storage object makes it possible
for matrices, instead of being data structures of autodiff types, for the autodiff type
itself to represent a matrix. Operations on these new types can be more efficient than the old
ones, and this design remains fully backwards compatible with the curren Stan autodiff types.

For the rest of this proposal, "autodiff" means "reverse mode autodiff," and all C++ functions
are assumed to reside in the `stan::math` namespace. The necessary namespace will be
included if this is not true.

# New Reverse Mode Autodiff Type
[newtype]: #newtype

The new autodiff type is `stan::math::var_value<T>`, where `T` is the underlying
storage type of the autodiff variable. For `T == double`, this type is
equivalent to the current `stan::math::var` type.

A `stan::math::var` in Stan is a PIMPL (pointer to implementation) object. It is
a pointer to a `stan::math::vari`, which is an object that holds the actual
value and adjoint. In terms of data, the basic var and vari implementation look
like:

```cpp
struct vari {
  double value_;
  double adjoint_;
};

struct var {
  vari* vi_; // pointer to implementation
}
```

The new, templated `var_value<T>` and `vari_value<T>` are very similar except
the `double` type is replaced with a template type `T`:

```cpp
template <typename T>
struct vari {
  T value_;
  T adjoint_;
};

template <typename T>
struct var_value<T> {
  vari_value<T>* vi_; // pointer to implementation
}
```

Currently, Stan implements matrices using
`Eigen::Matrix<var, Eigen::Dynamic, Eigen::Dynamic>` variables. Internally,
an `N x M` `Eigen::Matrix<var, Eigen::Dynamic, Eigen::Dynamic>` is a
pointer to `N x M` vars on the heap. The storage of an
`Eigen::Matrix<var, Eigen::Dynamic, Eigen::Dynamic>` is equivalent to the
following:

```cpp
struct DenseStorage {
  var* var_data_;
};
```

Because vars are themselves just pointers to varis, this can be simplified
to the more direct form:

```cpp
struct DenseStorage {
  vari** vari_data_;
};
```

So current Stan matrix class is represented internally as a pointer to pointers.

When Stan performs an operation on a matrix it will typically need
to read all of the values of the matrix at least once on the forward autodiff
pass and then update all the adjoints at least once on the reverse autodiff
pass. This can be slow because the pointer chasing required to read a pointer to
pointers data structure is expensive. The can be wasteful because fetching just
the values or adjoints ends up loading both the values and adjoints into cache
(since they are stored beside each other). Stan vectors and row vectors are
implemented similarly and present the same problems.

This proposal will enable an `N x M` Stan matrix to be defined in terms of one
autodiff object with two separate `N x M` containers, one for its values and
one for its adjoints. Filling in the templates, the storage of a
`var_value<Eigen::MatrixXd>` is effectively:

```cpp
template <>
class vari_value<Eigen::MatrixXd> {
  Eigen::MatrixXd value_;    // The real implementation is done with Eigen::Map
  Eigen::MatrixXd adjoint_;  // types to avoid memory leaks
}

template <>
class var_value<Eigen::MatrixXd> {
  vari_value<Eigen::MatrixXd>* vi_; // pointer to implementation
};
```

The full, contiguous matrices of values or adjoints can be accessed without
pointer chasing on every element of the matrix, eliminating the two prime
inefficiences of the `Eigen::Matrix<var, Eigen::Dynamic, Eigen::Dynamic>`
implementation.

As an example, of how this is more efficient, consider the reverse pass
portion of the matrix operation, `C = A * B`. If the values and adjoints
of the respective variables are accessed with `.val()` and `.adj()`
respectively, this can be written as follows:

```cpp
A.adj() += result.adj() * B.val().transpose();
B.adj() += A.val().transpose() * result.adj();
```

Even though on each line only the values or the adjoints of any single variable
are needed, with an `Eigen::Matrix<var, Eigen::Dynamic, Eigen::Dynamic>`
implementation, the values and adjoints of all three variables will be loaded
into memory. Because of the pointer chasing, the compiler will not be able to
take advantage of SIMD instructions.

Switching to a `var_value<Eigen::MatrixXd>`, this is no longer the case. The
values and adjoints can be accessed and updated independently, and because the
memory is contiguous the compiler can take advantage of SIMD instruction
sets.

## Recap and Summary of New Type

From this point forward, the existing
`Eigen::Matrix<var, Eigen::Dynamic, Eigen::Dynamic>` types will be referred to
as a `matvar` types (because the implementation is a matrix of vars).
Similarly, the Eigen Matrix of vars implementation of Stan vector and row
vector types are also `matvar` types.

The replacement types will be referred to as `varmat` types and include,
among others, the `var_value<Eigen::MatrixXd>` type introduced thus far.
The replacement implementation of vector and row vector are also `varmat` types.

The motivation for introducing the `varmat` type is speed. These types speed up
computations in a number of ways:

1. The values in a `varmat` are stored separately from the adjoints and can
be accessed independently. In a `matvar` the values and adjoints are interleaved,
and each value/adjoint pair can be stored in a different place in memory.
Reading a value or adjoint in a `matvar` requires dereferencing a pointer to
where the value/adjoint pair is stored and then accessing them. Because of how
caches and memory work on modern CPUs, even if only the value or adjoint are
needed, both will be loaded.

2. Reading all `N x M` values and adjoints of a `varmat` requires one pointer
dereference and `2 x N x M` double reads. Reading the values and adjoints
of a similar `matvar` requires `N x M` pointer dereferences and `2 x N x M` reads.

3. Memory is linear in `varmat`, and in the best case interleaved in `matvar`
(though because every element is a pointer, in worse case `matvar` memory accesses
are entirely random). The linear memory in `varmat` means that they can use
vectorized CPU instructions.

4. `varmat` is a more suitable data structure for autodiff variables on a GPU
than `matvar` because the memory difficulties with pointer-chasing and strided
accesses are more acute on GPUs than CPUs. Linear memory also helps make the
communication between the CPU and GPU efficient.

5. Because values and adjoints of a `varmat` are each stored in one place, only
two arena allocations are required to build an `N x M` matrix. `matvar` requires
`N x M` allocations.

See [here](https://github.com/stan-dev/design-docs/pull/21#issuecomment-625352581)
for performance tests on a small subset of gradient evaluations using `varmat` and
`matvar` types.

`matvar` has two advantages that `varmat` does not duplicate. These are listed
here to motivate the backwards compatibility of this proposal with `matvar`:

1. `matvar` types are more compatible with existing Eigen code. For instance, it is possible
to autodiff certain Eigen decompositions and solves with `matvar` types that will
not work with `varmat` types.

2. It is easier to assign individual elements of a `matvar` to another variable -- this
can be done by writing a new pointer over an old pointer. Assigning elements to a `varmat`
can be done, but it requires either matrix copies (slow, and not implemented), or
adding extra functions on the reverse pass callback stack (implemented and discussed later)

# Math Implementation and Testing
[math-implementation]: #math-implementation

As before, `var_value<T>` is a PIMPL (pointer to implementation) type. The
implementation of `var_value<T>` is held in `vari_value<T>`, and the only data a
`var_value<T>` holds is a pointer to a `vari_value<T>` object. All
`vari_value<T>` types inherit from `vari_base`, which is a new type used in the
autodiff stacks (there are no changes there other than swapping `vari_base` in for
`vari`).

The old `var` and `vari` types are now typedef aliases to `var_value<double>` and
`vari_value<double>` respectively.

At this point versions of `var_value<T>` types have been implemented for `T` being an
Eigen dense type, an Eigen sparse type, a limited number of Eigen expressions, a double,
or a `matrix_cl` which is matrix with data stored on an OpenCL device (targeting GPUs).

`var_value<T>` and `vari_value<T>` types are meant to be implemented with template
specializations. There is no expectation that `var_value<T>` will work in a generic
case.

For every `var_value<T>` that is defined, `vari_value<T>` must also be defined, and
`vari_value<T>` must inherit from the abstract class `vari_base` (since the autodiff
stacks now work via `vari_base` pointers). It is not true, however, that everything
that inherits from `vari_base` should be a `vari_value<T>`, or that for every
`vari_value<T>` there should be a `var_value<T>`.

`vari_base` is an abstract class that defines the interface by which everything
interacts with the autodiff stacks. Classes that inherit from `vari_base` require
implementation of two functions, `void chain()` and `void set_zero_adjoint()`,
which are called by the functions that manage the autodiff stacks.

There are three autodiff stacks in Stan, all which hold pointers to `vari_base`
objects:

1. The chaining autodiff stack
2. The non-chaining autodiff stack
3. The delete-ing autodiff stack

Instances of classes which inherit from `vari_base` can allocate themselves on
these stacks. Which stack an instance puts itself on depends on the requirements of
that instance. If the instance will need its `chain` function called in the
reverse pass, it must go on the first stack. If it does not, it goes on the second
stack. An instance should not go on both stacks. If the instance stores adjoints,
it should go on the first or second stack (both will call `set_zero_adjoint()` at
the appropriate time). If the instance needs a destructor called, it should go
on the third stack. The third stack is not mutually exclusive with the first
two, and an instance can go in either the first or second stack as well as the
third stack.

The only extra requirement on a `vari_value<T>` (on top of the requirements of being
a `vari_base` child class) is that it defines `val_` and `adj_` member variables of
an appropriate storage type. This does not need to match `T`. For instance, with
`vari_value<Eigen::MatrixXd>`, the underlying storage types are actually modified
`Eigen::Map` types.

The only extra requirement on a `var_value<T>` is that it contains one member
variable, a pointer to a `vari_value<T>`.

There are really not any other univeral requirements on `var_value<T>` or
`vari_value<T>` types. If they have common member variables like
`vari_value<T>::value_type`, `vari_value<T>::size`, or `vari_value<T>::val` that
make the type work more easily with the rest of the autodiff library, but nothing
is guaranteed.

## Use and Testing in Functions

Because `varmat` types are meant for performance, there are no default constructors
for building `matvar` types from `varmat` or `varmat` from `matvar` (or any of the
the `varmat` types above from any other). This is done on purpose to avoid implicit
conversions and any accidental slowdowns this may lead to. Everything written for
`varmat` types is done explicitly, which makes it somewhat less automatic than
`matvar`. The `matvar` types are still available for general purpose autodiff.

Testing `varmat` autodiff types for different functions is done by including a
`stan::test::test_ad_matvar(...)` mixed mode autodiff test along with every
`stan::test::test_ad(...)` test. The tests for `log_determinant`, available
[here](https://github.com/stan-dev/math/blob/develop/test/unit/math/mix/fun/log_determinant_test.cpp)
are typical of what is done.

`test_ad_matvar` checks that the values and Jacobian of a function autodiff'd with
`varmat` and `matvar` types behaves the same (and also that the functions throw
errors in the same places). `test_ad_matvar` is not included by default in `test_ad`
because not all functions support `varmat` autodiff.

`test_ad_matvar` also checks return type conventions. For performance, it is assume
a function takes in a mix of `varmat` and `matvar` types should also return a `varmat`.

A complete list of `varmat` functions is planned for the compiler implementation.
As an incomplete substitute, a list of functions with reverse mode implementations
that are being converted to work with `varmat` is here:
https://github.com/stan-dev/math/issues/2101 . A pull request
([here](https://github.com/stan-dev/math/pull/2214)) is up that adds support for
`varmat` to all the non-multivariate distribution functions.

## Assigning a `varmat`

A limitation from the original design doc that is no longer necessary is the limitation
that subsets of `varmat` variables cannot be assigned efficiently. The efficiency loss
was so great in the original design (requiring a copy of the entire `varmat`) that this
idea was discarded completely. There is a strategy available now to assign to subsets
of `varmat` variables that is more efficient than this.

The idea is that when part of a `varmat` is assigned to, the values in that part of the
`varmat` are saved into the memory arena before being overwritten, and a call is pushed
onto the chaining stack that will restore the values back from the arena and set the
respective adjoints of the `varmat` entries to zero.

The assumptions that makes this work is after a subset of a `varmat` is overwritten,
that part of the `varmat` cannot be used in any further calculations, and so the adjoints
of that part of the matrix will be zero in the reverse pass at the time of assignment.

This means that assignment into a `varmat` variable would make it so that views
point into that part of the `varmat` variable's memory no longer point to the expected
variables.

# Stanc3 implementation
[stanc3-implementation]: #stanc3-implementation

The stanc3 implementation goal is to implement `varmat` types in a way that
is invisible to the user. This means the compiler decides how Stan vectors, row
vectors, and matrices (or arrays of these types) are implemented automatically,
either picking an appropriate `varmat` or a `matvar` type, and these decisions should
be made in a way to avoid making programs slower than they would have been
with just `matvar` types. For brevity, any Stan vector, row vector, or matrix
type will be referred to from hereon as just a matrix type. Consider a linear
regression model:

```stan
data {
  int N;
  int K;
  matrix[N, K] X;
  vector[N] y;
}

parameters {
  vector[K] b;
  real<lower = 0.0> sigma;
}

model {
  vector[N] mu = X * b;
  target += normal_lpdf(y | mu, sigma);
}
```

In this program there are four named matrix variables, `X`, `y`, `b`, and `mu`.

It is immediately evident that because there are no autodiff types in the
`data` block, all the matrix types in there are implemented with doubles in
Eigen, so there is no `matvar` or `varmat` to worry about. The same thing
applies for `transformed data` and the `generated quantities` block.

This leaves `b` and `mu`, matrix variables defined in the `parameters` and
`model` block. Any matrix variable defined in a `transformed parameters` block
would be decided the same way.

The algorithm for figuring out the underlying matrix types for these variables
is as follows:

1. Define all user-defined functions only for `matvar` types, and all
internally defined variables and returned variables are `matvar` types as well.

2. Assume every named and unnamed matrix variable in the `parameters`,
`transformed parameters` and `model` blocks use `varmat` types

3. If a matrix variable is used in a function that does not support `varmat`
arguments, it is made a `matvar` variable.

4. If single elements of a matrix variable are indexed, it is made a `matvar`
variable.

5. If a `matvar` matrix variable is assigned to a second matrix variable,
the second is made to be a `matvar` variable.

6. Repeat steps 3-6 until the types of every variable in the program do not
change any more.

It is already possible to determine, given function name and a set of argument
types, if the function exists and what the return type is. Now that `matrix`
in Stan can mean multiple different types under the hood this lookup
functionality may need extended.

Step #4 in the algorithm above comes from the fact that indexing or assigning
a `varmat` is slower than a `matvar`.

# User-defined Functions
[user-defined-functions]: #user-defined-functions

The major component this design ignores are user-defined functions.
As long as more and more `varmat` functions are implemented and users are
able to move away from looping over matrix variables, more and more of the
matrix variables defined in the `parameters`, `transformed parameters`, and
`model` block will be compiled as `varmat` variables.

Whereas for functions implement in `stan-dev/Math` the list of allowed
signatures and return types can be computed ahead of time, for user defined
functions this would need iteratively computed along with the regular
variable types.

The proposal takes the simpler approach of assuming user-defined functions
are only defined for `matvar` types and only return `matvar` types.

# Original (rejected) Stanc3 Design
[original-stanc3-design]: #original-stanc3-design

The original proposal was that `varmat` variables would be explicitly typed, for
instance the Stan type `whole_matrix` instead of `matrix` would indicate that
the compiler should use a `var_value<Eigen::MatrixXd>` type. The control this
gives the user to optimize how their program is written is alluring, but this
creates the problem that either:

1. all functions written to support `varmat` types are documented explicitly
as such, and users are responsible for looking up which functions support the
`varmat` types and which do not,

2. or the compiler automatically convert `varmat` functions to `matvar` functions
when necessary to ensure compatibility with the new types.

Option #1 would be difficult to maintain and difficult for users to keep up
with. Option #2 is clearly simpler from a documentation perspective. However,
if #2 is implemented and the compiler is automatically casting between different
matrix types, which begs the question that maybe the compiler could do a
a pretty good job picking which matrix types to use.

# Prior art
[prior-art]: #prior-art

Discussions:
 - [Efficient `static_matrix` type?](https://discourse.mc-stan.org/t/efficient-static-matrix-type/2136)
 - [Static/immutable matrices w. comprehensions](https://discourse.mc-stan.org/t/static-immutable-matrices-w-comprehensions/12641)
 - [Stan SIMD and Performance](https://discourse.mc-stan.org/t/stan-simd-performance/10488/11)
 - [A New Continuation Based Autodiff By Refactoring](https://discourse.mc-stan.org/t/a-new-continuation-based-autodiff-by-refactoring/5037/2)

[JAX](https://jax.readthedocs.io/en/latest/notebooks/Common_Gotchas_in_JAX.html#%F0%9F%94%AA-In-Place-Updates) is an autodiff library developed by Google whose array type is similar to what is here.

[Enoki](https://github.com/mitsuba-renderer/enoki) is a very nice C++17 library
for automatic differentiation which under the hood can transform their autodiff
type from an arrays of structs to structs of arrays.

[FastAD](https://github.com/JamesYang007/FastAD) very fast C++ autodiff taking
advantage of expressions, matrix autodiff types, and a static execution graph.