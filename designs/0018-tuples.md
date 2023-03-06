- Feature Name: Tuples
- Start Date: 2020-04-23
- RFC PR:
- Stan Issue: https://github.com/stan-dev/stan/issues/2431

# Summary
[summary]: #summary

This proposal is to add tuples to the Stan language. Tuples are _static_,
heterogeneous containers, meaning that they have a known, fixed size in the
program and can contain elements which are of different types and sizes. They
allow access only at known elements (known as "projection"), rather than dynamic
indexing. Tuples are common in many languages from Python to OCaml and C++.
Formally, a tuple is a product type of its contained types.

# Motivation
[motivation]: #motivation

Tuples support several important use cases.

One common use for tuples is to support _multiple return_, allowing functions to
return more than one type of value simultaneously. For example, a function could
be defined which returns both a matrix and some real-valued property of this
matrix. In the math library, this can be used for cases such as singular value
decomposition. Currently, two different functions must be called to receive the
two portions of the decomposition, and this duplicates computation.

Some forms of data are best represented by a mix of different types or different
sizes of the same type; currently it is not possible in Stan to package these
together.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

A tuple is the generalization of the idea of a pair to any number of elements.
In Stan, tuples allow packaging of different types together into one value.

## Declaration

A tuple variable is declared as follows

```
tuple(T1, ..., TN) x;
```

where `T1` through `TN` are themselves type specifications. Tuples are
recursive - they can contain other tuples.

A pair containing one integer and one real value could be declared

```
tuple(int, real) p;
```

These types can be any Stan type which would be valid in that block/context. For
example, one can define a parameter which is a pair of an array of real values and a
simplex like so

```
tuple(array[5] real, simplex[10]) param;
```

Tuples can be used as function arguments and return types.

## Tuple expressions

The expression for creating tuples will be `(a, b, c)`.  This will create a tuple
of type `tuple(typeof(a), typeof(b), typeof(c))`, each subject to the normal
promotion rules.

This is inspired by the syntax currently used for arrays (`{value, value2, ...}`),
and for row vector expressions (`[value1, value2, ...]`) with the notable
difference that tuples allow mixes of types among their different values.

For example, `(1.5, {2.3, 4})` is a tuple with type `tuple(real, array[2] real)`.

## Tuple accessors

A key difference between tuples and other containers in Stan is that they have a
fixed size which is known during compilation. As such, they are accessed using
indexing which is also known during compilation. This is done using `.` followed
by a integer literal after the tuple. This static indexing is also known as
projecting.

For example,
```
tuple(S, T, U) x;
...
S a = x.1;
T b = x.2;
U c = x.3;
// x.4 causes compilation error
```

It is **not** possible to write
```
x[1]; // not valid
x.n; // not valid
```

## Assignment

Tuples and their elements may be used on the left hand side of assignment
statements, as in:

```
tuple(double, int) a;
a = (3.7, 2);  // assign to
a.1 = 4.2;
```

## Promotion (covariance)

Like other Stan container types, tuples are covariant. That means that whenever
`a` is a subtype of `b` (e.g., `int` is a subtype of `real`), then
`tuple(..., a,...)` is a subtype of `tuple(..., b, ...)` as a tuple.

This would allow you to assign an integer and double tuple to a pair of double
value tuples, etc. For example, `tuple(int, double, matrix)` assignable to
`tuple(double, double, matrix)`.

## Input and Output formats

These proposals are specific to the CmdStan interface.

### JSON input format

Tuples are represented as JSON objects with indices stored as keys.

For example, the Stan declaration `tuple(int, array[2] real) d;` can be represented
in JSON as follows:

```json
{
  "d": {
    "1": 3,
    "2": [3.5, 6.7]
  }
}
```

### CSV output format

Like all Stan objects, tuples are flattened into a single row for output. Due to
the existing convention of using `.` for array and matrix indices in the output
format, the `:` character is used.

For example, the Stan declaration `tuple(int, array[2] real) d;` will produce the
following column headers in the output CSV file:

