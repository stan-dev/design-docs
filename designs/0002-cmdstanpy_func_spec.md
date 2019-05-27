---
output:
  html_document: default
  pdf_document: default
---

# CmdStanPy Functional Specification

CmdStanPy is a lightweight interface to Stan for Python users which
provides the necessary objects and functions to compile a Stan program
and run either:
 - the HMC-NUTS sampler to produce a sample from the posterior of the model conditioned on data
 - the LBFGS optimizer
 - VI

The CmdStan interface is file-based:

* Stan programs are compiled to c++ executibles
* The c++ executible operates on input files and produces output files.

Using CmdStanPy, in-memory Python objects can be used as data inputs,
and the sampler output can be assembled into an in-memory data structure which
can be used in downstream analysis.


## Goals

- Clean interface to Stan services so that CmdStanPy can keep up with Stan releases.

- Provides complete control - all CmdStan command options have corresponding named argument in CmdStanPy.

- Easy to install,
  + minimal Python library dependencies: numpy
  + Python code doesn't interface directly with c++, only calls compiled executables (using package `os`).

- Modular - CmdStanPy produces a sample from the posterior but other modules will do the analysis.


## Design considerations

- Choices for naming and structuring objects and functions should reflect the Stan workflow.

- Data structure used for posterior sample facilitates downstream analysis.
  + is memory efficient - avoids making copies of big data.
  + provides fast access for per-parameter, per-chain information.

- Should this be Python2/Python3 agnostic?  After investigation, answer is no, use Python3
  + all existing downstream modules are written for Python3 
  + Python3 code is cleaner

- how to specify configuration choices:
  + path to CmdStan installation
  + path to tmpfiles vs. in-memory tmpfiles


## Assumptions

- Initial version will use existing CmdStan interface to compile models and run sampler
  + requires c++ compiler and `make`
  + requires composing call to compiled executable using current CmdStan syntax

- Other packages will be used to analyze the posterior sample.


## Workflow

* Specify Stan model - function `compile_model`
  + takes as input a Stan program and produces the corresponding c++ executable.
  + both Stan program and c++ executable exist as on-disk files

* Assemble input data in the form of either:
  + a Python `dict` object consisting of key-value pairs where the key corresponds
 to Stan data variables and the value is of the correct type and shape.
  + an existing data file on disk in either JSON or Rdump format.

* Run sampler - function `sample`
  + invokes Stan's NUTS-HMC sampler to condition model on input data, produces output csv files
  + runs any number of chains - should run at least 2, default 4
  + lightweight object `RunSet` keeps track of sampler arguments, per-chain outcome, output files
  + returns `PosteriorSample` object which contains information about sample

* `PosteriorSample` object contains names of csv output files
  + attribute `sample` assembles in-memory sample from csv files
  + methods `summary` and `diagnose` invoke CmdStan tools `bin/stansummary` and `bin/diagnose` respectively


## CmdStanPy API

The CmdStanPy interface is implemented as a Python package
with the following functions and classes.

## Functions

### compile_model

Compile Stan model, returning immutable instance of a compiled model.
This is done in two steps:

* call the `stanc` compiler which translates the Stan program to c++
* call c++ to compile and link the generated c++ code

The `compile_file` function must allow the user to specify
default settings to the c++ compiler and ways to override those setting.

```
model = compile_file(path = None,
                     optimization_flag = 3,
                     ...)
```

In case of compilation failure, this function returns `None`
and the `compile_file` function reports the compiler error messages.


#### parameters

* `path` =  - string, must be valid pathname to Stan program file
* `optimization_flag` = optimization level, the value of the `-o` flag for the c++ compiler, default value is `3`
* additional flags for the c++ compiler


### sample (using HMC/NUTS)

Condition the model on the data using HMC/NUTS with diagonal metric: `stan::services::sample::hmc_nuts_diag_e_adapt`
and run one or more chains, producing a set of samples from the posterior.
Returns a `PosteriorSample` object which contains information on all runs for all chains.

```
RunSet = sample(model,
                chains = 4,
                cores = 1,
                seed = None,
                data_file = None,
                init_param_values = None,
                csv_output_file = None,
                console_output_file = None,
                refresh = None,
                post_warmup_draws_per_chain = None,
                warmup_draws_per_chain = None,
                save_warmup = False,
                thin = None,
                do_adaptation = True,
                adapt_gamma = None,
                adapt_delta = None,
                adapt_kappa = None,
                adapt_t0 = None,
                nuts_max_depth = None,
                hmc_metric_file = None,
                hmc_stepsize = None)
```

The `sample` command runs one or more sampler chains (argument `num_chains`), in parallel or sequentially.
The `num_cores` argument specifies the maximum number of processes which can be run in parallel.

#### parameters
The `model` parameter is required.  If the model has data inputs, the input data parameter must be specified as well.

