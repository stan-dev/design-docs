- Feature Name: 0034-mixtures
- Start Date: 2024-02-14
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

The mixtures feature is designed to allow users to specify mixture
models using a consistent density-based notation without having to
worry about marginalization and working on the log scale.



# Motivation
[motivation]: #motivation

Users writing their own mixture models has been error prone.  A
specific failure mode is vectorization and mixing over the whole
population versus mixing over individuals.  The latter is almost
always intended, but the former is often coded.


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The syntax follows that of a distribution.  For example, a
two-component normal mixture model could be written in canonical form
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
define
```stan
mixture_lpdf(y | p, lp1, lp2)
=def=
log_sum_exp(log(p) + lp1(y), log1m(p) + lp2(y));
```

where we have explicitly used application syntax for `lp1` and `lp2`.

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

Unary functions will be allowed as function arguments to `mixture`, so the
following would be legal.

```stan
functions {
  real normal1(real y) {
    real m1 = ...; 
    real s1 = ...; 
    return normal_lpdf(y | m1, s1); 
  }
  real normal2(real y) {
    real m2 = ...; 
    real s2 = ...; 
    return normal_lpdf(y | m2, s2); 
  }
}
... 
real<lower=0, upper=1> p; 
...
model {
  y ~ mixture(p, normal1, normal2);
}
```

The alternative to allowing function arguments would be to force the
user introduce new distribution functions, such as the following,
which defines a zero-inflated Poisson as a mixture model.

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

The idea is to allow arbitrary numbers of components in the mixture,
with the first argument being a simplex matching in size.  For
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

In terms of compilation, this is another variadic function with type
checking. 


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The implementation requires `mixture_lpmf` and `mixture_lpdf` to be
coded in C++.  These will be variadic functions that accept one simplex
argument and a parameter pack of mixture components that must in practice be
the same size as the simplex (only discoverable at runtime).

Derivatives can either be supplied by autodiff, or they can be done
analytically, where the adjoint rule is just going to mix the adjoints
of the components according to the simplex.

There are no interactions with other features.

The boundary conditions are simple.  If zero mixture components are
supplied, it should throw an exception.  This is better than returning
-infinity and letting the user try to debug the rejection.  
If only a single mixture component is supplied, it should provide a
warning that the use can be simplified.

# Drawbacks
[drawbacks]: #drawbacks

It's yet one more kind of ad hoc parsing that doesn't fit into the
type system until we have functions.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

This design is close to optimal as it matches the way a statistician
might write a mixture in mathematical notation.

The alternative is to just require users to keep using the log_mix function.

The impact of inaction here is just that it's harder for users to
write readable and robust mixture models.

# Prior art
[prior-art]: #prior-art

Prior art is basically just `log_mix` and some examples of how to code
by hand in the mixtures chapter of the *User's Guide*.

I am not aware of other probabilistic programming languages that
include this feature.  This is way too small of a feature for a paper.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

1.  Should we allow function arguments or force user to write `_lpdf`
or `_lpmf` functions?  Proposal says YES.

2.  Should we allow one-component mixtures as the boundary condition?
    Proposal says YES.

3.  Should `normal(m, s)` be interpreted as a function elsewhere in
Stan.  Proposal says NO.

This proposal is not intended to address infinite mixtures, like a gamma-Poisson.
