- Feature Name: Declaration Annotations
- Start Date: 2022-02-28
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

This design proposes a general framework for adding arbitrary metadata to
declarations in Stan programs through the use of optional _annotations_ on
function and variable declarations. An annotation is constructed by prefixing a
declaration with `@foo` where 'foo' is (in the most general case) any string.
Different backends may choose different sets of annotations to recognize, and
should ignore annotations they do not need, except to perhaps produce a warning.

# Motivation
[motivation]: #motivation

Currently, the Stan compiler makes several optimizations which are difficult to
automatically detect and apply. Additionally, there has long been the desire for
user defined gradients and transformations in the language.

One core issue connecting both of these is _information_: How could a user
communicate that this object is meant to be optimized (placed in GPU memory, or
treated as static and using the Struct-of-Arrays style), or that this function
serves as the gradient (or transform, etc.) of a different function?

There are various proposals to solve each of these. For example, we could add a
`matrix_gpu` type which is specifically declared to be used in GPU
computation, or a `static_matrix` type for Struct-of-Arrays usage. For
user-defined gradients and transforms, we could specify in the language that a
function `foo` has a user-defined gradient specified by a function with the
exact name `foo_grad`, or that a function `foo_constrain` must be declared
alongside `foo_free`.

However, each of these adds additional special cases to the language, and ones
that might not be valid in all cases: what is the behavior of `matrix_gpu` if it
is compiled on a machine without a GPU, or it is compiled targeting a Python
backend? Furthermore, good luck if you want a static matrix allocated on the
GPU, unless we introduced a third `static_matrix_gpu`.

The following proposal suggests one alternative way to solve the problem of
communication between the user and the compiler in a general way which scales
well as the number of things one would like to tell the compiler increases.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation


## Annotations

It is possible to give Stan further information about your model through the use
of **annotations** on function and variable declarations. An annotation is
indicated with an `@` symbol followed by text, and it is placed before the
return type of the function or the type of the variable, like so

``` stan
functions {
  @foo void bar(int x){...}
}
parameters {
  @baz matrix[3,3] A;
}
```

Annotations can be identifiers, like the above examples, or they can be more
complicated. An annotation ends when it encounters a space, except if there are
parentheses used, in which case it ends when the final `)` is reached.

``` stan
@bar(1, 2, 3) vector[N] alpha;
@this(is( fine )) matrix[N,N] B;
```

Annotations are optional - both to you, and to the compiler. You may write
anything you want in an annotation, or leave them off entirely. Furthermore, the
compiler will ignore* any annotation it does not recognize.


### Why Use Annotations

Annotations give hints to Stan about details of how to treat your model. For
example, if you are using a backend which supports computation on GPUs, then the
annotation

``` stan
@gpu matrix[N,M] p;
```

Can give the compiler an extra push toward allocating `p` in the GPU's memory
rather than in standard RAM. The optional nature means that a model with this
annotation can also be used-without modification-in backends that do not
support GPU computation, and it will be safely ignored.

### Example Annotations

The following are annotations which may be supported by various backends or
optimization settings. Please consult (link to backend specific documentation).

(Author's Note: This design doc does not specifically endorse or propose any of
these, they are all provided as examples which this larger framework would
allow. A key feature, however, is that none of these are really new
*features*-they do not increase the expressiveness of Stan, only allow tweaks
and efficiency considerations)

- `@gpu` - When used on variables, indicate to the compiler that you desire this
  variable to be placed in GPU memory and optimized for GPU computation.
- `@const` - When placed on a variable, indicate that it will not be edited and
  is a candidate for Struct-of-Array optimizations.
- `@likely` and `@unlikely` - When placed on an integer which is used as the
  test of a conditional, these annotations directly translate to the `likely`
  and `unlikely` markings in the generated C++.
- `@extern` - When placed on a function declaration, mark it as not needed a
  definition in the program. This is equivalent to a more targeted version of
  the `--allow-undefined` flag available for stanc3.
- `@grad_adj_jac(foo,1)` - This annotation, when placed on a function, indicates that this
  function defines the derivative of another function called `foo` along the
  first argument to said function.
- `@inline` - This annotation suggests that the compiler should specifically
  attempt to inline the function it is placed on during optimization.

----

* Note: In reality, the compiler will produce a warning when an unknown
  annotation is used. This is mainly to help you - it would be a shame if a
  simple typo in an annotation led to the compiler ignoring your intention
  without even letting you know.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation


