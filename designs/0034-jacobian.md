- Feature Name: `jacobian` target
- Start Date: 01-25-2024

# Summary
[summary]: #summary

Adding a `jacobian` target that increments the log probablity will allow users to impliment their own constraints within stan programs. The `jacobian` target will be accessible directly in `transformed parameters` and implictly in `parameters` through `~ distribution(...)` functions. The below examples shows the main use cases. The parameter `a` is given a `normal(0, 10)` prior, `b_raw` is transformed to have a lower bound of 5, and `c_raw` uses a user defined constraint function to transform `c` to have an upper bound. 

```stan
functions {
  // User defined constrain function
  // Implicitly passed `jacobian` parameter
  real upper_bound_constrain(real x, real upper_bound) {
      jacobian += x;
      return upper_bound - exp(x);
  }
  // Must be defined for internal `write_array` function
  // Not called directly by user
  real upper_bound_unconstrain(real x, real upper_bound) {
    return log(upper_bound - x);
  }
}
data {
  real lower_bound;
  real upper_bound;
}
parameters {
  // (1) Declares a and calls 
  //  target += normal_lpdf(a, 0, 10);
  real a ~ normal(0, 10);
  // Maybe we allow this?
  real x, y, z ~ normal(0, 10);
  // Allow parameters to be passed into the prior
  real<lower=0> sigma
  real mu ~ normal(0, sigma);
  real b_raw;
  real c_raw;
}
transformed parameters {
  // (2) Transform and accumulates like stan math directly
  real b = exp(b_raw) + lower_bound;
  // Underneath the hood, only actually calculated if 
  // Jacobian bool template parameter is set to true
  jacobian += b_raw;
  // (3) jacobian implicitly passed to constrain functions
  real c = upper_bound_constrain(c_raw, upper_bound);
}
```

I think it would be nice to have at least one of these added to the language

# Motivation
[motivation]: #motivation

Since the beginning of the Stan language it was decided that users would only be permitted to increment the joint log probability `target` within the model block. This is due to partially to incapsulation concerns. Given a function mapping $c$ that tranforms a set of parameters from the unconstrained space $Y$ to the constrained space $X$, probability density function $\pi$, and a Jacobian determinant function over the constrained space $J(c(y))$, Stan calculates the transformed log transformed density function [2]

$$
\pi^*(y) = \pi\left( c\left(y\right) \right) J(c\left(y\right)) \\
\log\left(\pi^*(y)\right) = \log\left(\pi\left( c\left(y\right) \right)\right) + \log\left(J(c\left(y\right)\right)) \\
$$

Having the Stan language define types for transform from the constrain to unconstrain space allows users to focus on modeling in the constrained space while algorithm developers could focus on developing in the unconstrained space. This is very nice for both parties since it is both of their preferred spaces to work in.

However, I disagree with this pure encapsulation of the constrain space for users! I don't think it's bad, in fact 95% of the time this is very good. The main issue is that the strong opinion forces users to write code that is either fully encapsulated or works directly on the unconstrain space. For instance, from the comment [3] by @betanalpha (slightly commented and fleshed out)

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
  //  own, but the combination are well defined.
  eta ~ prob(values);     
  target += jacobian(theta); 
}
```

I think only having the all hands off approach and a set of given constrain types is kind of paradoxical! The hands off or hands on approach also leaves out a growing group of Stan programmers who write code for other Stan programmers. Right now, adding a constraint to Stan involves having to touch the math library which is rather complicated. Not just by C++ itself, but the essentially small DSL we use to describe autodiff in the Stan math library.

Sometimes users, and particularly Stan programmers, need to cook. I'd like us to be in a place between telling users, "No you are a little baby and this is a wittle baby kitchen for teeny tiny babies like you" and tossing them a propane tank, match box, and pack of cigarettes.

Having a way for users and Stan package writers to define constraints allows users to remove some of the veil of encapsulation and write repeatable code for future models.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Explain the proposal as if it was already included in the project and you were teaching it to another Stan programmer in the manual. That generally means:

- Introducing new named concepts.
- Explaining the feature largely in terms of examples.
- Explaining how Stan programmers should *think* about the feature, and how it should impact the way they use the relevant package. It should explain the impact as concretely as possible.
- If applicable, provide sample error messages, deprecation warnings, or migration guidance.
- If applicable, describe the differences between teaching this to existing Stan programmers and new Stan programmers.

For implementation-oriented RFCs (e.g. for compiler internals), this section should focus on how compiler contributors should think about the change, and give examples of its concrete impact. For policy RFCs, this section should provide an example-driven introduction to the policy, and explain its impact in concrete terms.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The first thing we would do is add `jacobian` keyword to the Stan language. Like `target`, `jacobian` would only be available on the right hand side of statements to be accumulated into. It's domain is restricted to the `transformed parameters` and `model` block as well as functions ending in `_constrain`.

This section will break the model given in the summary section to break down what the Stan compiler requires piece by piece. First, let's look at the `functions` block where we define our constrain and free functions

```stan
functions {
  // User defined constrain function
  // Implicitly passed `jacobian` parameter
  real upper_bound_constrain(real x, real upper_bound) {
      jacobian += x;
      return upper_bound - exp(x);
  }
  // Must be defined for internal `write_array` function
  // Not called directly by user
  real upper_bound_unconstrain(real x, real upper_bound) {
    return log(upper_bound - x);
  }
}
```

The Stan compiler will check that for each `{FUNCTION_NAME}_constrain` function there is an associated `{FUNCTION_NAME}_unconstrain`. The templates and signature for the `_constrain` function will be the same as a normal function except for a `bool` template parameter `Jacobian` and a templated reference argument `jacobian` to accumulate the jacobian determinant into.

```c++
template <bool Jacobian, typename T1, typename T2, typename TJacobian>
return_type_t<T1, T2> upper_bound_constrain(const T1& x, const T2& upper_bound, TJacobian& jacobian);

