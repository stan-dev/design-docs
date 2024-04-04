- Feature Name: 0034-mixtures
- Start Date: 2024-02-14
- RFC PR:
- Stan Issue:

# Summary

The mixtures feature is designed to allow users to specify mixture
models using a consistent density-based notation without having to
worry about marginalizing the discrete parameter manually or about
working on the log scale.


# Motivation

Users writing their own mixture models has been error prone.  A
specific failure mode is vectorization and mixing over the whole
population versus mixing over individuals.  The latter is almost
always intended, but the former is what a naive Stan program will
do.


# Guide-level explanation

In both the two-component and multi-component mixture syntax, a new
distribution function will be introduced, which is described in this
section.  


## Two-component mixtures.

A two-component normal mixture model will be written in canonical form
as follows.

```stan
y ~ mixture(p,
            normal(m[1], s[1]),
            normal(m[2], s[2]));
```

Here, `p` is a probability in (0, 1) and `normal(m[1], s[1])` acts
like a lambda binding of the first argument (more on that below).
This notation would be syntactic sugar for the following expression

```stan
target += log_sum_exp(log(p) + normal_lpdf(y | m[1], s[1]),
                      log1m(p) + normal_lpdf(y | m[2], s[2]));
```

Because this follows distribution syntax, for consistency we would
also define the probability functions `mixture_lpdf` and `mixture_lpmf`
```stan
mixture_lpdf(y | p, lp1, lp2)
=def=
log_sum_exp(log(p) + lp1(y), log1m(p) + lp2(y));
```

Here we have have explicitly used application syntax for `lp1` and
`lp2`, even though it doesn't exist in Stan.  For discrete
distributions, we will also need a `mixture_lpmf`.

If Stan had C++ style lambdas, a distribution without an outcome
variable would be defined as follows.

```stan
normal_lpdf(m[1], s[1])
=def=
[y].normal_lpdf(y | m[1], s[1])
```

Even though a distribution without an outcome behaves like a lambda in
the context of mixtures, this will *not* be generally available in
Stan, so that it would not be legal to write the following.

```stan
target += normal(m[1], s[1])(y);  // ILLEGAL
```

## Require probability function arguments

Although it would be possible to allow arbitrary functions to
participate in mixtures, in the first release we propose to not allow
arbitrary functions and restrict the arguments after the first to be
probability functions (lpdfs or lpmfs).  The workaround in this
case is to take the function and wrap it in an lpdf or lpmf
definition.  We may add arbitrary function arguments at a later date
after we introduce lambdas into Stan.

For example, to define a zero-inflated Poisson as a mixture model,
the lpmf that puts all of its mass on 0 can be defined and then used
as one of the mixture components.

```stan
functions {
  real zero_delta_lpmf(int y) {
    return y == 0 ? 0 : -infinity();
  }
}
...
real<lower=0, upper=1> p;
...
model {
  y ~ mixture(p, zero_delta, poisson(lam));
```


## Mixtures with more than two components

Up until now, we have assumed two mixture components and a probability
argument.  In general, we want to allow more than two mixture
components.  The proposal is to have the first argument be a syntax
whose  size determines the numnber of remaining arguments.  For
example, the following would be a legal way to define a 3-component mixture.

```stan
simplex[3] p;
...
y ~ mixture(p, normal(m[1], s[1]),
               normal(m[2], s[2]),
               student_t(4.5, m[3], s[3]));
```

Run-time error checking is largely a matter of making sure the simplex
argument is both a simplex and the right size for the number of
components, or if it's a probability, checking that there are two
components and that the value is in (0, 1).

In terms of compilation, `mixture` is another variadic function with type
checking. 

## Comparison to existing `log_mix` function

This functionality is more general than the existing `log_mix`
functionality, which requires actual log density values as arguments.
In this case, the above mixture would be written as

```stan
simplex[3] p;
...
target += log_mix(p, normal_lpdf(y | m[1], s[1]),
                     normal_lpdf(y | m[2], s[2]), 
                     student_t_lpdf(y | 4.5, m[3], s[3]));
```

The `log_mix` function is slightly different than the `mixture`
distribution and while it could be deprecated in favor of `mixture`,
it would also make sense to keep it.



# Reference-level explanation

The implementation requires `mixture_lpmf` and `mixture_lpdf` to be
coded in C++.  These will be variadic functions that accept either (a)
one probability argument and two probability functions without
variates, or (b) one simplex, and a number of probability functions
matching its size.

Derivatives can be handled by autodiff, or an "analytic" derivative
for `mixture_lpmf` and `mixture_lpdf` can be supplied.

## Interactions with other features

There are no interactions with other features.

## Boundary conditions and exceptions

The boundary conditions are simple.  If zero mixture components are
supplied, it should throw an exception.  This is better than returning
`-infinity` and letting the user try to debug the rejection. 
If only a single mixture component is supplied with a size 1 simplex,
a warning should be emitted suggesting simplified usage.

## Include normalizing constants

The distributions have to be compiled with `propto=False` and this
needs to be made clear in the documentation.   Statistically,
`propto=False` is required to get the correct result when the mixture
components don't have equal normalizing constants.

## Catching out of bounds exceptions in variates

Stan's probability functions are designed to throw
`std::invalid_argument` exceptions when they encounter illegal
arguments.  In this case, we want to catch any exceptions that come
from the variate being mixed being out of bounds.  That is, if
we use `exponential(2)` as one of our mixture components, then
we want a negative argument `exponential_lpdf(-1 | 2)` to return
`-infinity` rather than throw an exception.

To handle that, we propose to change the exception thrown in the math
library to a subclass of `std::invalid_argument` which we will call
`stan::math::invalid_variate`.  This is a simple change in the math
lib for type of exception thrown and will not break backward
compatiblity. 

# Drawbacks

It's yet one more kind of ad hoc parsing that doesn't fit into the
type system until we have functions.

## Rationale and alternatives

This design is close to optimal as it matches the way a statistician
might write a mixture in mathematical notation.

The alternative is to just require users to keep using the `log_mix`
function or writing their own custom code.

The impact of inaction here is just that it's harder for users to
write readable and robust mixture models.


## Limitations

This proposal is not intended to address infinite mixtures, like a gamma-Poisson.

## Prior art

Prior art is basically just `log_mix` and some examples of how to code
by hand in the mixtures chapter of the *User's Guide*.

I am not aware of other probabilistic programming languages that
include this feature.  This is way too small of a feature for a paper.


# Resolved questions

1.  Should we allow function arguments or force user to write `_lpdf`
or `_lpmf` functions?  No.

2.  Should we allow one-component mixtures as the boundary condition?  Yes.

3.  Should `normal(m, s)` be interpreted as a function elsewhere in
Stan.  No.

