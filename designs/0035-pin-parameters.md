- Feature Name: pin-parameters
- Start Date: 2025-05-05
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

It is often useful to be able to 'pin' the otherwise free parameters in a statistical model to specific values. First, this is useful when debugging a statistical model to diagnose computational problems or understand the priors. Second, it is useful when one wishes to explore a simpler model that is nested inside an extended one. e.g., the mu = 0 no effect model that is nested inside the   mu != 0 model of a new effect of size mu. This proposal makes pinning straight-forward at runtime.

# Motivation
[motivation]: #motivation

At present, to pin a parameter a Stan model must be rewritten. We must either: 

- move a parameter from the parameter block to the data block, where it is pinned to a fixed value
- add convoluted logic so that a boolean (more precisely an `integer<lower=0, upper=1>`) in the data block can control whether a parameter is pinned, e.g., (from [here](https://discourse.mc-stan.org/t/fixing-parameters-in-a-model/39035/4?u=andrewfowlie))
```stan
data {
  int<lower=0, upper=1> mu_is_data;
  array[mu_is_data] real mu_data;
  ...
parameters {
  array[1 - mu_is_data] real mu_param;
  ...
transformed parameters {
  real mu = mu_is data ? mu_data[1] : mu_param[1];
  ...
```

This pattern is inelegant and unsatisfactory, as it is clunky and obfuscates the inherent generative structure of the model. 

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The following section is a draft of the docs for the new `pin` keyword-value pair in `cmdstan` command-line options that would appear [here](https://mc-stan.org/docs/cmdstan-guide/command_line_options.html). We don't at this stage make any proposal for how this feature would be propagated to other Stan interfaces, they do not anticipate any difficulties. 

## Command-Line Interface Overview

A `pin` argument is added to the command-line interface. This argument appears parallel to `init` in the configuration hierarchy and applies to all Stan interfaces.

...
- `init` - ...
- `pin` - specifies values for any parameters that should be pinned, if any
- `random` - ...
...

### Pin model parameters argument

Parameters defined in the parameters block can be 'pinned' to specific values. This is useful when debugging a model or exploring a simpler model that is nested inside an extended one.

By default, no parameters are pinned. The pinned parameters are read from an input data file in JSON format using the syntax:
```
pin=<filepath>
```
The value must be a filepath to a JSON file containing pinned values for some or all of the parameters in the parameters block. This file should be in the same JSON format as that used for other Stan files (e.g. `init`); see [here](https://mc-stan.org/docs/cmdstan-guide/json_apdx.html#creating-json-files) for more information about JSON and creating JSON files.

At present, there are two restrictions on parameters that can be pinned.
 
1. You cannot pin a subset of elements of a non-scalar parameter (e.g, `vector`, `array`, `matrix` or `tuple`); all elements must be pinned or else none must be pinned. E.g., consider
```stan
parameters {
  vector[5] x;
}
```
We can pin all 5 elements of `x` or no elements. We cannot pin, e.g., only the first element `x[1]`.
2. You cannot pin constrained parameters. E.g., consider
```stan
parameters {
  real<lower=0> x;
}
```
Because it is constrained, we cannot pin `x`.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

** to be discussed **

# Drawbacks
[drawbacks]: #drawbacks

1. It is another command-line argument and there are already several.
2. The same thing can be achieved by coding the model in a more complicated way, as shown above.
3. It changes the *interpretation* of a Stan model, though in a very explicit way.
4. The two restrictions, particularly that one cannot pin constrained parameters, will limit use cases

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives


Pinning parameters at runtime is far more elegant than existing solutions. An alternative would be a new keyword in the Stan language itself, e.g., in a parameter constraint
```stan
parameters {
  real<pin=0> mu;
}
```
or using a new annotation
```stan
parameters {
  @pin(0)
  real mu;
}
```
They could possibly be combined with the data block, e.g.,
```stan
data {
  real mu_data;
}
parameters {
  real<pin=mu_data> mu;
}
```
These possibilities are certainly neater than 
```stan
data {
  int<lower=0, upper=1> mu_is_data;
  array[mu_is_data] real mu_data;
  ...
parameters {
  array[1 - mu_is_data] real mu_param;
  ...
transformed parameters {
  real mu = mu_is data ? mu_data[1] : mu_param[1];
  ...
```
Even with `<pin=>` or `@pin`, pinning still requires one to change a model and recompile, and doesn't let us turn off pinning at runtime.

# Prior art
[prior-art]: #prior-art

`PyMC` has specific functionality for pinning. See [here](https://www.pymc.io/projects/docs/en/stable/api/model/generated/pymc.model.transform.conditioning.do.html). In `PyMC`, pinning (and perhaps other similar things) are called 'interventions'. The example given in the docs is this,
```python
import pymc as pm
import arviz as az  # added to make example code work

with pm.Model() as m:
    x = pm.Normal("x", 0, 1)
    y = pm.Normal("y", x, 1)
    z = pm.Normal("z", y + x, 1)

# Dummy posterior, same as calling `pm.sample`
idata_m = az.from_dict({rv.name: [pm.draw(rv, draws=500)] for rv in [x, y, z]})

# Replace `y` by a constant `100.0`
with pm.do(m, {y: 100.0}) as m_do:
    idata_do = pm.sample_posterior_predictive(idata_m, var_names="z")
```

# Unresolved questions
[unresolved-questions]: #unresolved-questions

I don't know how this would be implemented technically, but there is a comment [here](https://discourse.mc-stan.org/t/fixing-parameters-in-a-model/39035/7?u=andrewfowlie)
