- Feature Name: `jacobian` target
- Start Date: 01-25-2024

# Summary
[summary]: #summary

This design doc proposes adding a `jacobian` target and a new block for user defined constraints. The `jacobian` target will be accessible directly in `transformed parameters` and a new `constraints` block where users can define custom constraints similar to Stan's already existing constrained data types. 
The examples below show an example use case.

```stan
constraints {
 upper_bound {
   // Constrain x to have an upper bound
   real constrain(real x, real upper_bound) {
     jacobian += x;
     return upper_bound - exp(x);
   }
   // Constrain a vector x to have an upper bound
   real constrain(vector x, real upper_bound) {
     jacobian += sum(x);
     return upper_bound - exp(x);
   }
   // Unconstrain real x from the upper bound
   real unconstrain(real x, real upper_bound) {
     return log(upper_bound - x);
   }
   // Unconstrain vector x from the upper bound
   vector unconstrain(vector x, real upper_bound) {
     return log(upper_bound - x);
   }
   // Validate x has an upper bound
   int validate(real x, real upper_bound) {
     return x < upper_bound;
   }
 }
}
data {
 real ub;
 int<lower=0> N;
}
parameters {
 // User defined constraint
 real<constraint upper_bound(ub)> b;
 vector<constraint upper_bound(ub)>[N] b_vec;
}
```

Users can also access `jacobian` directly in the `transformed parameters` block.

```stan
data {
 real lb;
}
parameters {
 real c_raw;
}
transformed parameters {
 // Transform and accumulate jacobian
 real c = exp(c_raw) + lb;
 jacobian += c_raw;
}
```
# Motivation
[motivation]: #motivation

Given a function $c$ mapping unconstrained parameters in $Y$ to constrained parameters in $X$, probability density function $\pi$, and a Jacobian determinant function over the constrained space $J(c(y))$, Stan calculates the log transformed density function [2]

$$
\pi^*(y) = \pi\left( c\left(y\right) \right) J_c\left(y\right)
$$

$$
\log\left(\pi^*(y)\right) = \log\left(\pi\left( c\left(y\right) \right)\right) + \log\left(J_c\left(y\right)\right)
$$

The Stan languages has built in constraints constraints such as `lower`, `upper`, `ordered`, etc. to handle $ \log\left(J_c(y)\right)$. A variable (unconstraining) transform is a surjective function $f:\mathcal{X} \rightarrow \mathbb{R}^N$ from a constrained subset $\mathcal{X} \subseteq \mathbb{R}^M$ onto the full space $\mathbb{R}^N$.
The inverse transform $f^{-1}$ maps from the unconstrained space to the constrained space. 
Let $J$ be the Jacobian of $f^{-1}$ so that $J(x) = (\nabla f^{-1})(x).$ and $|J(x)|$ is its absolute Jacobian determinant. A transform in Stan specifies 

- $f(y)$ The unconstraining transform
- $f^{-1}\left(y\right)$ The inverse unconstraining transform
- $\log |J(y)|$ The log absolute Jacobian determinant function for $f^{-1}$ chosen such that the resulting distribution over the constrained variables is uniform
- $V(y)$ that tests that $x \in \mathcal{X}$ (i.e., that $x$ satisfies the constraint defining $\mathcal{X}$).

Having the Stan language define types for transforms from the unconstrained to constrained space allows users to focus on modeling in the constrained space while algorithm developers focus on developing algorithms in the unconstrained space. 
This is very nice for both parties since it is both of their preferred spaces to work in.

Most of the time this encapsulation is very good. 
The main issue is that Stan users either have to write code that either only uses Stan's built-in transforms to stay in the constrained space or works directly on the unconstrained space. 
For instance, from a comment [3] by @betanalpha (slightly commented and fleshed out)

-----------

> It’s only in the context of trying to assign a density on the output value that a Jacobian is needed, so the proper encapsulation is

```stan
functions {
 real f(real x) {
   // transform function
 }
 real jacobian(real x) {
   // jacobian determinant calculation
 }
 real prob(real x) {
   // lpdf calculation
 }
}
parameters {
 real theta;
}
transformed parameters {
 real eta = f(theta);
}
model {
 // In a pure sense, neither line is well defined on it's
 //  own, but the combinations are well defined.
 eta ~ prob(values);
 target += jacobian(theta);
}
```

-----------