* `model` - required - CmdStanPy model object
* `num_chains` - positive integer, default 4
* `num_cores` -  positive integer, default 1
* `seed` - integer - random seed
* `data_file` - string - full pathname of input data file in JSON or Rdump format
* `init_param_values` - string - full pathname of file of initial values for some or all parameters in JSON or Rdump format
* `csv_output_file` - string - full pathname of the sampler output file, in stan-csv format, , each chain's output is written to its own file '<csv-output>-<chain_id>.csv'
* `console_output_file` - string - full pathname of file of sampler messages to stdout and/or stderr, each chain's output is written to its own file '<console-output>-<chain_id>.txt'
* `refresh` - integer - the number of iterations between progress message updates.  When `refresh = -1`, the progress message is suppressed but not warning messages.
* `post_warmup_draws_per_chain` non-negative integer - number of post-warmup draws for each chain
* `warmup_draws_per_chain`  non-negative integer - number of warmup draws for each chain
* `save_warmup` - boolean, default False - whether or not warmup draws are written to output file
* `thin` - non-negative integer - period between saved draws
* `nuts_max_treedepth` - integer - NUTS maximum tree depth
* `do_adaptation` - boolean, default True - whether or not NUTS algorithm updates sampler stepsize and metric during warmup, True implies num warmup draws > 0
* `adapt_gamma` - non-negative double - adaptation regularization scale,
* `adapt_delta` - non-negative double - adaptation target acceptance statistic
* `adapt_kappa` - non-negative double - adaptation relaxation exponent
* `adapt_t0` non-negative integer - adaptation iteration offset
* `hmc_metric_file` - string - full pathname of file containing precomputed diagonal Euclidian metric in JSON or Rdump format
* `hmc_stepsize` - positive double value -  step size for discrete evolution

These arguments must be translated into a valid call to the CmdStan sampler.
This requires assembling the arguments into a specific order and adding additional
CmdStan arguments.

### summary

Calls CmdStan's `summary` executable passing in the names of the per-chain output files
stored in the `RunSet` object.
Prints output to console or file

```
summary(runset = `sampler_runset`, output_file= "filename")
```

### diagnose

Calls CmdStan's `diagnose` executable passing in the names of the per-chain output files
stored in the `RunSet` object.
If there are no diagnostic messages, prints message that no problems were found.

Prints output to console or file

```
diagnose(runset = `sampler_runset`, output_file= "filename")
```


## Classes

### Model

A model is a specification of a joint probability density in the form of a Stan program.
Models are translated to c++ by the `stanc` compiler (CmdStan `bin/stanc`).
This c++ code is compiled and linked to the Stan math library and the resulting executable
is used to sample from the posterior distribution of the model conditioned on the data.

A instance of a Model is created by calling the `compile_file` function.


### StanData

A `StanData` object contains
the data used to condition the model, i.e., the values
for all variables declared in the `data` block of the Stan program.
The same data format is used for user-supplied initializations
for the HMC/NUTS sampler.

Stan's data types are limited to primitives `int` and `real`,
container types `vector`, `row_vector`, and `matrix` which contain real values,
and n-dimensional arrays of all of the above.
Stan's `int` type corresponds to Python's `int` type,
and Stan's `real` type corresponds to Python's `float` type.
Containers and arrays correspond to numpy's `ndarray`.

The `StanData` class provides methods to assemble all of the data variable values
and serialize them to a file in a format accepted by CmdStan

 - `rdump` (CmdStan 2.18) 
 -  JSON (CmdStan 2.19).

CmdStan 2.18 input data must be in Rdump format.
As of the next release (2.19),  CmdStan also accepts JSON format.

JSON input must be a single JSON object which contains a set of name-value pairs
where the name corresponds to the Stan data variable name
and the value is either a single numeric value or an array of numeric values.
Arrays must be rectangular.
Empty arrays are not allowed, nor are arrays of empty arrays.
The strings "Inf" and "Infinity" are mapped to positive
infinity, the strings "-Inf" and "-Infinity" are mapped to negative
infinity, and the string "NaN" is mapped to not-a-number. Bare
versions of Infinity, -Infinity, and NaN are also allowed.

Functions for future versions:

+ validate data against model's data block definitions


### PosteriorSample

The `PosteriorSample` object combines all outputs from a `RunSet` into a single object.
The numpy module is used to manage this information in a memory-efficient fashion.

The `PosteriorSample` object 
Stan's HMC NUTS sampler produces a set of _draws_ from the model conditioned on data.
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

The `PosteriorSample` provides methods to access the sample draws:

- `get_parameter`
- `get_sampler_state`
- `get_draw`

It also provides methods which report
per-chain draws, sampler settings, and warning messages:

- `get_num_chains`
- `get_num_draws`
- `get_warnings`
- `get_step_size`
- `get_metric`
- `get_timing`
- `get_stan_version`



### RunSet

Each call to CmdStan to runs the HMC-NUTS sampler for a specified number of iterations.
In order to check that the model is well-specified and the sampler has
converged during warmup we run the sampler multiple times, each time using
the same random seed for the random number generator and a different offset.
Each run is one _chain_ and the set of draws for that chain is one _sample_.

The `RunSet` object records all information about the set of runs:

- number of chains
- per-chain call to CmdStan
- per-chain output file name
- per-chain transcript of output to stdout and stderr
- per-chain return code
