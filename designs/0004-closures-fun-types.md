- *Feature Name:* closures-fun-types
- *Start Date:* 2019-08-31
- *RFC PR(S):*
- *Stan Issue(s):*

# Summary
[summary]: #summary

Add functional types and closures to the Stan language;  generalize
scope of function definitions.

# Motivation
[motivation]: #motivation

1.  Extend object sized and unsized type language to functional types.

2.  Allow general expressions, variables, function arguments of
    function types to support functional programming.

3.  Allow functions to be defined in any scope.

4.  Allow values of constant variables in lexical scope to be
    captured via closures without passing as arguments.


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

## Functional Types

#### First-order functions

Consider the multiplication function, which among other signatures,
requires a row vector and vector argument and returns their product, a
real value.  The function can be coded in Stan (without input
size validation) as

```
real mult(row_vector x, vector y) {
  real prod = 0;
  for (n in 1:cols(x))
    prod += x[n] * y[n];
  return prod;
}
```

This defines an identifier `mult` that is of type `real(row_vector,
vector)`.  In the type, the arguments are presented in order between
parentheses and the result is on the outside.

The types `real`, `int`, `vector`, `row_vector`, and `matrix` are all
first-order types.  Arrays of first-order types are also first-order
types, so that includes `real[]`, `int[ , ]`, and `row_vector[]`.  A
function is *first-order* if its arguments and result are first-order
types.  The current version of Stan only allows users to define
first-order functions.

#### Higher-order functions

A function that takes function arguments or returns a function is said
to be *higher-order* (we don't need to assign integer orders here;
this definition is just for convenience).

The arguments to a function might themselves be functions.  For
instance, consider a function that composes two other functions,

```
real compose_apply(real(real) f, real(real) g, real x) {
  return f(g(x));
}
```

The argument `f` is of type `real(real), i.e., a function from reals
to reals.  The argument `g` is of the same type.  The final argument
`x` is of type real.  The function simply applies `g` to `x`, then
applies `f` to the result.  The type of `compose_apply` is
`real(real(real), real(real), real)`.

Higher-order functions can also return functions as results.  For
example, consider the following version of multiplication that takes
its arguments one at a time (such functions are said to be *curried*
after Haskell Curry, one of the pioneers of higher-order logic and
computation).

```
real(vector) curry_mult(row_vector x) {
  return
    (vector y) {
      return mult(x, y);
    }
}
```

This definition introduces two new concepts, lambdas for anonymous
functions and closures, which we will unpack in the next two
sections.  For now, we will concentrate on implicit function typing.

The function `curry_mult` is of type `(real(vector))(row_vector)`,
meaning that it takes a single argument of type `row_vector` and
returns a result of type `real(vector)`, i.e., a function from
`vector` to `real`.  To avoid a pileup of parentheses on the left of
type expressions, we assume they are left associative, so that, for
example,

```
real(vector)(row_vector) == (real(vector))(row_vector)
```

Stan's types are what are known as *simple*, meaning they are
recursively composed of simpler types down to first-order types.  In
In contrast, programming languages like Lisp involve much more general
recursive typing, with which is possible to define a function that can
be applied to itself.  Languages OCaml go even further in allowing
mutually recursive templated type definitions.  This proposal sticks
to simple types.

#### Lambdas

The term "lambda" is derived from the lambda-calculus, the logic
behind functional programming languages from Lisp to OCaml.
Currently, a Stan function is defined with a name like the definition
of `mult` above.  With lambdas, we can define *anonymous functions*
that do not have names.

For example, consider the expression

```
(row_vector x, vector y) {
  return x * y;
}
```

This is a lambda defining a function that takes two arguments, a row
vector `x` and a vector `y`, and returns their product.  The return
type, `real`, is implicitly defined by the type of `x * y`.  Thus the
type of the whole expression is `real(row_vector, vector)`.

Using Stan's type language, we can declare a function variable and assign
a function expression to it.  For example

```
real(row_vector x, vector y) f;
...
f = (row_vector x, vector y) { return x * y; };
...
row_vector a = ...;
vector b = ...;
real c = f(a, b);
```

After this program executes, `c` will be equal to `a * b`.

Using the declare-define syntax, this provides an alternative
approach to defining functions,

```
real(row_vector, vector) mult
  = (row_vector x, vector y) {
      return x * y;
    };