```

The body will be the same as any other Stan function, except that when we detect the left hand side of an accumulate statement is for the keyword `jacobian` we will wrap that jacobian accumulation in an `if (Jacobian)` statement so that it is only accumulated if requested at compile time.

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

Next is the parameters block.

While optional, I think it would be nice to have a way for users to declare priors directly in the parameters block like so
```stan
parameters {
  // (1) Declares a and calls 
  //  target += normal_lpdf(a, 0, 10);
  real a ~ normal(0, 10);
}
```

this would be translated to the equivalent of 
```
  real a;
  a ~ normal(0, 10);
```

Gelman said he would find this useful and I agree I like how it keeps everything close by. Often times I'm declaring a parameter then just giving it normal priors in the model block. This would save a bit of code and I think looks nice / makes since. Whether we want to allow `real x, y, z ~ normal(0, 10);` can be a point of discussion. Again I think it reduces reduntant code and is nice to read. Though I could also see it being abused.

Inside of transformed parameters we expose `jacobian` like in the functions section listed below. Any jacobian accumulation will be wrapped in an `if (Jacobian)`
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

```stan
parameters {
  real c_raw;
}
transformed parameters {
  // (3) jacobian implicitly passed to constrain functions
  real c = upper_bound_constrain(c_raw, upper_bound);
}
```


# Drawbacks
[drawbacks]: #drawbacks

- Making a new keyword `jacobian` will almost surely break current user code.

Why should we *not* do this?

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?
- What other designs have been considered and what is the rationale for not choosing them?
- What is the impact of not doing this?

```stan
parameters {
  // Acts like ~ function where param injected as first argument
  real<udc=lower_bound(lb)> a;
}
```

```stan
types {
  lower_bound {
    constrain(real x) {
      // ...
    }
    unconstrain(real x) {
      // ...
    }
  };
}
```

# Prior art
[prior-art]: #prior-art

Discuss prior art, both the good and the bad, in relation to this proposal.
A few examples of what this can include are:

- For language, library, tools, and compiler proposals: Does this feature exist in other programming languages and what experience have their community had?
- For community proposals: Is this done by some other community and what were their experiences with it?
- For other teams: What lessons can we learn from what other communities have done here?
- Papers: Are there any published papers or great posts that discuss this? If you have some relevant papers to refer to, this can serve as a more detailed theoretical background.

This section is intended to encourage you as an author to think about the lessons from other languages, provide readers of your RFC with a fuller picture.
If there is no prior art, that is fine - your ideas are interesting to us whether they are brand new or if it is an adaptation from other languages.

Note that while precedent set by other languages is some motivation, it does not on its own motivate an RFC.
Please also take into consideration that rust sometimes intentionally diverges from common language features.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?
- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?


# Citations

[1] https://github.com/stan-dev/stanc3/issues/979#issuecomment-956355020
[2] https://github.com/stan-dev/stanc3/issues/979#issuecomment-932382499