```csv
d:1, d:2.1, d:2.2
```

## Special functions (optional)

The following special functions for tuples could be defined. These would be
impossible to write in a generic way in the language itself, so any
implementation would need to be in the standard library.

```
T1
head(tuple(T1, ..., TN) a);
```

```
tuple(T2, ..., TN)
tail(tuple(T1, T2, ..., TN) a);
```

```
tuple(T1, T2, ..., TN)
concat(T1 a, tuple(T2, ..., TN) b);
```

## Destructuring assignment (optional)

A common feature of other languages with tuples is destructuring ("unpacking")
through assignment, e.g.

```
int x;
int y;
(x, y) = (1, 2)
```
leaves `x` with value `1` and `y` with value `2`.
This feature makes programming with tuples much more elegant.
This feature is often paired with the the convention of having `_` serving as an
indicator to ignore a value, so the assignment `(x, y, _) = (1,2,3);` has the
same result as above.

Some languages support this without the need for the enclosing parenthesis. This
is possible in Stan, but would have conflicts with the multiple declaration
syntax `int x,y;` -- the line `int x,y = a;` could be interpreted two different
ways depending on if `a` has type `int` or type `(int,int)`.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

## C++ Implementation

Tuples will be represented directly by using the C++11 `std::tuple` type.

### C++ I/O Support

#### Serializer interface
Serialization/deserialization of tuples (i.e., in parameters or for the
`transform_inits` function) is done elementwise. It is possible to extend the
deserializer interface to directly construct the desired tuples, but due to the
fact that tuples can contain some portions which are constrained, elementwise IO
best supports this.

#### Var_context interface
Data reads (using `var_context`) are more complicated, since the current
implementation assumes a 1:1 correspondence between the name of a variable and a
homogeneous, rectangular array of values. Additionally, due to the use of
virtual functions, templating is not available.

The proposed solution is to treat each sub-element of the tuple like a unique
name in this context. The `var_context` object would then store things like
`"name.1"`. These would be homogeneous and flat, like other variables. This may
require both nesting (e.g. a variable named something like `"name.2.1"`), and
also possibly unzipping (e.g, an array of tuples is stored in var context as a
set of parallel arrays).


This is best shown by a complicated but illustrative example:

Given the Stan declaraction `array[2] tuple(int, tuple(real, array[3] complex)) data;`

- The call `context.vals_i("data.1")` should return a `std::vector<int>` of
  length 2.
- The call `context.vals_r("data.2.1")` should return a `std::vector<double>` of
  length 2.
- The call `context.vals_c("data.2.2")` should return a
  `std::vector<std::complex<double>>` of length 2*3 = 6. The data from this call
  should be the data for `data[1].2.2` followed by the data for `data[2].2.2`,
  concatenated together into one vector.

It is the job of the compiler to generate code which takes these objects and
produces one object `data` of the desired type and shape. This is similar to how
the current implementation reads in matrices as a flat array and generates the
necessary code to reshape them.

Dimension validation is also done with these flat names. In the same order as
above:

- The expected dimensionality of the first element (in the sense of
  `context.validate_dims(...,"data.1", ...)`) is the vector `{2}`.
- The expected dimensionality of `"data.2.1"` is the vector `{2}`.
- The expected dimensionality of `"data.2.2"` in the var context is the vector
  `{2,3,2}`, since in JSON complex values are represented as a length-2 array.


### Stan library support

Several functions will need additional overloads to support the implementation
of tuples in the language:

 - The `stan::assign` function will be updated to support tuple types directly.
 - `promote_scalar` will need to accept tuple types and `std::vectors` of tuples
 - `print` and `reject` will both need support for turning tuples into string representations

## Compiler implementation

The implementation of tuples in the compiler is _conceptually_ simple, but
requires a large effort to execute.

The current types in the compiler are (roughly) specified by the following
recursive type defintion:

```ocaml
type t =
  | Int
  | Real
  | Complex
  | Vector of size
  | RowVector of size
  | Matrix of size * size
  | ComplexVector of size
  | ComplexRowVector of size
  | ComplexMatrix of size * size
  | Array of t * size

```