```

The right-hand side of the expression defining `mult` is a lambda
defining an anonymous function; the left hand side declares the
variable `mult`, which is assigned the anonymous function as its
value.  The resulting value of `mult` is identical to the more
standard definition form,

```
real mult(row_vector x, vector y) {
  return x * y;
}
```

This standard form may be thought of as syntactic sugar for the lambda
and assignment.


#### Closures

Recall the definition of the curried form of row-vector/vector multiplication,

```
real(vector) curry_mult(row_vector x) {
  return (vector y) { return mult(x, y);  };
}
```

The value returned is an anonymous function, defined by

```
(vector y) { return mult(x, y);  }
```

More specifically, the value is a *closure* beause the variable `x`
takes its value from the value of `x` in an enclosing scope, here the
function argument `row_vector x`.  Stan employs *static lexical
scoping*, meaning that closures defined by lambdas such as the one
above capture values of variables in enclosing scopes, including
earlier in the Stan program.

For example, we can capture data variables by defining a function in
the transformed data block,

```
data {
  real x;
  real y;
}
transformed data {
  real foo(real z) {
    return x * y + z;
  }
}
```

The function `foo` defined in the transformed data block uses
variables `x` and `y`, which caputre the values of the variables `x`
and `y` defined in the data block.   The same approach may be used to
capture parameters by defining a function in the transformed
parameters block.  The type of `foo` is simply `real(real)`, as it
takes a real argument and returns a real result;  under the hood, the
function can store constant references to the variables `x` and `y` in the
enclosing scope for use when the function is evaluated.

Lambdas may also use closures.  For example, if the following appeared
in a block allowing statements, such as the top of the transformed
data block,

```
transformed data {
  real x = 12;
  real(real) h = (real u) { return u + x; };
  print(h(5));
  ...
```

the value 17 will be printed.  If the value subsequently changes in
the transformed data block, the original value will be used.

```
transformed data {
  real x = 12;
  real(real) h = (real u) { return u + x; };  // ILLEGAL CAPTURE OF x
  x = 1;
  print(h(5));
```

will still print `17`, because the value of `x` is captured, not a
reference.



This style of scoping for closures captures variables by value,
resolving which variable's value to use by static lexical scoping.
This latter term just means the variable to be used is known at
compile time and scoping is to the (lexical) environment in which the
lamda is defined. Any block variable in scope (that is, available to
be used or printed) may be used in a lambda.

Now we can put everthing together with an example to see how
composition might work.

```
real(real)(real(real))(real(real)) compose
 = (real(real) f) {
     return (real(real) g) {
       return (real x) {
         return f(g(x));
       }
     }
  };
real(real) sq = (real x) { return x^2; }
real(real) p1 = (real u) { return u + 1; }
real(real) sq_p1 = compose(sq, p1);
real y = sq_p1(5);  // y is 26
```

The composition function is written out directly in curried form.
Then the `sq` and `p1` variables are set to functions and passed into
`compose`.  We could repeat and evaluate `compose(sq_p1)(sq_p1)(3)`.
We cold also pass the lambdas in directly as argumens without ever
giving them names,

```
real(real) sq_p1
  = compose((real x) { return x^2; },
            (real u) { return u + 1; });
```





## Block variables only to prevent dangling references

Capture of local variables that are not block variables will not be
allowed.  (Block variables include those defined at the top level
scope of data, transformed data, parameters, transformed parameters,
and generated quantities;  it excludes the model block, which does not
have any block-level variables.)

This ensures that the variables remain alive even if they
would otherwise produce dangling references.  For example, the
following example is illegal because `a` is a local variable.

```
model {
  real a = 10;
  real(real) times_a = (real u) { return u * a; }  // ILLEGAL CAPTURE
```

In contrast, the following is acceptable, because `a` is a block variable.

```
transformed data {
  real a = 10;
  real(real) times_a = (real u) { return u * a; }
```


With pass by value, we do not run the risk of capturing dangling
references.  Consider the following example:

```
transformed data {
  real(real) f;
  {
    real y = 3;
    f = (real u) { return u + y; };
    real a = f(5);  // DEFINED --- y still in scope
  }
  real b = f(7);    // UNDEFINED --- y out of scope
```

Recall that the inner braces define a local scope; as soon as the last
statement executes, local variables go out of scope and have undefined
values.  Allowing capture of local vaiables by reference risks
capturing variables that disappear before the closure is used.  This
is one of the motivations for not capturing variables by reference.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

#### Variables captured by closure become constant

Once a variable is captured by a closure, it can no longer be
modified.  It is thus illegal to have

```
transformed data {
  real a = 10;
  real(real) times_a = (real u) { return u * a; }
  a = 5;  // ILLEGAL MODIFICATION OF CAPTURED VARIABLE
```

The result is that closures themselves become constant because there
is no way to change their behavior after they are created.

With the restriction to block variables discussed in the previous
section, we should be able to capture variables either by value (`[=]`
in C++) or by constant reference to a constant (`[&]` is sufficient because we do
not allow modification of variables once they are captured).


## Type system

The underlying type system for Stan relies on a notion of runtime
typing of all objects.  The runtime type does *not* include any
constraints.  The constraints are used for bounds checking for read or
constructed types and for transforms for parameters.

Sized types are used for block declarations and unsized types are used
for function arguments.  Local variables are currently sized, but in
the future will be allowed to be unsized.


#### Unsized runtime types

The set of unsized runtime types is the least set of types such that

* *unsized primitive type*: `int` and `real` are unsized types,
* *unsized vector type*: `vector` and `row_vector` are unsized types,
* *unsized matrix typen*: , `matrix` is an unsized type,
* *unsized array type*: `T[]` is an unsized type if `T` is an unsized type, and
* *unsized function type*: `T0(T1,...,TN)` is an unsized type if `T0`, `T1`, ..., `TN`
are unsized types.



#### Covariance and contravariance

If we wanted to get fancy, we could use the polarity of type
occurrences in function types to extend assignability.  For the base
case, we have `int` as a subtype of `real` in the sense that we can
assign an `int` expression to a `real` variable but not vice-versa.
Covariant typing would extend this as follows.

* `int` is a subtype `real`,
* `T[]` is a subtype of `U[]` if `T` is a subtype of `U`, and
* `T0(T1, ..., TN)` is a subtype of `U0(U1, ..., UN)` if
  `T0` is a subtype of `U0`, `U1` is a subtype of `T1`, ..., `UN` is a
  subtype of `TN`.

The type `T` in the array type `T[]` is covariant in that it preserves
subtyping.  The type `T` in `T(U)` is similarly covariant, but `U` is
contravariant, in that it reverses the subtyping relationship.  As a
concrete example, consider legal types for `a` (the lvalue) and `b`
(the rvalue) in `a = b`,

| lvalue type  | legal rvalue types                     |
|:------------:|:--------------------------------------:|
| `int(int)`   | `int(int)`, `int(real)`                |
| `real(real)` | `real(real)`, `int(real)`              |
| `int(real)`  | `int(real)`                            |
| `real(int)`  | `real(int)`, `real(real)`, `int(real)` |


#### Sized types

The set of sized runtime types is the least set of types such that

* *sized primitive type*: `int` and `real` are sized types,
* *sized vector type*: `vector[K]` and `row_vector[K]` are sized
types if `K` is a non-negative integer,
* *sized matrix type*: `matrix[M, N]` is a sized type if `M` and `N` are
  non-negative integers,
* *sized array type*: `T[]` is a sized type if `T` is a sized type, and
* *sized function type*: `T0(T1,...,TN)` is a sized type if `T0`, `T1`, ..., `TN`
are sized types.


## Lambda Expression Syntax

Syntactically, a lambda expression is represented as a function argument
list followed by a function body.   For example, in `(real u) { return
1 / (1 + exp(-u)); }`, the function argument list is `(real u)` and
the function body is `{ return 1 / (1 + exp(-u)); }`.

As a shorthand, a function argument list followed by an expression is
taken to be shorthand for the function argument list followed by a
function body returning that expression.  For example, the lambda
expression

```
(real u) { return 1 / (1 + exp(-u)); }
```

may be replaced with the equivalent

```
(real u) 1 / 1 + exp(-u)
```

Lambda expressions behave like other expressions such as `2 + 2`, only
they denote functions rather than values and have function types.


## Changes to Standard Functions

Allow functions to be defined in any scope.  Allow function
definitions and lambda expressions to capture variables in scope by
value.

Deprecate the functions block;  functions declared there can be
declared in the transformed data block.

Standard function definitions of the form

```
T0 f(T1 x1, ..., TN xN) { ... }
```

may be replaced with

```
T0(T1, ..., TN) f = (T1 x1, ..., TN xN) { ... }
```

## Variable declarations

Variable declarations for functions follows the usual syntax, with a
sized type required for block variables, an unsized type for function
arguments, and either a sized (as of 2.20) or unsized (future) type
for a local variable declaration.


## Assignment

Nothing changes conceptually about assignment.  The right-hand side
type must still be assignable to the left-hand side type, which for
functions, means they have the same function type.  The only question
is whether to require strict matching of types or support full
covariance and contravariance.

## Implementation

Lambdas can be mapped directly to C++ lambdas with default value
closures.  This will work because the scope of the compiled C++ is the
same as that of the Stan program.


# Drawbacks
[drawbacks]: #drawbacks

Like all new features, more coding, testing, doc, and ongoing maintenance.

Higher-order programming is hard.  If we use too much of it, we risk
alienating users who are looking for something simpler.

There is no I/O for types with functions in them, as there is no way
to save a function.  This will complicate various test programs and
I/O programs involving typed variables.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

This is really two proposals, one for closures (for capturing
variables in scope) and one for lambdas (for anonymous functions).
Although they naturally go together, it would be possible to adopt
closures without lambdas or vice-versa.

Disallowing lambdas would complicate standard functional idioms like
maps, which rely on simple inline anonymous lambdas.

Disallowing closures requires passing all values to higher order
functions as arrays along with the packing and unpacking required.

# Prior art
[prior-art]: #prior-art

Most major languages support both lambdas and closures.  I'll survey
the ones that are most relevant to our project in that they'll be the
most familiar to our users.

#### C++

The proposal here follows the
[C++11 style of lambdas and closures](https://en.cppreference.com/w/cpp/language/lambda)
both syntactically and semantically.  The sublanguage for specifying
unsized types directly mirrors the type syntax of C++11.

C++ allows an explicit specification of whether variables are captures
by reference or by value; the proposal here is equivalent to having
the captures at the front of the lambda expression be explicitly
specified as captured by reference, `[=]`, which
specifies that all automatic variables used in the body of the lambda
be captured by value.  Automatic variables are those without
explicit capture declarations; all variables in this proposal for Stan
will behave as automatic variables.

#### R

R captures by reference using dynamic lexical scope.

In R, the expression `function(u) { return(1 / (1 + exp(-u))) }`
defines a function that denotes the inverse logit function.  It can be
assigned to a variable, e.g.,

```
inv_logit <- function(u) { return(1 / (1 + exp(-u))); }
theta <- inv_logit(0.2)
```

Unlike C++ or Stan, R requires the outer parentheses for returns.  R
provides a convenient shortcut that the body of a function returns its
last evaluated expression if there is no return statement, so the
inverse logit function can be rewritten as

```
inv_logit <- function(u) { 1 / (1 + exp(-u)) }
```

We can go one step further and drop the braces, as they are only there
to allow a sequence of statements to be grouped,

```
inv_logit <- function(u) 1 / (1 + exp(-u))
```

This is the abbreviated syntax we recommend here for Stan lambdas,
where the equivalent would be

```
real(real) ilogit = (real u) { return 1 / (1 + exp(-u)); };
```

or in abbreviated form,

```
real(real) ilogit = (real u) 1 / (1 + exp(-u));
```

R uses the unusual mechanism of dynamic lexical scoping, meaning that
a lambda will capture whichever variable exists in its environment
when executed.  This can lead to non-deterministic behavior of
variable scopes at runtime.  This proposal for Stan is to use the more
traditional approach of static lexical scoping, which is what is used
in C++.


#### Python

Python captures variables by reference.

Python allows lambdas such as `lambda u : 1 / (1 + exp(-u))`.
Multiple argument functions my be `lambda x, y : (x**2 + y**2)**0.5`.
Python captures variables by reference in lambdas, as the following
example demonstrates.

```
>>> x = 3
>>> f = lambda y : (x**2 + y**2)**0.5
>>> f(4)
5.0
>>> x = 10
>>> f(4)
10.770329614269007
```

This is the same capture-by reference that is used by R as well as the
behavior for C++ if the captures specification takes all implicit
captures by reference (`[&]`).  We are explicitly proposing to capture
variables by value here.


# Unresolved questions
[unresolved-questions]: #unresolved-questions

None at this point unless someone wants to suggest an alternative
syntax.  I just borrowed the C++ syntax.
