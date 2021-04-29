---
output:
  html_document: default
  pdf_document: default
---

# Complex Numbers Functional Specification

This is a proposal for adding complex number, vector, and matrix types to the Stan language. This involves proposals for

- language types, constructors, and accessors
- I/O format for the generated C++ model class
- input format for JSON and R dump
- suggested data formats for the CmdStan, R, and Python interfaces

This proposal is backed by a full implementation of the [C++ complex number standard](https://en.cppreference.com/w/cpp/header/complex) in the Stan math library. 

At their heart, complex numbers are nothing more than pairs of real numbers with a bunch of special functions defined over them.


## Goals

- The goal of this feature is to allow users to code models involving complex numbers.

- The goal of this document is to be precise enough that
    - users can understand the feature well enough to evaluate it, and
    - developers can work on a technical specification for the implementation.

## Design considerations

- The main design consideration is that Stan programs involving complex numbers be easy to write, and just as importantly, easy to read.

- We should follow the basic design of Stan types, including promotion structure and associated covariance (in the CS not stats sense).

- I/O structures need to
    - balance self documentation and efficiency, and
    - be easy to adapt to the interfaces and analysis tools.


## Assumptions

- The language will target C++ code in the Stan math library.


## Stan data types

The following four basic data types will handle all of the complex number functionality we need:

- `complex`:  scalar type
- `complex_vector`: vector of complex values
- `complex_row_vector`: row vector of complex values
- `complex_matrix`: matrix of complex values

As usual, arrays can be constructed from any of these types.

### Constructors

A complex number is constructed from a pair of real numbers, one representing the real component and one the imaginary component.  The proposal is to have a function do that work.

```
real r;
real i;
complex z = to_complex(r, i);
```

This is very verbose, but we don't want to use just `complex(r, i)` because we don't want functions confused with types.  We could use a simple pair structure instead of `to_complex(r, i)`, such as `{ r, i }`, `<r, i>`, or `[r, i]`, but these notations are already used for arrays, constraints, and row vectors respectively.  Or we could use an ad-hoc abbreviation like `cmplx(r, i)`, but that's hard to remember and we elsewhere try to avoid abbreviations where possible.

### Accessor lvalues

The real and imaginary components of a complex number may be accessed as follows.

```
complex z;
...
real r = z.real;
real i = z.imag;
```

This follows the C++, Java, and Python conventions for accessing components of structures (including tuples).  It uses the C++ standard library's naming convention for the components.  We could instead use a function-like accessor notation, such as `z.real()`, but that feels less clear that it can be used an lvalue.  

These accessors work as lvalues, so that the following will be allowed

```
complex z;
...
z.real = 5.2;
```

with the result being that `z` now has 5.2 as its real component---that is, it's a destructive operation.

### Equality

Equality is defined component-wise, so that `z1 == z2` for complex typed variables `z1` and `z2` is true if `z1.real == z2.real` and `z1.imag == z2.imag`.  

```
complex z1;
complex z2;
int a = (z1 == z2);
```

Note that this imports all of the usual difficulties of comparing floating-point numbers. Testing for equality of floating point and hence complex numbers should be avoided if possible.

### Promotion and function arguments

Currently in Stan, function arguments work like assignment.  You can use a variable for a function argument if and only if it could be assigned to a variable of the type of that argument.  

Currently Stan allows promotion of `int` values to `real` values but not vice-versa, so that 

```
int a;
real b = a;
```

is legal, but

```
real b;
int c = b; // ILLEGAL
```

is not.

We will extend the notion of promotion in Stan by allowing real numbers to be promoted to complex numbers, but not vice versa.  By transitivity, this will allow assignment of real- or integer-typed expressions to complex variables or function arguments.  In particular,

```
int a = 2;
real b = 3.7;
complex z1 = a;
complex z2 = b;
```

is legal, but not the other way around

```
complex z;
int a = z;  // ILLEGAL
real b = z;  // ILLEGAL
```

As of now, there is no general promotion for arrays, and there are only real-valued matrices.  With the introduction of complex-valued vectors and matrices, we need to support assignment of real-valued vectors and matrices to their complex counterparts.  That is,

```
real_matrix[2, 3] x;
complex_matrix[2, 3] z = x;
```

is legal (and similarly for vector and row-vector types), but

```
complex_matrix[3, 4] u;
real_matrix[3, 4] x = u;  // ILLEGAL
```

This carries through to calling functions, too.

## Function support

All functions will support full mixing of real, integer and complex types, as well as mixing of data and parameter types (primitive and autodiff types at the math library level).

### Scalar arithmetic operators

All of the standard arithmetic operators, `+`, `-`, `*`, `/` and unary `-`, will be supported.  The binary operators allow mixing of real and complex scalars, with the result being a complex scalar.  These are already implemented in the C++ standard library for primitive complex types and in the Stan math library for complex autodiff types.

### Matrix arithmetic operators

The plan is to roll out support for all of the standard matrix arithmetic operators including all of the scalar operators as well as the left and right residuation operators (`\` and `/`).  Like their scalar counterparts, these will allow mixing of complex and real arguments with complex results.  These are implemented in the Stan math library.

### Matrix and array constructors

The array and matrix constructors will extend to complex numbers. Like their behavior with real numbers, the result should be the promoted type.  For example,

```
complex z1;
complex z2;
complex_vector[2] v = [z1, z2]';
```

is fine, as is

```
complex z1;
real x2;
int n3;
complex_vector[3] v = [z1, x2, n3]';
```

but not

```
complex z1;
real x2;
vector[2] v = [z1, x2]';  // ILLEGAL, [z1, x2]' type is complex_vector
```

Complex matrices should be constructible from sequences of complex row vectors,
as in

```
complex z;
complex_matrix[2, 2] m
  = [[1, z], [z, 1]];
```

Arrays are constructed as usual,

```
complex z1;  complex z2;
complex z[5] = {z1, z2, z3, 1, 2.8};
```

As with vectors, promotion to the highest type will be carried out for array construction.


### Elementwise operators

The elementwise vector and matrix operations, `.*` and  `./`, should work as expected, carrying out their operations elementwise.    They should allow mixed complex and real results, e.g.,

```
vector[2] x;
complex_vector[2] y;
complex_vector[2] z = x .* y;
```

### Scalar functions

Every scalar complex function available in the C++ standard library `<complex>` header will be included.  These are already implemented in the Stan math library.

### Matrix functions

There are no matrix functions exposed through the math library, but fast Fourier transforms (FFT), asymmetric eigendecomposition, and Schur decomposition have all been implemented and are part of the unit tests for complex numbers.


## C++ model class

Stan programs are converted to C++ class definitions by the stanc3 transpiler.   There are two components in this compiled class that.  This section covers data input and parameter output.  User-facing I/O is handled by the interfaces.

### Data input format

The C++ model class uses an object of class `var_context` to input variables declared in the data block.  This object needs to be extended to read complex number objects.  To read a complex number, we must read a sequence of two real numbers to pass to the C++ `complex<double>` constructor.

### Parameter output format

Parameters are output as an array.  Complex numbers will be sequenced with their real components before their imaginary components.  The output names for a complex variable `z` will be `z.r` and `z.i` for the real and imaginary components.

For containers of complex numbers, the natural order is to indicate container indexing first.  For example, an entry for a matrix might look like `z.2.3.r` for the real component of the complex element at row 2 and column 3.

## File I/O formats

We have file-based output for samples and structured JSON or R dump format for input.  We use the same format for specifying data, initial values, etc., so there is only one format needed that will work for all of the interface needs.

### CmdStan output

CmdStan output just mirrors the C++ class output and will write headers the same way they are produced by the C++ class.

## JSON input

The key design aspect here is that we know when we want to read an array and know when we want to read complex numbers.  So we do not need to encode the complex/non-complex distinction directly in the output structure.  Specifically, we will follow the example in the 
[Python JSON spec](https://docs.python.org/3/library/json.html), which encodes a complex number `3 - 1.5j` as the list `[3, -1.5]`.  

A self-documenting JSON format might look like this, 

```
{ "real": 3, "imag": -1.5 }
```

but that's going to be far too verbose.

## R dump format input

We can adopt the standard R dump format for complex number output, which separates the real and imaginary component with the 

```
z1 <- 3-1.5i
z2 <- 2.3+4.7i
```

## Rationale and alternatives

Most of these proposals are just applying the simplest possible thing that is mathematically and computationally coherent.  For example, it's natural to promote `real` to `complex` in mathematics, so we allow it in the language.  Similarly, it's natural to 

### Container type alternative

It might be tempting to try to decompose types as C++ does, for example using `matrix<real>` and `matrix<complex>` or even `complex matrix`, etc.  One obstacle to this is that we use `<...>` for constraints, as in `matrix<lower = 0>`.  And we want to start stacking constraints, as in `real<multiplier = 7, offset = 3.9><lower = 0>`.  But the real reason not to do this is that there's not much shared between the matrices other than constructors, getters, and setters.

For example, complex numbers do *not* work with constraints.  It does not make sense to write `complex<lower = 0> z` or `complex<offset = 7>`.  

There are not good alternatives to these proposals that would differ in things other than minor details.

The biggest issue is how much covariance do we want to support given that it's not yet fully supported for `int` and `real`.  For example, it'd be nice to allow assignment of `int[]` to `real[]` and of `real[]` to `complex[]`.

## Prior art

The prior art this proposal draws on includes:

* Stan's existing handling of promotion of `int` to `real`
* Stan's existing container constructors
* Stan's existing I/O formats for R and JSON
* Stan's existing output format for the C++ model class
* the C++ data type `complex` and associated operations from the `<complex>` header in the standard library
* R's standard dump format for complex numbers
* Python encodings of complex numbers and example of extending JSON to complex numbers

This proposal follows all of this prior art directly.