To add tuples, this is extended to include:

```ocaml
  | Tuple of t list
```

However, the current compiler also makes several assumptions about the nature of
types in the language. Adding a type that is both heterogeneous and
non-rectangular requires inspecting, and possibly updating, large portions of
the code in the compiler.

Some abstractions, such as the function `dims_of`
which takes in a type and returns a list of integers which represents the length
of each dimension of said type, are nonsensical in the context of tuples and
must be rethought or removed.

While the compiler already features a recursive type in arrays, it is a much
simpler kind of recursion than that of tuples. Much of the handling of arrays
consists of finding out what the innermost type of the array is and proceeding
from there; with tuples, there is no such easy way out. They must be handled in
a way which is truly recursive.

# Drawbacks
[drawbacks]: #drawbacks

Supporting tuples in the language requires a large jump in the complexity of the
type system, both in terms of their implementation in the compiler and the need
of users to understand them.

Several portions of the compiler require very complicated re-writes to break
assumptions about types being rectangular and homogeneous, and similar work must
be done in the C++ library.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

## Tuples vs Structs/Records

Product types can also be implemented as a record type, where each component is
given a named label rather than an integer index. These are analogous to structs
in C. Languages such as OCaml support both.

Labeled product types are desirable independently from tuples and implementing
one should not preclude the other from consideration. Indeed, much of the work
needed to implement tuples would make the later implementation of structs much
easier.

## Alternative declaration syntax
The syntax `(T1,T2,T3)` was considered as an alternative to `tuple(T1,T2,T3)`.
This is is used by Python and OCaml, but is less explicit and may be confusing
for users. The use of the keyword `tuple` also makes searching programs easier,
and aligns with the `array` keyword used in Stan 2.26+.

This syntax is **not** used for tuple expressions. While it could be, this is
overly verbose and looks like a function call rather than an expression.

One advantage to using this for expressions _would_ be more natural handling of singleton tuples.
Using only parenthesis leads to the issue (also found in e.g. Python) where the
expression `(1)` is not a tuple containing an int, but just an integer. The
tuple expression is `(1,)`. This somewhat awkward syntax is also used by Stan,
but we additionally note that even compared to something like Python, the
singleton tuple in Stan is exceptionally useless and will likely never appear in
a program "in the wild".

## Alternative JSON formats

Two other formats were considered for JSON representations.

The first is one used by Python natively to dump out tuples, which is
non-rectangular arrays. For example, the same declaration from earlier,
`(int, array[2] real) d;`, would be represented as follows

```json
{
  "d": [ 3, [3.5, 6.7] ]
}
```

This is more compact, but considerably more complicated to read in and store.
To understand why, consider that the types `array[10,2] real` and
`array[10] (int, real)` would be representable by the same JSON format.

The second is a more "flattened" format similar to the proposed internal
representation in `var_context`. The same declaration again would be:

```json
{
  "d.1": 3,
  "d.2": [3.5, 6.7]
}
```

This format gets increasingly complicated as the declaration is more and more
nested, and is painful for both a user and any interface to prepare, but it
would be the simplest to implement internally. It is preferable that this level
of implementation detail not become something the user or interfaces need to
worry about.

Finally, the selected JSON format is also desirable for if structs are
implemented at a later time.

# Prior art
[prior-art]: #prior-art

Tuples are a common feature of many programming languages:

- [std:tuple in C++](https://en.cppreference.com/w/cpp/utility/tuple)
- [Tuples in Python](https://docs.python.org/3/tutorial/datastructures.html#tuples-and-sequences)
- [Tuples in OCaml](https://dev.realworldocaml.org/guided-tour.html#tuples)

Note that the tuples proposed here differ from Python tuples and R lists by
being statically declared and typed.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Which, if any, standard library functions should accept or return tuples.
- How the `get_dims` function of the model class should handle tuple parameters
  (see [stanc3#1242](https://github.com/stan-dev/stanc3/issues/1242))
