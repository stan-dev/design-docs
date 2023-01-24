# StanCLI - C++ interface to Stan inference algorithms

## Overview

StanCLI provides command-line argument handling
for the transpiled Stan model C++ code,
allowing the user to run the resulting C++ executable
from the Unix shell or Windows terminal.
StanCLI will also anticipate the proposal for new
[Stan output formats](https://github.com/stan-dev/design-docs/blob/master/designs/0032-stan-output-formats.md),
allowing the end-user to configure which information to output and in what format.

Stan's inference engines are highly configurable.
The command line interface must allow the end user to specify
or override default behavoirs for the following:

* Inputs

  + Model data - one or more input files which fully specify the values for all Stan program data variables.

  + Initial parameter values, either a combination of exact parameter initializations
  plus random initialization according to a uniform distribution of range [-x, x],  or setting all parameters to 0.
  It should be possible to specify the value of each parameter either exactly or allow random initialization within a range.

* Outputs - per new Stan output format spec

* Runtime configuration - random seed plus stride, inference or diagnostic algorithm, and attendant agorithm-specific arguments



Argument parsing is handled by [CLI11](https://github.com/CLIUtils/CLI11),
a header-only C++ library (BSD license).
CLI11 supports common shell idioms, making it easy for the end-user to use,
and the CLI11 API is well structured, documented, and tested,
making it easy for the developer to code against.
Better command-line argument handling will simplify the
wrapper interfaces CmdStanPy, CmdStanR, et al.,
which interact with the Stan inference algorithms programmatically.

## Functional Specification

The StanCLI interface is compiled together with the transpiled Stan model C++ code
to create a model executable.
Command line arguments consist of either a flag or a keyword-value pair.

The command line argument structure is completely flat; arguments and flags can be
specified in any order, i.e., commands are not nested into subcommands.
Nested subcommands impose a partial ordering on the command line arguments.
The model development process often requires repeated runs with different configurations.
Adding order constraints to the configuration process adds overhead to an already
complicated task.
Nonetheless, in the following spec, we discuss options by grouping inputs, outputs, and config.

### Inputs

* data\_values

* param\_init\_values

* param\_init\_range

### Outputs

* output\_dir

* output\_format

* output\_types

### Runtime config

* algo

* random\_seed, random\_offset

#### Algorithm-specific config

