Coding transforms directly across multiple blocks (parameter, transformed parameter, model) is clunky and error prone. 
And when users want to add a constraint to the Stan language they have to touch the math library which is rather complicated. 
Not just by C++ itself, but the essentially small DSL we use to describe autodiff in the Stan math library.

Having a new block for user-defined constraints allows users to encapsulate and reuse their transforms as units.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The following section is a draft of the docs for the new constraint and `jacobian` keyword.

## Constraint Block

### Overview

The constraints block was included in Stan 2.XX to provide users with the ability to define custom constraints on parameters, transformed parameters, and data. 
This block is situated immediately after the `functions` block and before the `data` block in a Stan program. 
The primary purpose of the `constraints` block is to allow users to define custom constraints that can be used in the same way as built-in constraints.

### Syntax

A constraints block is defined by the keyword `constraints`. 
Inside of the `constraints` block each constraint is its own block with a given `constraint_name` and the functions needed to define the constraint.
Inside the `constraints` block, users can define one or more constraint types. Each constraint type is encapsulated within its own set of curly braces and is identified by a unique name.

Each constraint type must specify a set of functions that define the transformation between unconstrained and constrained spaces, validate data, and increment the log of the absolute value of the determinant of the Jacobian. 
The first argument for all functions defined in a constraint must be the argument of interest to be transformed or validated. These functions include:

- `constrain(TransformType, OtherArguments...) -> ReturnType`: Transforms a real unconstrained variable to a constrained space.
- `unconstrain(TransformType, OtherArguments...) -> ReturnType`: Transforms a real constrained variable back to the unconstrained space.
- `validate(TransformType, OtherArguments...) -> ReturnType`: Validates a real variable against the constraint, returning 1 if valid and 0 otherwise.

The pseudocode below shows the structure of a user defined constrained. All CamelCase names are to be replaced by the user.

- `ConstraintName`: The name of the constraint which will be called by users from within the `<>` of Stan's [data types](https://mc-stan.org/docs/reference-manual/overview-of-data-types.html).
- `ReturnType`: A Stan data type that is the return type of the function
- `UnconstrainType`: A Stan data type that is the variable to be transformed or validated.
- `OtherArgs` The rest of the Stan data types that are passed to the constraint during construction of the data type that is being constrained.


```stan
constraints {
 ConstraintName {
   // Transform from unconstrained to constrained space
   ReturnType constrain(UnconstrainType, OtherArgs...) {
     // ... transformation logic ...
     // Increment Jacobian
     jacobian += ...;
     return ...;
   }

   // Transform from constrained to unconstrained space
   ReturnType unconstrain(UnconstrainType, OtherArgs...) {
     // ... inverse transformation logic ...
     return ...;
   }

   // Validate data
   int validate(UnconstrainType, OtherArgs...) {
     // ... validation logic ...
     return ...; // typically returns a boolean value
   }
 }
}
```

### Using the jacobian Keyword

The `jacobian` keyword is introduced within the `constraint` block to allow the Jacobian accumulator to be incremented by the log absolute determinant of the Jacobian of the constraining transform. This keyword behaves similarly to the `target` keyword, allowing users to account for the change of variables in the probability density function. The `jacobian` keyword is available in both the `constraints` block and the `transformed parameters` block.

### Declaring Variables with User-defined Constraints

Variables can be declared with user-defined constraints in the data, transformed data, parameters, transformed parameters, and generated quantities blocks. The syntax for declaring a variable with a user-defined constraint is as follows:

```stan
type<constraint constraint_name(args...)> variable_name;
```

Here, `constraint` denotes a user-defined constraint and `constraint_name(args...)` specifies the name of the constraint along with any arguments it requires.

### Example Usage

```stan
constraints {
 upper_bound {
   real constrain(real x, real upper_bound) {
     jacobian += x;
     return upper_bound - exp(x);
   }
   real unconstrain(real x, real upper_bound) {
     return log(upper_bound - x);
   }
   vector constrain(vector x, real upper_bound) {
     jacobian += sum(x);
     return upper_bound - exp(x);
   }
   vector unconstrain(vector x, real upper_bound) {
     return log(upper_bound - x);
   }
   int validate(real x, real upper_bound) {
     return x < upper_bound;
   }
 }
}
data {
 real a;
 real u_bound;
 int N;
}


transformed data {
 // Data will use the validate() function from the user-defined constraint
 real<constraint upper_bound(u_bound)> c = a;
}


parameters {
 // User-defined constraint applied to parameters alpha and b
 real<constraint upper_bound(u_bound)> alpha;
 vector<constraint upper_bound(u_bound)>[N] b;
 // In these cases this is the same as calling
 // real<upper=u_bound> alpha;
 // vector<upper=u_bound>[N] b;
}
```

