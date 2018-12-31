---
output:
  pdf_document: default
  html_document: default
---

# CmdStanPy Technical Specification

This is the technical specification for the initial version of CmdStanPy.

* This version will wrap the existing CmdStan (current version is 2.18),
therefore calls to the CmdStan executables must have the appropriate
arguments in the appropriate order.

* Model compilation will be delegated to `make` (Gnu make).


## Classes

### model class

Each call to the `compile_file` function returns a `model` instance.

Instance variables:

+ model source file - the Stan program


Methods:

+ get the full path to source file
+ get the model name
+ check existence of compiled executable
+ get the compiled model executable
+ delete the compiled executable

### data class

The data object is supplied to the `sample` function which wraps calls to CmdStan.
The CmdStan sampler reads input data from a file on disk.
When this file already exists, the data object registers the file name.
When the data is in the Python environment, the data object creates a corresponding
disk file in JSON format.

A data object has instance variables

- data file name - path to file on disk in JSON or Rdump format
- data dict - a non-empty `dict` or `None`

The data object provides methods to:

- register an existing data file
- get the data file name
- add the values corresponding to a named data variable to the Python `dict` object
- transform a Python `dict` object into a new file on disk in JSON format
  + optionally specify location of serialized JSON file - facilitates reuse of data
  + if no location specified, use tmp file

Python's `json` module will be used to serialize python dictionaries to JSON strings.

The following is the set of Stan data types and the corresponding Python data structure:

|Stan | Python | note |
|-----|--------|------|
| int | int |  Stan uses 32-bit integer, max 2^^31, min -2^^31|
| real | float |  Stan uses 64-bit floating point |
| vector | 1-d array of float  |
| row_vector | 1-d array of float | |
| matrix | 2-d array of float | stored row-major order |

Stan allows multi-dimensional arrays of all of these types.
These correspond to numpy ndarrays of float which must be "jsonified"
before serialization - cf https://stackoverflow.com/questions/26646362/numpy-array-is-not-json-serializable


### sampler_runset

A `sample_runset` object records the arguments used to run the sampler
and the names of the resulting CmdStan output csv files .

Successful calls to the `sample` function return a `sampler_runset` instance.
Instance variables:

- cmstan call
- number of chains
- per-chain output file name


### posterior_sample

A `posterior_sample` instance is instantiated via a 1-arg constructor function
with takes as input a `sampler_runset`.

A  `posterior_sample` object contains all draws from all chains as a pandas dataframe.
The set of draws from all chains is organized for optimal memory locality for downstream processing
Each draw is a vector of int and float values and the axes of that vector are the labels, either sampler state or parameter value names.

- each row contains all values for one vector label
- column indices are <chain, iteration>.

This requires transposing the information in the CmdStan csv output files where
each file corresponds to the chain, each row of output corresponds to the iteration,
and each column corresponds to a particular label.

_It is critical that this be implemented in a memory-efficient manner, i.e.,
avoid creating copies of the ndarray for the sample._

Instance variables

+ sample - a multi-dimensional pandas object:  chains X iterations X (sampler_state + model params)
+ sampler_runset - copy of `sampler_runset` from constructor
+ per-chain sampler information

The `posterior_sample` object provides functions which can access

- the sample - all labels, all chains, all iterations
- all draws for a specified label
- all draws for a specified label, specified chain
- all draws for specified chain
- one draw for a specified chain and iteration number

The `posterior_sample` provides methods which report
per-chain draws, sampler settings, and warning messages:

- `get_num_chains`
- `get_num_draws`
- `get_warnings`
- `get_step_size`
- `get_metric`
- `get_timing`
- `get_stan_version`


## Functions

### compile_file

For the initial version, use CmdStan's `makefile` for program `Gnu make`.
The makefile has rules which compile and link an executable program `my_model`
from Stan program file `my_model.stan` in two steps:

* call the `stanc` compiler which translates the Stan program to c++
* call c++ to compile and link the generated c++ code

```
model = compile_file(path = None,
                     opt_level = 0,
                     ...)
```
##### makefile variables

The files `github/stan-dev/cmdstan/makefile` and `github/stan-dev/cmdstan/make/program`
contain the rules used to compile and link the program.
The CmdStan makefile rule for compiling the Stan program to c++ is
in file `github/stan-dev/cmdstan/make/program`, line 30:
```
@echo '--- Translating Stan model to c++ code ---'
$(WINE) bin/stanc$(EXE) $(STANCFLAGS) --o=$@ $<
```
The CmdStan makefile rule for creating the executable from the
compiled c++ model is in file `github/stan-dev/cmdstan/make/program`, line 37:
```
$(LINK.cpp) $(CXXFLAGS_PROGRAM) -include $< $(CMDSTAN_MAIN) $(LDLIBS) $(LIBSUNDIALS) $(MPI_TARGETS) $(OUTPUT_OPTION)
```
where the `$(LINK.cpp)` is a rule which contains more make variables:
```
$(CXX) $(CXXFLAGS) $(CPPFLAGS) $(LDFLAGS) $(TARGET_ARCH)
```

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

The `sample` command can run chains in parallel and/or sequentially.
The `num_cores` argument specifies the maximum number of processes which
can be run in parallel.
When all chains have completed without error, the output files need to be
combined into a single output.

Python's multiprocessing module will be used to run all chains.

+ [python 3](https://docs.python.org/3/library/multiprocessing.html)
+ [python 2](https://docs.python.org/2.7/library/multiprocessing.html)

### summary

```
summary(runset = `sampler_runset`, output_file= "filename")
```

### diagnose

```
diagnose(runset = `sampler_runset`, output_file= "filename")
```

## Repository Structure

The repository structure reflects the project's architecture.
We will follow the recommendations here:
 https://docs.python-guide.org/writing/structure/

The CmdStanPy repo will have one file per class.
File `cmdstanpy.py` will have definitions for all user-facing functions.
Additional files may be necessary, following Python best practices.


