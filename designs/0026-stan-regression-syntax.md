- Feature Name: Stan Regression Syntax
- Start Date: 2020-09-21
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

The goal is to add a regression syntax to Stan similar to that offered by the high level interfaces (rstanarm and brms, and historically lm/glmer/lme4, etc.).

# Motivation
[motivation]: #motivation

Adding a regression syntax directly to Stan should make it easy to:

1. Develop high level Stan interfaces that expose regression-like syntaxes without depending on external design matrix or sparse matrix libraries

2. Express likelihood evaluations in a way that can be automatically parallelized and sent to GPUs/other accelerators

3. Manipulate design matrices directly in Stan to do things like integrate out random variables

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The basic multilevel regression syntax from rstanarm/brms/inla/lme4/etc. is written like:

```response ~ linear_model```

The response variable is the variable being modeled, the `~` indicates this expression is going to form a regression, and the `linear_model` is a representation of all the covariates, factors, and variables that go into predicting the response on the left.

Right off the bat this syntax is a little different than Stan code because there is no distribution. For instance, a normal likelihood term in Stan looks like:

```y ~ normal(mu, sigma)```

The regression model above leaves the distribution undefined, and usually the `linear_model` only defines a certain part of the model. In terms of Stan syntax this might look like:

```response ~ ?(linear_model, ?)```

where the `?` terms are undefined.

Different regression software packages make different assumptions about the choice of likelihood and link functions and how extra parameters of the model are defined. This is true too for priors, which are either inferred automatically or specified separately from the linear model.

Stan already provides a way to express priors, likelihoods, and link functions though, and so the key to a regression syntax in Stan is a mechanism to support the `linear_model` part of the regression.

## Linear Models

brms breaks down the linear part of the model into a few terms:

```linear_model = population_level_terms + group_level_terms + smooth_terms```

