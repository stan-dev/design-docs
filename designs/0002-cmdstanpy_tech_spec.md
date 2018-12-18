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

## Objects

### model

A model object has instance variables

+ model source file - the Stan program

A model object has methods to

+ get the full path to source file
+ get the model name
+ check existence of compiled executable
+ get the compiled model executable
+ delete the compiled executable

### data

The data object is supplied to the `sample` function which wraps calls to CmdStan.
The CmdStan sampler reads input data from a file on disk.
When this file already exists, the data object registers the file name.
When the data is in the Python environment, the data object creates a corresponding
disk file in JSON format.

A data object has instance variables

+ data file name - path to file on disk in JSON or Rdump format
+ data dict - a non-empty `dict` or `None`

The data object provides methods to:

+ register an existing data file
+ transform a Python `dict` object into a new file on disk in JSON format
+ get the data file name

_todo_:  Check that numpy arrays (stored row-major) are also serialized to JSON in row-major form.


### posterior_sample

The Pandas module will be used to manage this information.

A posterior sample object has instance variables

+ sample - a multi-dimensional pandas object:  chains X iterations X (sampler_state + model params)
+ meta-data about the arguments passed to cmdstan, number of chains, input data file, etc.
+ meta-data about the outcome

The `posterior_sample` object provides functions which can access

* all draws
* all draws for specified chain
* one draw for a specified chain and iteration number


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
                          parallel = True
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
When all chains have completed without error, the output files need to be
combined into a single output.

### extract

This function should accept a list of parameter names or the name of an individual parameter.
It should collapse the draws from multiple chains.
It returns a list tuples consisting of <parameter name, vector of draws>
where all vectors are of length = num\_chains * num\_samples

```
draws = extract(posterior_sample = None, parameter = None)
```
