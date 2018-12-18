---
output:
  html_document: default
  pdf_document: default
---

# CmdStanPy Functional Specification

CmdStanPy is a lightweight interface to Stan for Python users which
provides the necessary objects and functions to compile a Stan program
and run Stan's HMC-NUTS sampler to produce a sample from the posterior of the
model conditioned on data.

## Goals

- Clean interface to Stan services so that CmdStanPy can keep up with Stan releases.

- Provides complete control - all sampler arguments have corresponding named argument
for CmdStanPy sampler function.

- Easy to install,
  + minimal Python library dependencies: numpy, pandas
  + Python code doesn't interface directly with c++, only calls compiled executables (using package `os`).

## Design considerations

- Choices for naming and structuring objects and functions should reflect the Stan workflow.

- Data structure used for sampler output facilitates downstream analysis.

- Favor immutable objects.


## Assumptions

- Initial version will use existing CmdStan interface to compile models and run sampler
  + requires c++ compiler and `make`
  + requires composing call to compiled executable using current CmdStan syntax

- Other packages will be used to analyze the sampler output.


## Objects

### model

A model is a specification of a joint probability density in the form of a Stan program.
Models are translated to c++ by the `stanc` compiler (CmdStan `bin/stanc`).
This c++ code is compiled and linked to the Stan math library and the resulting executable
is used to sample from the posterior distribution of the model conditioned on the data.

### data

By `data` we mean just the data used to condition the model.
For a model which contains a non-empty `data` block,
CmdStan reads the data from a file on disk in either JSON or Rdump format.
In order to fit a Stan model to data in the Python environment, this data must be
assembled into a Python `dict` with entries for all data variables specified by the model
and then serialized to a file in JSON format.

### posterior_sample

The `posterior_sample` object contains _draws_ from the model conditioned on data.
A draw consists of:

- the sampler state for that iteration
  + `lp__`,
  + `accept_stat__`,
  + `stepsize__`,
  + `treedepth__`,
  + `n_leapfrog__`,
  + `divergent__`,
  + `energy__`,
- the values for all non-local variables declared in the parameters,
transformed parameters, and generated quantities blocks.

A posterior sample is only valid if the model is well-specified and
Stan's HMC sampler has converged during warmup.
To check convergence, we run the sampler multiple times, each time using
the same random seed for the random number generator and a different offset.
Each run is one _chain_.
Each chain produces one sample (set of draws).
The samples from all chains in the run have exactly the same size and shape.
The `posterior_sample` contains the mapping from chain ids to samples.
The draws are stored in iteration order.


The `posterior_sample` object provides functions which can access

* all draws
* all draws for specified chain
* one draw for a specified chain and iteration number

The samples from each chain should all have the same characteristics.
If they don't, the model has failed to converge during warmup and the
sample is invalid.
For a valid sample, all draws across all chains are used to estimate
the posterior density.

The Pandas module will be used to manage this information.

## Functions

### compile_file

Compile Stan model, returning immutable instance of a compiled model.
This is done in two steps:

* call the `stanc` compiler which translates the Stan program to c++
* call c++ to compile and link the generated c++ code

The `compile_file` function must allow the user to specify
default settings to the c++ compiler and ways to override those setting.

```
model = compile_file(path = None,
                     opt_level = 0,
                     ...)
```

##### parameters

* `path` =  - string, must be valid pathname to Stan program file
* `opt_level` = optimization level, the value of the `-o` flag for the c++ compiler
* additional flags for the c++ compiler


### sample (using HMC/NUTS)

Produce sample output using HMC/NUTS with diagonal metric: `stan::services::sample::hmc_nuts_diag_e_adapt`

```
posterior_sample = sample(model = None,
                          num_chains = 4,
                          num_cores = 1,
                          seed = None,
                          data_file = "",
                          init_param_values = "",
                          output_file = "",
                          diagnostic_file = "",
                          refresh = 100,
                          num_samples = 1000,
                          num_warmup = 1000,
                          save_warmup = False,
                          thin_samples = 1,
                          adapt_engaged = True,
                          adapt_gamma = 0.05,
                          adapt_delta = 0.65,
                          adapt_kappa = 0.75,
                          adapt_t0 = 10,
                          NUTS_max_depth = 10,
                          HMC_diag_metric = "",
                          HMC_stepsize = 1,
                          HMC_stepsize_jitter = 0)
```

The `sample` command can run chains in parallel or sequentially.
The `num_cores` argument specifies the maximum number of processes which
can be run in parallel.
When all chains have completed without error, the output files need to be
combined into a single output.

##### CmdStanPy specific parameters

* `model` - CmdStanPy model object
* `num_chains` - positive integer
* `parallel` -  True (1) False (0), default True

##### CmdStan parameters

* Random seed - CmdStan arg must be preceded by `random`
    + `seed` - random seed

* Data Inputs - CmdStan args preceded by `data`
    + `data_file` - string, 
    + `init_param_values` - string, default is empty string, must be valid pathname
to file with read permissions in Rdump or JSON format which specifies initial values for some or all parameters.

* Outputs
    + `output_file` - string value, default is empty string, must be valid pathname
    + `diagnostic_file` - string value, default is empty string, must be valid pathname
    + `refresh` - integer, the number of iterations between progress message updates.
When `refresh = -1`, the progress message is suppressed but not warning messages.

* MCMC Sampling - CmdStan args must be preceded by `sample`
    + `num_samples` Number of sampling iterations - non-negative integer, default 1000
    + `num_warmup`  Number of warmup iterations - non-negative integer, default 1000
    + `save_warmup` Stream warmup samples to output? - True (1) False (0), default False
    + `thin_samples` Period between saved samples - non-negative integer, default 1

*  Warmup Adaptation controls: CmdStan args must be preceded by `adapt`
    + `adapt_engaged` True (1) False (0), default True
    + `adapt_gamma` Adaptation regularization scale, double > 0, default 0.05
    + `adapt_delta` Adaptation target acceptance statistic, double > 0, default 0.65
    + `adapt_kappa` Adaptation relaxation exponent, double > 0, default 0.75
    + `adapt_t0` Adaptation iteration offset, double > 0, default 10

* HMC Sampler:  CmdStan arg must be preceded by `algorithm=hmc engine=nuts`
  + `NUTS_max_depth` -  Maximum tree depth, int > 0, default 10

* HMC Metric:  must be preceded by keywords `metric=diag`
  + `HMC_diag_metric` - string value, default is empty string, must be valid pathname
to file with read permissions in Rdump or JSON format which specifies precomputed Euclidian metric.
  + `HMC_stepsize` - positive double value, step size for discrete evolution, double > 0, default 1
  + `HMC_stepsize_jitter` Uniformly random jitter of the stepsize, values between 0,1, default 0


### extract

Extract a simple list of structured draws for the specified estimand, which is either
a parameter where non-local variable declared in the transformed parameter or generated quantities block.
This function should accept a list of parameter names or the name of an individual parameter.
It should collapse the draws from multiple chains.

```
draws = extract(posterior_sample = None, parameter = None)
```

Ideally, the extract function should impose the structure of the parameter on the returned elements.
For non-scalar parameters, e.g. a matrix, this requires assembling the contained elements into the correct structure.
This requires information about the type and dimensions of the container which could be parsed out
of the set of parameter names returned by the sampler.
A simpler alternative is to return the flattened set of elements as is.
