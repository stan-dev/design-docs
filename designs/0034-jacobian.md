- Feature Name: `jacobian` target
- Start Date: 01-25-2024

# Summary
[summary]: #summary

This design doc proposes adding a `jacobian` target and a new block for user defined constraints. The `jacobian` target will be accessible directly in `transformed parameters` and a new `constraints` block where users can define custom constraints similar to Stan's already existing constrained data types. The below examples shows an example use case.

```stan
constraints {
 upper_bound {
   real constrain(real x, real upper_bound) {
     jacobian += x;
     return upper_bound - exp(x);
   }
   real constrain(vector x, real upper_bound) {
     jacobian += sum(x);
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
data {
 real lb;
 real ub;
}
parameters {
 //(2) User defined constraint
 upper_bound<ub=ub> b_raw;
 real c_raw;
}
transformed parameters {
 // (3) Transform and accumulates like stan math directly
 real b = exp(b_raw) + lb;
 // Underneath the hood, only actually calculated if
 // Jacobian bool template parameter is set to true
 jacobian += b_raw;
}
```

# Motivation
[motivation]: #motivation

Given a function mapping $c$ that transforms a set of parameters from the unconstrained space $Y$ to the constrained space $X$, probability density function $\pi$, and a Jacobian determinant function over the constrained space $J(c(y))$, Stan calculates the log transformed density function [2]

$$
\pi^*(y) = \pi\left( c\left(y\right) \right) J(c\left(y\right)) 
$$

$$
\log\left(\pi^*(y)\right) = \log\left(\pi\left( c\left(y\right) \right)\right) + \log\left(J(c\left(y\right)\right)) 
$$

In a Stan program, $ \log\left(J(c\left(y\right)\right))$ is handled via the Stan languages defined constraints such as `lower`, `upper`, `ordered`, and others.
Having the Stan language define types for transforms from the unconstrained to constrained space allows users to focus on modeling in the constrained space while algorithm developers focus on developing algorithms in the unconstrained space. This is very nice for both parties since it is both of their preferred spaces to work in.

Most of the time this encapsulation is very good. The main issue is that the strong opinion forces users to write code that is either fully in the constrained space or works directly on the unconstrained space. For instance, from a comment [3] by @betanalpha (slightly commented and fleshed out)

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

So users have to choose between either leaving the nice constrained space to write your model in the unconstrained space or to restrict the models developed on constrained spaces to just the ones available with the Stan languages constrained types. The hands off or hands on approach also leaves out a growing group of Stan programmers who write code for other Stan programmers. In addition, adding a constraint to Stan involves having to touch the math library which is rather complicated. Not just by C++ itself, but the essentially small DSL we use to describe autodiff in the Stan math library.

Having a new block for user-defined constraints allows users and developers to remove some of the veil of encapsulation and write repeatable code for future models.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The following section is a draft of the docs for the new constraint and `jacobian` keyword.

## Constraint Block

### Overview

The constraints block was included in Stan 2.XX, introduced to provide users with the ability to define custom constraints on parameters, transformed parameters, and data. This block is situated immediately after the `functions` block and before the `data` block in a Stan program. The primary purpose of the `constraints` block is to allow users to define custom constraints that can be used in the same way as built-in constraints.

### Syntax

A constraints block is defined by the keyword `constraints`. Inside of the `constraints` block each constraint is its own block with a given `constraint_name` and the functions needed to define the constraint. Inside the `constraints` block, users can define one or more constraint types. Each constraint type is encapsulated within its own set of curly braces and is identified by a unique name.

Each user-defined constraint within the constraint block must specify a set of functions that define the transformation between unconstrained and constrained spaces, validate data, and increment the log of the absolute value of the determinant of the Jacobian. The general structure of a user-defined constraint is as follows:

```stan
constraints {
 constraint_name {
   // Transform from unconstrained to constrained space
   ReturnType constrain(TransformType, OtherArgs...) {
     // ... transformation logic ...
     // Increment Jacobian
     jacobian += ...;
     return ...;
   }


   // Transform from constrained to unconstrained space
   type unconstrain(TransformType, OtherArgs...) {
     // ... inverse transformation logic ...
     return ...;
   }


   // Validate data
   int validate(TransformType, OtherArgs...) {
     // ... validation logic ...
     return ...; // typically returns a boolean value
   }
 }
}
```

Each constraint type must define a set of functions that govern the transformation and validation of variables subject to the constraint. The first argument for all functions defined in a constraint must be the argument of interest to be transformed or validated. These functions include:

- `constrain(TransformType, OtherArguments...) -> ReturnType`: Transforms a real unconstrained variable to a constrained space.
- `unconstrain(TransformType, OtherArguments...) -> ReturnType`: Transforms a real constrained variable back to the unconstrained space.
- `validate(TransformType, OtherArguments...) -> ReturnType`: Validates a real variable against the constraint, returning 1 if valid and 0 otherwise.

### Using the jacobian Keyword

The `jacobian` keyword is introduced within the Constraint block to facilitate the increment of the log of the absolute determinant of the Jacobian. This keyword behaves similarly to the `target` keyword, allowing users to account for the change of variables in the probability density function. The `jacobian` keyword is available in both the `constraints` block and the `transformed parameters` block.

### Declaring Variables with User-defined Constraints

Variables can be declared with user-defined constraints in the data, transformed data, parameters, transformed parameters, and generated quantities blocks. The syntax for declaring a variable with a user-defined constraint is as follows:

```stan
type<udc=constraint_name(args...)> variable_name;
```

Here, udc denotes a user-defined constraint , and constraint_name(args...) specifies the name of the constraint along with any arguments it requires.

### Example Usage

```stan
constraints {
 upper_bound {
   real constrain(real x, real upper_bound) {
     jacobian += x;
     return upper_bound - exp(x);
   }
   real constrain(vector x, real upper_bound) {
     jacobian += sum(x);
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
data {
 real a;
 real u_bound;
 int N;
}


transformed data {
 // Data will use the validate() function from the user-defined constraint
 real<udf=upper_bound(u_bound)> a_validated;
}


parameters {
 // User-defined constraint applied to parameters alpha and b
 real<udf=upper_bound(u_bound)> alpha;
 vector<udf=upper_bound(u_bound)> b;
 // In these cases this is the same as calling
 // real<upper=u_bound> alpha;
 // vector<upper=u_bound>[N] b;
}
```

In this example, upper_bound is a user-defined constraint that is applied to the data and parameters. The validate() function from upper_bound is used to validate a_validated in the transformed data block, and the transformations defined in upper_bound are applied to alpha and b in the parameters block.

### Error Messages

If the `constrain` function of a constraint does not increment `jacobian` a warning is thrown to inform users. In these cases it is better to use a standard function as a new constraint type is most likely not necessary.

```md
Warning: {CONSTRAINT_TYPE} does not increment the log of the absolute of the determinant of the jacobian.
It is recommended to instead use a function in `transformed parameters` instead of a custom constraint.
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
vector<udc=my_constrain(args...)> X;
```

# Citations

[1] https://github.com/stan-dev/stanc3/issues/979#issuecomment-956355020
[2] https://github.com/stan-dev/stanc3/issues/979#issuecomment-932382499
