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

- Modular - CmdStanPy produces a sample from the posterior but other modules will do the analysis.

## Design considerations

- Choices for naming and structuring objects and functions should reflect the Stan workflow.

- Data structure used for posterior sample facilitates downstream analysis.
  + is memory efficient - avoids making copies of big data.
  + provides fast access for per-parameter, per-chain information.


## Assumptions

- Initial version will use existing CmdStan interface to compile models and run sampler
  + requires c++ compiler and `make`
  + requires composing call to compiled executable using current CmdStan syntax

- Other packages will be used to analyze the posterior sample.

## CmdStanPy API

The CmdStanPy interface is implemented as a Python package
with the following classes and functions.

## Classes

### model

A model is a specification of a joint probability density in the form of a Stan program.
Models are translated to c++ by the `stanc` compiler (CmdStan `bin/stanc`).
This c++ code is compiled and linked to the Stan math library and the resulting executable
is used to sample from the posterior distribution of the model conditioned on the data.

A instance of a model is created by calling the `compile_file` function.


### data

By `data` we mean the data used to condition the model, i.e., the values
for all variables declared in the `data` block of the Stan program.

Stan's data types are limited to primitives `int` and `real`,
container types `vector`, `row_vector`, and `matrix` which contain real values,
and n-dimensional arrays of all of the above.
Stan's `int` type corresponds to Python's `int` type,
and Stan's `real` type corresponds to Python's `float` type.
Containers and arrays correspond to numpy's `ndarray`.

For CmdStan, data is read in from a file on disk in either JSON or Rdump format.
The `data` class provides methods to assemble all of the data variable values
and serialize them to a file in the JSON format accepted by Stan's 
JSON data handler which checks that the input consists of a single
JSON object which contains a set of name-value pairs.

The key is a string corresponding to the data variable name and
the value is either a single numeric scalar value or a JSON array of
numeric values.  Arrays must be rectangular.
Empty arrays are not allowed, nor are arrays of empty arrays.
The strings "Inf" and "Infinity" are mapped to positive
infinity, the strings "-Inf" and "-Infinity" are mapped to negative
infinity, and the string "NaN" is mapped to not-a-number. Bare
versions of Infinity, -Infinity, and NaN are also allowed.

Nice function to have:  validate data against model's data block definitions.

Another nice function:  allow user to specify location of serialized JSON file
for reuse.

### sampler_runset

Each call to cmdstan to runs the HMC-NUTS sampler for a specified number of iterations.
In order to check that the model is well-specified and the sampler has
converged during warmup we run the sampler multiple times, each time using
the same random seed for the random number generator and a different offset.
Each run is one _chain_ and the set of draws for that chain is one _sample_.

The `sampler_runset` object records all information about the set of runs:

- cmdstan arguments
- number of chains
- per-chain output file name


### posterior_sample

The `posterior_sample` object combines all outputs from a `sampler_runset`
into a single object.
The Pandas module is used to manage this information in a memory-efficient fashion.

The `posterior_sample` object contains _draws_ from the model conditioned on data.
A draw is a vector of values and a set of labels for each index consisting of:

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
  + values for scalar variables are labeled by the variable name, e.g. `theta`
  + values for container variables are a labeled by variable name plus index, e.g. `theta[2,1,2]`

A posterior sample is only valid if the model is well-specified and
Stan's HMC sampler has converged during warmup.
The samples from all chains in a set of runs must be the same size and shape.
If they aren't, the model has failed to converge during warmup and the sample is invalid.

The `posterior_sample` provides methods which report
per-chain draws, sampler settings, and warning messages:

- `get_num_chains`
- `get_draws`
- `get_warnings`
- `get_step_size`
- `get_metric`
- `get_timing`
- `get_stan_version`


A  `posterior_sample` object contains all draws from all chains as a pandas dataframe.
For a valid sample, all draws across all chains are used to estimate the posterior density.
This analysis will be done by downstream modules, therefore
this information is organized for optimal memory locality:

- each row contains all values for one vector label
- column indices are <chain, iteration>.

This requires transposing the information in the cmdstan csv output files where
each file corresponds to the chain, each row of output corresponds to the iteration,
and each column corresponds to a particular label.


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
                     opt_level = 3,
                     ...)
```

#### parameters

* `path` =  - string, must be valid pathname to Stan program file
* `opt_level` = optimization level, the value of the `-o` flag for the c++ compiler, default value is `3`
* additional flags for the c++ compiler


### sample (using HMC/NUTS)

Condition the model on the data using HMC/NUTS with diagonal metric: `stan::services::sample::hmc_nuts_diag_e_adapt`
to produce a posterior sample.

```
sample_runset = sample(model = None,
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
                       nuts_max_depth = 10,
                       hmc_diag_metric = "",
                       hmc_stepsize = 1,
                       hmc_stepsize_jitter = 0)
```

The `sample` command can run chains in parallel or sequentially.
The `num_cores` argument specifies the maximum number of processes which
can be run in parallel.
When all chains have completed, the output files are combined into a 
single `posterior_sample` object.

#### CmdStanPy specific parameters

* `model` - CmdStanPy model object
* `num_chains` - positive integer
* `num_cores` -  positive integer

#### CmdStan parameters

The named arguments must be translated into a valid call to the cmdstan sampler.
This requires assembling the arguments into a specific order and adding additional
cmdstan arguments.

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

_note: cmdstan uses uppercase `NUTS` and `HMC` in argument names, but lowercase `algorithm=hmc engine=nuts`_

### summary

Calls cmdstan's `summary` executable passing in the names of the per-chain output files
stored in the `sampler_runset` object.
Prints output to console or file

```
summary(runset = `sampler_runset`, output_file= "filename")
```


### diagnose

Calls cmdstan's `diagnose` executable passing in the names of the per-chain output files
stored in the `sampler_runset` object.
If there are no diagnostic messages, prints message that no problems were found.

Prints output to console or file

```
diagnose(runset = `sampler_runset`, output_file= "filename")
```

