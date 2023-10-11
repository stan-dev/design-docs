- *Feature Name:* **Ragged Containers for Stan Language**
- *Start Date:* 2019-07-28
- *RFC PR:*
- *Stan Issue:*

# Summary
[summary]: #summary

Add sized ragged containers to the Stan language so that we can
support non-rectangular structures of any type with natural indexing.
The term "ragged container" is used because the resulting structures
might be arrays of vectors or matrices.


# Motivation
[motivation]: #motivation

Ragged data structures are ubiquitous.  Use cases include any data set
where there are differing numbers of observations.  Typical examples
include hierarchical models, which might contain different numbers of
item per group.  For example, the number of survey respondents may be
different in different groups, such as men and women, or European
vs. Asian residents.

The motivation for this proposal is that *ragged containers allow
ragged data to be represented and modeled using the same idioms as
rectangular containers.* In particular, we want to support vectorized
statements without slicing (which is hard to read and hence error
prone).

As of Stan 2.19, there is no built-in support for ragged containers.
See the [ragged array section of the user's
guide](https://mc-stan.org/docs/2_19/stan-users-guide/ragged-data-structs-section.html)
for an explanation of how ragged structures may be coded now through
slicing and/or long-form index fiddling.


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

A *ragged container* is nothing more than a container whose elements
may vary in size.

### Ragged arrays of reals

The simplest ragged container is a ragged array.  A simple non-trivial
example is: 

```
real[{3, 4}] x = {{a, b, c}, {d, e, f, g}};
```

Here we are assuming that the standard array expression will be
generalized to work for ragged arrays.  For example, `{1, 2}` is a
two-dimensional array of integers, and `{{1, 2}, {3, 4}, {5, 6}}`
denotes a three by two array of integers.

The variable `x` is a ragged two-dimensional array of size two.
Indexing works as usual, with

```
x[1] == {a, b, c}
```

and

```
x[2] == {d, e, f, g}
```

Sizing also works as expected, with

```
size(x) == 2
```

and

```
size(x[1]) == 3
size(x[2]) == 4
```

This array is ragged because the sizes of `x[1]` and `x[2]` are
different.  If `x[i1, ..., iN]` is the same for all valid indexes,
then `x` is said to be *rectangular*.

We write the unsized type of `x` the same way as for rectangular two-dimensional arrays,

```
x : real[ , ]
```

Declarations for ragged arrays are made up of the sizes of their
elements.  Declaring `x` of type and size `real[{3, 4}]` declares `x`
to be a two-dimensional array with `x[1]` having size three and `x[2]`
size four.

Providing an out-of-bounds index will raise the same exceptions (and
thus cause the same behavior in interfaces) as other out-of-bounds
errors.

A ragged three-dimensional array may be defined similarly; each
element in the sizing is the sizing of a ragged two-dimensional array.

```
real[{ {2, 3}, { 1, 2, 3 } }] y
  = { {{a, b, c}, {d, e, f, g}},
      {{h}, {i, j}, {k, l, m}} };
```

The size of `y` is the number of elements in its top-level
declaration, here `size(y) == 2`.  The first element of `y` is a
ragged two-dimensional array,

```
y[1] == {{a, b, c}, {d, e, f, g}}
```

and the second is

```
y[2] == {{h}, {i, j}, {k, l, m}}
```

The type of both `y[1]` and `y[2]` is `real[, ]`, the type of a
real-valued two-dimensional array.  This is a requirement of ragged
structures.

This brings up an important principle of ragged structures:  each
element in a ragged structure must be the same unsized type.  That is,
it's not possible to have a ragged array whose first element is
two dimensional and whose second element is three dimensional.

### Ragged arrays of vectors

In addition to arrays, the values of ragged structures may be vectors
or matrices.  For example, a ragged array of vectors may be declared
and defined as

```
vector[{3, 2}] v = { [a, b c]', [e, f]' };
```

The variable `v` is typed as an array of vectors, `v : vector[]`.  The
value of `v[1]` is the size three vector `[a, b, c]'`, whereas the
value of `v[2]` is the size two vector `[e, f]'`.  Both `v[1]` and
`v[2]` are of type `vector`.  All 

All size functions (`rows()`, `cols()`, etc.) work as expected.

Row vectors are handled identically, e.g.,

```
row_vector[{3, 2}] w = { [a, b c], [e, f] };
```

### Ragged arrays of matrices


Ragged arrays of matrices are more challenging to declare because
their base elements are two dimensional.  For example,

```
matrix[2, 3] u = [[a, b, c], [d, e, f]];
```

declares `u` to be a two by three matrix.  In order to deal with
ragged matrix declarations in general, the following declaration is
identical to the previous, for a two by three matrix,


```
matrix[{2, 3}] u = [[a, b, c], [d, e, f]];
```

This is chosen to match the dimensions declaration, where the function
`dims` returns a matrix's dimensions,

```
dims(u) == {2, 3}
```

A ragged array of matrices is declared using a sequence of sizes.  For
example,

```
matrix[{ {2, 3}, {3, 2}, {1, 2} }] v
 = { [[a, b, c], [d, e, f]],
     [[g, h], [i, j], [k, l]],
     [[m, n]] };
```

declares a one-dimensional array of matrices of size three, so

```
size(v) == 3
```

the dimensions of which are

```
dims(v[1]) == {2, 3}
dims(v[2]) == {3, 2}
dims(v[3]) == {1, 2}
```

Multidimensional arrays of matrices are handled in the same way.


### Constrained type declarations

Because all constrained types resolve at run time to real, integer,
vector, row vector, or matrix types, ragged containers of constrained
types may be declared in exactly the same way.

For instance, to declare a ragged two-dimensional array of
probabilities, we can use

```
real<lower = 0, upper = 1>[{3, 4}] x = {{a, b, c}, {d, e, f, g}};
```

We can declare a ragged array of simplexes as

```
simplex[{3, 2, 2}] theta
  = { [0.2, 0.7, 0.1]', [0.3, 0.7]', [0.0018, 0.9982]' };
```

Indexing and sizing is the same as for ragged arrays of vectors.

We can declare a two-dimensional matrix `Sigma` of size three,
containing a 3 by 3, 2 by 2, and another 2 by 2 matrix,

```
cov_matrix[{ {3, 3}, {2, 2}, {2, 2} }] Sigma
  = { [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
      [[1, 0.5], [0.5, 1]],
      [[2.3, 0.8], [0.8, 3.5]] };
```

Correlation matrices, as well as Cholesky factors of covariance and
correlation matrices may be declared the same way.

#### Square correlation and covariance matrices

*Optional*:  Because correlation matrices and covariance matrices are
 typically square, a 3-dimensional array of 2 by 2 covariance matrices
 may be declared as

```
cov_matrix[2][3] x
  = { [[1, 0], [0, 1]],
      [[3.1, -0.2], [-0.2, 3.1]],
      [[15.2, 0.1], [0.1, 15.2]] };
```

### Adoption note

Nothing changes in the language for declaring rectangular containers,
so this should be straightforward to teach to new Stan users.
Rectangular arrays are just a special case of ragged arrays in their
usage.


# Developer notes

This is covered in the reference-level explanation, but for the sake
of completeness, the main issues are

1. *Error checking*: Ragged structures can use exactly the same error checking for sizing
and assignment as rectangular containers, as these have the same C++
runtime types.

2. *I/O*:  The base `var_context` type and all implementations will need
 to be updated to deal with ragged structures.  Otherwise, this should
 not be a problem for either the R dump or JSON formats, as neither of
 them requires rectangular structures.

3. *type checking*: enhancing parser and code generator to allow
non-rectangular containers



# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

## Type and size inference

The typing can be explained with a sequence of simple sequent rules.
We currently have the array declaration base case

* `T[i1, ..., iN]`: `N`-dimensional array of `T`

and propose to add:

* `matrix[{i, j}]` as a base case with the same meaning as `matrix[i, j]`

The recursive case for an arbitrary type `T` is then just 

* if `x : T[arr]` then `x[i] : T[arr[i]]`

#### Examples

For example, if

```
x : real[{3, 2, 4}]
```

then

```
x[1] : real[3]
x[2] : real[2]
x[3] : real[4]
```

That is, `x` is a two-dimensional ragged array containing
one-dimensional arrays of sizes three, two, and four.  The variable
`x` itself will be represented as unsized type `real[ , ]`, which we
write as

```
x : real[ , ]
```

As such nothing distinguishes ragged from fixed types in their runtime types.

Now suppose

```
y : real[{{{3, 2}, {4, 5}}, {{3, 1}}}]
```

The unsized type of `y` is

```
y : real[ , , ]
```

a three-dimensional ragged array.  We have

```
size(y) = 2
```

and

```
y[1] : real[{{3 ,2}, {4, 5}}]
y[2] : real[{{3, 1}}]
```



```
y[1, 1] : real[{3, 2}]
y[1, 2] : real[{4, 5}]
y[2, 1] : real[{3, 1}]
```

It would be illegal to declare

```
real[{{3, 2}, {4, 5}}, {1, 2}}] z;
```

because `z[1]` would be of type `real[ , ]`, whereas `z[2]`
would be of type `real[]`.

Suppose we have a ragged array of matrices of type

```
u : matrix[{{2, 3}, {4, 5}}]
```

The type of `u` is just an array of matrices,

```
u : matrix[]
```

The elements are of type

```
u[1] : matrix[2, 3]
u[2] : matrix[4, 5]
```

## Static vs. dynamic sizing

The proposal is to wait for unsized local variables for dynamically
sized ragged containers.  Until then, ragged structures will behave
like Stan's other type, in that sizes are fixed at the point they are
declared and immutable afterward.  This will *not* require additional code as
the assignment function is already defined to do size matching.  

The one place where we have dynamic sizes is in function arguments,
and those will work just like assignment and should not require any
additional code generation or type checking.  The function argument
syntax is the one we've been using where a type is a contiguous
sequence of characters.


## Runtime types

The runtime type of a ragged container is the same as that of a
rectangular one.  This does not require any changes, as the
`std::vector<std::vector<int>>` used for two-dimensional arrays of
integers can support ragged arrays;  rectangular arrays are just a
special case where each element is the same size (all the way down to
through base types integer, real, vector, row vector, and matrix).


## Array expressions

We will need to generalize array expressions to permit ragged array
expressions, such as `{{1, 2}, {3, 4, 5}}`.  The underlying type will not
change (`vector<vector<int>>` in C++).  This will be
straightforward and existing assignment statements will be able to
handle all size checking.

## I/O format

#### JSON

The JSON format does not change.  Nor do the return types in the
interfaces.  The only change is that 

#### RDump

This is being deprecated in interfaces other than R, which reads it
natively.  Optionally, we could define a data format to allow ragged
containers in R.  The approach would be to use lists.  That is,
if a ragged container `x` was of size `N`, we'd represent it as
`list(x[1]', ..., x[N]')` where `x[n]'` is the encoding of `x[n]`.

## Cross assignment

We will be able to support the assignment of a ragged structure to a
rectangular structure and vice-versa.  Either way, the sizes will have
to match if the variable being assigned is a sized block variable.


# Drawbacks
[drawbacks]: #drawbacks

It will take developer effort to code, test, document, and maintain.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

A [preliminary
design](https://github.com/stan-dev/stan/wiki/Ragged-array-spec) was
refined online and motivated this design.  I don't consider it a
serious alternative to this proposal.

# Prior art
[prior-art]: #prior-art

For now, what we do is code things in one of two long forms.  Suppose
we have a sequence of sequences, each of which we want to model as a
time-series, say

```
int K;             // num items
int<lower = 0> N;  // observations
real[N] y;         // num observations
int[K] start;      // start of each series
int[K] end;        // end of each series
...
for (k in 1:K)
  y[start[k], end[k]] ~ foo(theta);
```

For example, we might have data

```
N = 15;
K = 4;
start = {1, 5, 7, 12};
end = {5, 7, 12, 16};
y = {1, 2, 3, 0, -1, 0.2, 3, 5,
     7, 9, 11, 15, 13, 11, 9};
```

With the new proposal, this will look like:

```
real[{4, 2, 5, 9}] yr
  = {{1, 2, 3, 0}, {-1, 0.2},
     {3, 5, 7, 9, 11}, {15, 13, 11, 9 }};
...
for (k in 1:K)
  yr[k] ~ foo(theta);
```

The new data structure will also be more efficient as a reference can
be returned from `yr[k]` rather than requiring a copy.

In some situations, long form can be used if there's no inherent
structure in the subarrays.  For example, we might have long form data

```
real[N] y
  = {1, 2, 3, 0, -1, 0.2, 3, 5,
     7, 9, 11, 15, 13, 11, 9};
int<lower = 1, upper = K>[N] kk = {1, 1, 1, 1, 2, 2, 3, 3, 3,
              3, 3, 4, 4, 4, 4};
...
for (n in 1:N)
  y[n] ~ foo(theta[kk[n]]);
```

whereas the ragged structure would either be

```
for (k in 1:K)
  y[k] ~ foo(theta[k]);
```

or even

```
y ~ foo(theta);
```

if `foo` is vectorized.

### Other languages

In R, they use lists, which allow heterogeneous containers.   The
ragged proposal here is more strongly typed.  MATLAB does not support
ragged arrays.

A language like C++ supports ragged arrays in the sense of allowing
containers to hold containers.  For example, you could have

```
using std::vector;
vector<vector<double>> y;
for (size_t i = 0; i < 100; ++i)
  y[i] = vector(0.0, i);  // y[i].size() == i
```

This C++ idiom will be supported when we have unsized local variables.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

Whether this gets implemented for the deprecated Rdump format of I/O.
(The JSON format should not need to change other than that loops need
to be size-bounded rather than constant-bounded.)

Ragged containers will play nicely with unsized local variables and
function arguments.

This proposal as written depends on allowing type declarations like:

```
real[...] x;
```

rather than

```
real x[...];
```

This is *not* critical for this proposal, though it does specify what
the function argument type language will look like (same thing without
sizes).