The implementation of this in the stanc compiler is fairly simple. If an
annotation is parsed before a variable or function declaration, the contents of
that annotation (as a **string**) will be stored in the metadata of that
declaration throughout the AST and MIR stages. Individual backends, such as the
`stan::math` C++ backend can use these to perform specific optimizations or
other compiler passes, and print warnings for any annotations they do *not*
process.

These warnings mainly serve to avoid typos: if `@stati` is used, we
don't want to silently ignore it and let the user assume that they're getting
the optimizations they would if they had truly typed `@static`. The reason they
are not errors should be obvious - we want these annotations to be
forward-and-backward compatible in time, and we want different backends to still
be able to process the same model without modification.

The presence of annotations signals the compilers to transform the program while
maintaining the same behavior (up to floating point precision).
Particular annotations will be introduced one at a time, each with their own
review process. When adding a new annotation, care must be taken to ensure it
behaves nicely with existing annotations; either they must compose in a natural
way, or the existing annotations will take precedence over the new annotation if
there are any conflicts between the effects of a new annotation transformation
and the existing annotation transformations.

The examples provided at the end of the previous section provide a few examples
of the kind of thing the C++ backend may want to consider supporting. Other
backends may want to support a subset of these, or a completely different set
altogether. The primary goal of this proposal is to allow this - to let a
thousand flowers bloom, in a sense - while we all continue to speak the same
core language.


# Drawbacks
[drawbacks]: #drawbacks


Even though the annotation system would be entirely optional, documenting which
annotations are available under which conditions adds to documentation and
increases the number of things a user needs to keep track of if they want to get
the most out of Stan.

Additionally, there is the potential that introducing such a general system
would prompt some features which use annotations in ways that do meaningfully
change the semantics of a program, such as trying to use the annotations to
introduce new forms of transformation for certain backends. This is not
necessarily a reason not to implement the system, but something to keep in mind
when performing code review for *uses* of it.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The power of this design is its generality. There are many designs and
optimizations which would benefit from the ability for the user to supply just a
little bit of extra information to the compiler. Annotations allow this to be
done in a way that **does not**

1. Introduce new syntax or types for each one of these features, such as the
   `matrix_gpu` type discussed in the introduction
2. Require every backend or consumer of Stan programs to support all of these.

It is reasonable to imagine an extension of this where each declaration could
have more than one annotation, and indeed this would be relatively simple and
allow composition where it makes sense. The alternative is to simply support a
compound annotation, so rather than `@static @gpu matrix ...` it would simply be
`@static_gpu matrix`.

There is no true alternative which solves the same problem to this level of
generality. Individual examples of it's use all have alternatives, but they
usually require much tighter coupling with the core language.


## Static or const as a part of the core language

Specifically the concept referred to above as `@static` would be more powerful
if it was implemented as part of the core language in such a way that allowed it
to be enforced by the typechecker. This could be pursued in conjunction with the
annotation framework, but would be a keyword modifier instead.


# Prior art
[prior-art]: #prior-art

The name, style, and purpose of annotations in Stan is very similar to how
[Java solves the same
problem](https://docs.oracle.com/javase/tutorial/java/annotations/) ([JSR-175](https://www.jcp.org/en/jsr/detail?id=175)).

The use of the `@` sign is also used in Python's decorator syntax
([PEP-318](https://www.python.org/dev/peps/pep-0318/)). Similar syntax is used
in Julia for [macro
application](https://docs.julialang.org/en/v1/manual/metaprogramming/), and in
general is a recognizable syntax for this kind of metadata.

The usage is also similar to the
[compiler-specific
annotations](https://gcc.gnu.org/onlinedocs/gcc/Common-Function-Attributes.html#Common-Function-Attributes)
available in C and C++.

Finally, annotations (and specifically the `@silent` annotation) were included
in [early designs for the stanc3 compiler](https://github.com/seantalts/stan3/tree/170e6afc5b0e00dc5f201a25a881b7aa11f679b2#stan-3-language-goals).

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- The specifics of which annotations would be useful or possible is valuable to
  discussion of this RFC, but it is not the ultimate goal of this proposal. If
  we provide a general strucure for user-compiler communication, there will be
  opportunities to use it that are difficult to foresee now, in addition to the
  obvious ones discussed above as examples.
- Should multiple annotations be allowed on one declaration? This does not pose
  any additional implementation cost, but does lead to questions of what to do
  if two contradictory or incompatible annotations are applied to the same
  declaration.
