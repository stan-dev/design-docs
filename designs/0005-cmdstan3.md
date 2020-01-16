---
output:
  html_document: default
  pdf_document: default
---

# CmdStan3 Specification

CmdStan3 is a command-line interface to the Stan services layer
which provides an extensible syntax for calling Stan services
as well as model compilation.
CmdStan3 provide a utility program `stan` which takes as arguments
a set of subcommands; these subcommands map to functions
exposed by the `stan::services` package, model compilation,
and existing Stan utilities such as `stansummary`.

### Command syntax 

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
  + specify of non-default initial radius as well as parameter-specific initializiations

```
stan sample my_model metric=dense data_file=my_data.json\
            init_file=some_params.json init_radius=0.333 output_file=my_model.csv adapt_delta=0.95
```


### Mapping from subcommand to services - what granularity?


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

- defaults - nuts_hmc? do adaptation?  diag metric?
- expose static hmc?
- expose nuts unit_e??

### Design decisions

- Wrap `makefile` and current CmdStan utilities?

- Allow implicit compilation?

- Leverage existing c++ command-line parser libraries?



### References

[Posix utility argument syntax](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)



