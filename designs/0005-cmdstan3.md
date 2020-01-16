---
output:
  html_document: default
  pdf_document: default
---

- *Feature Name:* CmdStan3
- *Start Date:* 2020-01-16
- *RFC PR(S):*
- *Stan-dev Issue(s):*

# CmdStan3 Summary
[summary]: #summary

CmdStan3 is a command-line interface to the Stan services layer
which provides an extensible syntax for calling Stan services
as well as model compilation.
CmdStan3 provides a utility program `stan` which takes as arguments
a set of subcommands; these subcommands map to functions
exposed by the `stan::services` package, model compilation,
and existing Stan utilities such as `stansummary`.


# Motivation
[motivation]: #motivation

1. Unify all workflow operations: single utility for model compilation, fitting, and diagnostic operations.

2. Usability: flat command syntax which allows configuration arguments to be specified in any order

3. Extensibility: easy to add new commands corresponding to new services and to modify argument structure for existing commands.

# Guide-level explanation: Command Syntax
[guide-level-explanation]: #guide-level-explanation


The first argument to the `stan` utility is either

- `-h` or `--help` for help
- `-v` or `--version` for CmdStan3 version information
- a subcommand

Subcommand arguments are then followed by either

- `-h` or `--help` for subcommand-specific help
- a Stan model name

For subcommands which call a Stan service,
the remaining command line arguments consist of an
unordered set of pairs of the form `<name>=<value>`
which are parsed and validated by the `stan` utility
and then passed in to the services method.

Possible exceptions to this subcommand syntax are:

- The `compile` subcommand, which would instead take a series of makefile options.
- Utilities such as `stansummary` which operate on one or more files but don't need a compiled model.


### Examples

- Print top-level help:
```
stan -h
```

- Print subcommand help:
```
stan optimize -h
```

- Compile a Stan program `my_model.stan` using CmdStan makefile _from any directory_:

```
stan compile my_model
stan compile path/to/my_model
stan compile path/to/my_model -makeflag1=value1 ... -makeflagN=valueN
```


- Fit a Stan program to data
  + specify input, output, and sampling arguments in any order
  + specify of non-default initial radius as well as parameter-specific initializations

```
stan sample my_model metric=dense data_file=my_data.json\
            init_file=some_params.json init_radius=0.333 output_file=my_model.csv adapt_delta=0.95
```


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

### Interaction with other features:

- CmdStan3 makes calls to GnuMake and therefore will spawn a process on the underlying OS; must be robust to path and filenames
- CmdStan3 wraps the Stan services layer 

### Implementation

The processing steps:

- Parse command inputs - requires ad-hoc parser for above syntax - if possible, leverage existing c++ command line options parsers.
- Validate command configuration (as needed)
- Validate file paths, formats, contents
- Call `stan::services` method (or `make`)
- Report results

#### Decisions

For models with parameters, there are 3 choices of metric, { unit, diag, dense }, a {yes/no} choice for adaptation, and two kinds of hmc, {nuts, static} for a total of 12 functions:

```
services::sample::hmc_nuts_dense_e()
services::sample::hmc_nuts_dense_e_adapt()
services::sample::hmc_nuts_diag_e()
services::sample::hmc_nuts_diag_e_adapt()
services::sample::hmc_nuts_unit_e()
services::sample::hmc_nuts_unit_e_adapt()
services::sample::hmc_static_dense_e()
services::sample::hmc_static_dense_e_adapt()
services::sample::hmc_static_diag_e()
services::sample::hmc_static_diag_e_adapt()
services::sample::hmc_static_unit_e()
services::sample::hmc_static_unit_e_adapt()
```

- Mapping from subcommand to services - what granularity?<br>
 + defaults - nuts\_hmc? do adaptation?  diag metric?
 + expose static hmc? expose nuts unit\_e??

- Allow implicit Stan program compilation?


# Drawbacks
[drawbacks]: #drawbacks

- Introducing yet another interface increases maintenance burden, as long as both CmdStan and CmdStan3 are supported.

- The choice of argument names is always contentious; this proposal opens the door for more long bike-shed discussions.  It doesn't matter what the argument names are; what matters is that this interface exposes the full set of controls available from the services layer.

# Rationale
[rationale]: #rationale

- Usability
  + The syntax proposed here is familiar to command-line users; it removes the order dependencies introduced by the current CmdStan argument parser.
  + A flat syntax is easy to understand; a hierarchical organization requires learning both argument names and names of organizing concepts.  Knowledgeable Stan users find CmdStan impossible to use because they cannot get the command line syntax right and the error messages that result are often misleading. cf [issue #642](https://github.com/stan-dev/cmdstan/issues/642), for example.
  + The argument hierarchy in current CmdStan was drawn up 5 years ago; since then certain features have been removed, e.g., choice of RNG engine, resulting in a hierarchy mis-matched to the current feature set.


- Maintainability
  + The current CmdStan argument parser is difficult to maintain; cf [bugfix #695](https://github.com/stan-dev/cmdstan/pull/695) which was a relatively simple code change - less than 1 day programmer effort, however the argument test framework was buggy, and demonstrating the correctness of this fix to the satisfaction of the reviewer required an additional 2 weeks of effort.
  + Use of a standard options parsing library allows Stan developers and maintainers to get answers and support from online documentation and discussions.


### References

[Posix utility argument syntax](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)