In this example, `upper_bound` is a user-defined constraint that is applied to the data and parameters. The `validate()` function from `upper_bound` is used to validate `a_validated` in the `transformed data` block, and the transformations defined in `upper_bound` are applied to `alpha` and `b` in the parameters block.

### Error Messages

Inside of a constraint, if a `constrain` function is defined then an `unconstrain` function must also be defined with the same signature as `constrain`.

```
constraint(vector x, real upper_bound) for {CONSTRAINT_NAME} does not have an associated `unconstrain(vector x, real upper_bound)`. If you define one then you must define both!
```

If a user defined constraint type is used in `data`, `transformed data`, or `transformed parameters`, or `generated quantities` then the constraint must have a validate function for that given type. For example, if a user calls a constraint named `lower_bound` tha does not have a `validate()` function then the error message will look like:

```
// vector<constrain lower_bound(lb)> x;
a `lower_bound` constraint was given to `x`, but `lower_bound` does not have a validate(vector, real) function.
```


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The first thing we would do is add the `jacobian` keyword to the Stan language. Like `target`, `jacobian` would only be available on the left hand side of statements to be accumulated into. Its domain is restricted to the `transformed parameters` and `constraints` block.

This section will break down the model given in the summary section to show what the Stan compiler requires piece by piece. First, let's look at the `constraints` block where we define our constrain and unconstrain functions

## Constraint Block

```stan
constraints {
 upper_bound {
   constrain(real x, real upper_bound) {
     jacobian += x;
     return upper_bound - exp(x);
   }
   real unconstrain(real x, real upper_bound) {
     return log(upper_bound - x);
   }
   // Used for data
   int validate(real x, real upper_bound) {
     // For most this will be
     return x < upper_bound;
   }
 }
}
```

The new `constraints` block will need to be added to the compiler's parser, validator, mir, and c++ mir. The parser will transpile each of the constraints to c++ functions which start with the name of the constraint. For the example above the signatures would be

```c++
upper_bound_constrain__(...)
upper_bound_unconstrain__(...)
upper_bound_validate__(...)
```

The only function of the three listed above that has rules that differ from standard function generation is the `*_constrain` function which has an additional `jacobian` argument and `Jacobian` template parameter. The jacobian is kept behind an if statement that checks the compile time value `Jacobian` before incrementing the jacobian. Besides the jacobian argument the rest of the function will parse exactly like a standard function.

```c++
template <bool Jacobian, typename T1, typename T2, typename TJacobian>
return_type_t<T1, T2> upper_bound_constrain(const T1& x, const T2& upper_bound,
  TJacobian& jacobian) {
 if (Jacobian) {
   // If x is a vector we can
   //  wrap the right hand side in a sum()
   jacobian += x;
 }
 return subtract(upper_bound, exp(x));
}
```

The `_unconstrain` function will not be used directly by the user and instead will be used internally in the Stan model class when we need to go from the constrained to unconstrained space. The code generation for these will be the same as a standard function.

## Transformed Parameters

Inside of transformed parameters we expose `jacobian` like in the functions section listed below. Any jacobian accumulation will be wrapped in an `if (Jacobian)` so that the Jacobian increment only happens when requested.

```stan
parameters {
 real b_raw;
}
transformed parameters {
 // (2) Transform and accumulates like stan math directly
 real b = exp(b_raw) + lower_bound;
 // Underneath the hood, only actually calculated if
 // Jacobian bool template parameter is set to true
 jacobian += b_raw;
}
```

# Drawbacks
[drawbacks]: #drawbacks

- Making a new keyword `jacobian` will almost surely break current user code.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?

The other alternative is to not have a new block and have users define `*_constrain`, `*_unconstrain`, and `*_validate` functions in the `functions` block. This might be easier to implement, but it is not as nice looking as a new constraints block.

- What is the impact of not doing this?

Users will have to write programs as they currently do, where jacobian accumulations happen directly in transformed parameters or within the model block.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Is there a better syntax for users than

```stan
vector<constraint my_constrain(args...)> X;
```

# Citations

[1] https://github.com/stan-dev/stanc3/issues/979#issuecomment-956355020
[2] https://github.com/stan-dev/stanc3/issues/979#issuecomment-932382499