This proposal is going to ignore the `smooth_terms` part of the regression (not because they aren't interesting, just because it is a big enough project to work on the first two terms).

The responses in multilevel regression models are arranged into groups. That is why there are both population level terms and group level terms -- the population level terms account for the overall effects and the group level effects account for the group level variation.

A basic regression might be:
```
y ~ 1 + x + (1 | group) + (x | group)
```

The `1 + x` term are the population level effects. The `1` indicates that there should be a population level intercept in the model and the `x` term indicates a population level slope term should be fit.

The `(1 | group) + (x | group)` terms are the group level effects. The `(1 | group)` term indicates there should be a group level intercept (a different intercept term for every group) and the `(x | group)` term indicates there should be group level slopes (a different slope term for every group).

The regression implicitly defines population level intercept and slope parameters, intercept and slope parameters for each group, and any hierarhical parameters to go along with these. The implicitly defined variables is something that a Stan syntax would not have; all parameters are explicitly defined in Stan.

Though the statistical dichotomy in the problem are the two types of terms, the population level effects and the group level effects, in terms of computation, evaluating a linear model like this splits into a dense matrix vector multiply and a sparse matrix vector multiply. The population intercept and continuous population effects can be handled efficiently in a dense matrix vector multiply, and the population level factors variables and all the group level terms can be handled efficiently in a sparse matric vector multiply. This is how the linear model is formulated in the [lme4 paper](https://cran.r-project.org/web/packages/lme4/vignettes/lmer.pdf).

There are numerous other syntaxes in various regression packages in R. For instance, `(1 + x | group)` implies a correlated prior on the group level slopes and intercepts in lme4, but `(1 + x || group)` does not. `x - 1` means do not fit a population level intercept. For a syntax in Stan, where parameters must be explicitly defined, this extra syntax will not be necessary.

One thing not mentioned so far are the higher order groupings. Terms like `(x | group1:group2)` indicate that the slopes should vary according to the unique combination of `group1` and `group2` labels on each response (so a combined grouping of `group1` and `group2`). The aims of this proposal can be met with a syntax that supports the terms in the regression:

```
1 + x + (1 + x | group1) + (1 + x | group1:group2)
```

## Possible Implementation

The above syntax are already supported in Stan. `brms` and `rstanarm` already use Stan code directly. The problem is, while this syntax is fairly routine Stan code, it does not make it easy to meet the goals laid out in the beginning.

1. Interface developers are still dependent on design matrix libraries (that may differ across languages)

2. While perhaps efficient for a CPU, the code is unlikely to be efficient for a GPU or accelerator

3. The cleanest way to express the sparse matrix-vector multiply in Stan are for loops which do not make it easy to get design matrices out.

For clarity, the example model from above can be written in Stan syntax. Here is the regression model:
```
y ~ 1 + x + (1 + x | group1) + (1 + x | group1:group2)
```

Assume there are `N` responses, `G1` unique values of group 1, and `G2` values of group 2.

The data for the Stan model would look like:

```
int N; // number of responses
int G1; // number of unique members of group 1
int G2; // number of unique members of group 1
vector[N] y; // responses
vector[N] x; // covariates
int<lower=1, upper=G1> group1_idx[N]; // group 1 membership of the responses
int<lower=1, upper=G2> group2_idx[N]; // group 2 membership of the responses
```

The parameters would look like:

```
real intercept; // population level intercept
real slope; // population level slopes
vector[G1] group1_intercepts; // group 1 intercepts
vector[G1] group1_slopes; // group 1 slopes
matrix[G1, G2] group12_intercepts; // group1:group2 intercepts
matrix[G1, G2] group12_slopes; // group1:group2 slopes
```

The linear model can either be evaluated in a loop:

```
vector[N] linear_model;
for(n in 1:N) {
  linear_model[n] = intercept + slope * x[n] +
    group1_intercepts[group1_idx[n]] + group1_slopes[group1_idx[n]] * x[n] +
    group12_intercepts[group1_idx[n], group2_idx[n]] + group12_slopes[group1_idx[n], group2_idx[n]] * x[n];
}
```

or it can be written in a vectorized form:

```
vector[N] linear_model = intercept + slope * x +
    group1_intercepts[group1_idx] + group1_slopes[group1_idx] .* x +
    diagonal(group12_intercepts[group1_idx, group2_idx]) +
    diagonal(group12_slopes[group1_idx, group2_idx]) .* x;
}
```

The `diagonal(...)` terms are a very inefficient way to encode the combined groupings -- in all practical cases these would be written as single group terms by actually creating a new single group index to represent the combined `group1:group2` terms. The diagonal terms suffice for demonstration though.

There's really nothing to do more with the population intercept and slope. For everything else, a basic syntax that would be suitable for Stan would be:

```
covariate .* (parameters | group_idx)
```

where:

1. `group_idx` is the group index of the responses. It would be an integer array of length `N` in the range `[1, G]` assuming `G` groups.
2. `parameters` are the group level coefficients. It would be a length `G` vector-like variable.
3. `covariate` is an optional, length `N` vector-like set of covariates.

In the simplest case where `group_idx` is a 1d array of integers of length N, `parameters` is a vector of length `G`, and `covariate` is a length `N` vector of coefficients this would be equivalent to the Stan code here:

```
covariate .* parameters[group_idx]
```

This is not anything beyond what is already possible, but with a few variations on the syntax it can be.

First, this syntax can support multiple-group indexing. Instead of writing loops, or doing an inefficient `covariate .* diagonal(parameters[group1, group2])`, or refactoring the two groups into one, the multiple group membership could be handled by:

```
covariate .* (parameters | group1, group2)
```

where `parameters` is now a 2d variable. To get the design matrices, the `parameters` variable could be removed.

So if the following returns a length `N` vector:
```
covariate .* (parameters | group)
```

Then this would return an `N` by `G` design matrix:
```
design_matrix dmat = covariate .* (1 | group)
```

And then this design matrix could be cast to a `sparse_matrix` (once these are in Stan):
```
sparse_matrix smat = mat;
```

With the sparse matrix, the matrix vector product could be evaluated directly to get the equivalent of `covariate .* (parameters | group)`:

```
smat * parameters
```

But the design matrix could also get a `operator()` so that this was equivalent to:

```
dmat(parameters)
```

It might seem awkward to do this with call syntax, but this might be clearer for multiple group design matrices. For instance:

```
design_matrix dmat2 = (1 | group1, group2);
```

In this case `coefficients_matrix` would need compressed to a vector to make the sparse matrix vector product make sense, whereas `dmat2(coefficients_matrix)` can mean the effective matrix vector product without worrying about flattening `coefficients_matrix`. An extra function `flatten` could be provided to do this reordering if necessary.

With this syntax, the regression from above could be rewritten:
```
vector[N] mu = intercept + slope * x +
    (group1_intercepts | group1_idx) + x .* (group1_slopes | group1_idx) +
    (group12_intercepts | group1_idx, group2_idx) +
    x .* (group12_slopes | group1_idx, group2_idx);
```

All of the individual design matrix terms can be combined and evaluated at once. It should be possible to take advantage of group indices being reused in multiple terms (to avoid reading them twice).

To get the overall sparse design matrix for this expression, it would be necessary to have an equivalent of `bind_cols` for the design matrices.

```
design_matrix dmat = bind_cols((1 | group1_idx), x .* (1 | group1_idx),
                            (1 | group1_idx, group2_idx), x .* (1 | group1_idx, group2_idx));
vector[N] mu = dmat(group1_intercepts, group1_slopes, group12_intercepts, group12_slopes);
```

The equivalent sparse matrix and vector could be constructed with some extra code:
```
sparse_matrix Z = dmat;
vector[N] mu = Z * flatten(group1_intercepts, group1_slopes, group12_intercepts, group12_slopes);
```

And that's that. This is a regresion syntax for Stan that does not depend on outside design matrix libraries for Stan, can be written in a way that makes it (hopefully) possible to compile large expressions that can be passed off to accelerators, and allows design matrices, if necessary, to be extracted.

## Appendix: Multiple part regressions

It is natural to write some regressions in multiple parts. For instance, election responses might be modeled per state, with each state being in a certain region of the country. This looks like a smaller regression model feeding into a larger one:

```
vector[G] state_effect = (region_effect | region);
vector[N] mu = (state_effect | state);
```

This could be written as nested design matrix expressions:
```
vector[N] mu = ((region_effect | region) | state)
```

Or this could be broken out to make the design matrices more explicit:
```
vector[N] mu = (1 | state)((region_effect | region))
```

Taking this one step further:
```
vector[N] mu = (1 | state)((1 | region)(region_effect))
```

And then finally there is a combined design matrix:
```
design_matrix dmat = (1 | state)((1 | region));
vector[N] mu = dmat(region_effect);
```
