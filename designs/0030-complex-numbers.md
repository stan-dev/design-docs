---
output:
  html_document: default
  pdf_document: default
---

# Complex Numbers Functional Specification

This is a proposal for adding complex scalar, vector, and matrix types to the Stan language.

This involves proposals for

- language types, constructors, and accessors
- I/O format for the generated C++ model class
- input format for JSON and R dump
- suggested data formats for the CmdStan, R, and Python interfaces

This proposal is backed by a full implementation of the [C++ complex number standard](https://en.cppreference.com/w/cpp/header/complex) in the Stan math library. 

## Quick overview of complex numbers

A complex number $z = x + yi$ is uniquely defined by a pair $(x, y)$ of real numbers, with $i$ being the imaginary unit $\sqrt{-1}$.  The complex number $z = x + yi$ is said to have a real component $x$ and imaginary component $y$.

The basic arithmetic and matrix operators extend to complex numbers as expected, given the reduction $i^2 = -1.$.  Other functions, such as sine and logarithm, have more complicated extensions to the complex domain.  C++ provides support for complex numbers through its `<complex>` header, which defines all of the basic mathematical operations on complex numbers.

## Goals

The goal of this feature is to allow users to code models involving complex numbers.  The reason we want to extend Stan to complex numbers is that many statistical problems are most naturally formulated in the complex domain.  For example, in imaging applications such as magnetic resonance imaging (MRI) and cryo electron microscopy (cryo-em), we do not observe an image, but only the magnitude (or modulus) of its discrete Fourier transform.  This is naturally a problem that requires a complex FFT operation.  Similarly, eigendecomposition of asymmetric matrices is fundamentally a complex operation, as is Schur decomposition.  Stationarity conditions for time-series models are often stated in terms of conditions on the magnitudes of complex roots.

The goal of this document is to be precise enough that
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
- `complex_vector[N]`: vector of complex values
- `complex_row_vector[M]`: row vector of complex values
- `complex_matrix[M, N]`: matrix of complex values

As usual, arrays can be constructed from any of these types.


### Constructors

A complex number is constructed from a pair of real numbers, one representing the real component and one the imaginary component.  The proposal is to have a function do that work.

```
real r;
real i;
complex z = to_complex(r, i);
```

This overloads the type name in the same way as a C++ constructor.  `to_complex` seems too wordy and `cmplx` too cryptic.

### Imaginary literals

Imaginary literals are formed the same way as in MATLAB, R, and Python using a real literal followed by a letter.  In Stan's case, we use `i`.  That means that `3i`, `-2.9i` or `157.23458i` are all complex numbers with the specified imaginary component and a zero real component.  These can be put together with addition to construct complex numbers using mathematical notation.

```
complex z = 3 - 2.9i;
```

### Accessors

The real and imaginary components of a complex number may be accessed as follows.

```
complex z;
...
real r = get_real(z);
real i = get_imag(z);
```

These accessors do not work as lvalues. 


### Equality

Equality for scalars is defined component-wise, so that if `z1` and `z2` are are complex typed variables, then `z1 == z2` is true if `to_rea(z1) == to_real(z2)` and `to_real(z1) == to_real(z2)`.

```
complex z1;
complex z2;
if (z1 == z2) { ... }
```

Note that this imports all of the usual difficulties of comparing floating-point numbers. Testing for equality of floating point and hence complex numbers should be avoided if possible.  Because of promotion, equality can apply to complex numbers mixed with real or integers.

### Promotion and function arguments

Currently in Stan, function argument types work like the type of an lvalue in an assignment.  An expression can be passed to a function as an argument of type `T` if the expression could be assigned to an argument of type `T`.  

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

In the same way that we can assign an `array[] int` to an `array[] real`, we will be able to assign `array[] int` and `array[] real` to `array[] complex`.

```
array[2] int n;
array[2] real x;
array[2] complex z;
z = x;  // legal
z = n;  // legal
x = z;  // ILLEGAL
n = z;  // ILLEGAL
```

Calling functions works the same way as assignment.

## Function support

All functions will support full mixing of real, integer and complex types, as well as mixing of data and parameter types (primitive and autodiff types at the math library level).

### Scalar arithmetic operators

All of the standard arithmetic operators, `+`, `-`, `*`, `/` and unary `-`, will be supported.  The binary operators allow mixing of real and complex scalars, with the result being a complex scalar.  These are already implemented in the C++ standard library for primitive complex types and in the Stan math library for complex autodiff types.

### Matrix arithmetic operators

The plan is to roll out support for all of the standard matrix arithmetic operators including all of the scalar operators as well as the left and right residuation operators (`\` and `/`).  Like their scalar counterparts, these will allow mixing of complex and real arguments with complex results.  These are implemented in the Stan math library. Like with the real-valued matrices, Stan also allows broadcasting of scalar arguments, so that `complex_vector + complex` should be defined to add the complex scalar to each element of the complex vector.  

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

As with vectors, promotion to the richest type found for an element will be carried out for array, vector, and matrix construction.


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

Parameters are output as an array.  Complex numbers will be sequenced with their real components before their imaginary components.  The output names for a complex variable `z` will be `z.real` and `z.imag` for the real and imaginary components.

For containers of complex numbers, the natural order is to indicate container indexing first.  For example, an entry for a matrix might look like `z.2.3.real` for the real component of the complex element at row 2 and column 3.


## File I/O formats

We have file-based output for samples and structured JSON or R dump format for input.  We use the same format for specifying data, initial values, etc., so there is only one format needed that will work for all of the interface needs.

### CmdStan output

CmdStan output just mirrors the C++ class output and will write headers the same way they are produced by the C++ class.

### JSON input

The key design aspect here is that we know when we want to read an array and know when we want to read complex numbers.  So we do not need to encode the complex/non-complex distinction directly in the output structure.  Specifically, we will follow the example in the 
[Python JSON spec](https://docs.python.org/3/library/json.html), which encodes a complex number `3 - 1.5j` as the list `[3, -1.5]`.  

A self-documenting JSON format might look like this, 

```
{ "real": 3, "imag": -1.5 }
```

but that's going to be far too verbose.

### R dump format input

The R dump format treats a complex number as a pair.  For a complex number with real component 3 and imaginary component 1.5, the R dump format is

```
z1 <- c(3, 1.5)
```


## Rationale and alternatives

Most of these proposals are just applying the simplest possible thing that is mathematically and computationally coherent.  For example, it's natural to promote `real` to `complex` in mathematics, so we allow it in the language.

### Container type alternative

It might be tempting to try to decompose types as C++ does, for example using `matrix<real>` and `matrix<complex>` or even `complex matrix`, etc.  One obstacle to this is that we use `<...>` for constraints, as in `matrix<lower = 0>`.  And we want to start stacking constraints, as in `real<multiplier = 7, offset = 3.9><lower = 0>`.  But the real reason not to do this is that there's not much shared between the matrices other than constructors, getters, and setters.

For example, complex numbers do *not* work with constraints.  It does not make sense to write `complex<lower = 0> z` or `complex<offset = 7>`.  



### R dump alternatives

Eventually, we might be able to adopt the standard R dump format for complex numbers, which separates the real and imaginary component with the 

```
z1 <- 3-1.5i
z2 <- 2.3+4.7i
```

### Accessor alternatives 

For accessors, we could use method-like notation, such as `z.real()`, but Stan does not use this kind of object-oriented notation elsewhere and it is less clear that the result can be used an lvalue.

We could also use accessors `z.real` and `z.complex` to parallel the design for tuples.


## Prior art

The prior art this proposal draws on includes

* Stan's existing handling of promotion of `int` to `real`,
* Stan's existing container constructors,
* Stan's tuple proposal currently being implemented,
* Stan's existing I/O formats for R and JSON,
* Stan's existing output format for the C++ model class,
* the C++ data type `complex` and associated operations from the `<complex>` header in the standard library,
* the Eigen C++ matrix library's handling of complex scalars, vectors, and matrices,
* R's standard dump format for complex numbers, and
* Python and MATLAB and R encodings of complex numbers and example of extending JSON to complex numbers.

This proposal follows all of this prior art directly.





