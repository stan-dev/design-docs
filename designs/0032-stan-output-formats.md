- Feature Name: stan-output-formats
- Start Date: 2022-01-11
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

In order to monitor the progress of CmdStan's inference algorithms,
the outputs from CmdStan must be available to downstream readers on a streaming basis.
This design provides an alternative to the [Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html)
for outputs of the Stan inference algorithms which are exposed by the `stan::services` layer.


# Motivation
[motivation]: #motivation

The [Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html) contains a record
of the inference algorithm outputs.  This is the output format used by CmdStan, and therefore by the
CmdStan wrapper interfaces CmdStanPy and CmdStanR  This format is limited and limiting for several reasons.

* While the plain-text format is human readable, the drawbacks are that conversion to/from binary
is expensive and may lose precision, unless default settings are overridden, which in turn will
result in large output file size.  The plain text format is untyped, therefore we cannot distinguish
between integer, real, or complex numbers.

* The HMC sampler uses comment rows following the header row to report the stepsize, metric type, and metric
and a final set of comment rows to report sampler timing information.
This requires writing ad-hoc parsers to recover this information and precludes the use of many fast CSV parser libraries.

* The Stan CSV file use a single table to hold both the inference algorithm state as well as
the model outputs produced by the model class's `write_array`.
By convention, the initial columns contain inference algorithm state.
Depending on the kind of inference there will be zero or more such columns whose names end in `__`, e.g. `lp__`.

* Because each row of the CSV file corresponds to one draw, there is no way to monitor the inner workings
of the inference algorithm, e.g., leapfrog steps or gradient trajectories.

* Although we can now run multiple chains in a single process, it is still necessary to produce per-chain CSV files,
with the chain id baked into the filename.   A cleaner solution would be to combine all outputs in a single file.

To overcome these problems, we need to add new output mechanisms to core Stan.
For models which require extended processing we need to be able to monitor progress of both
the resulting inferences and the internals of the inference algorithm.
Examples of the former as the per-draw state of the joint model log probability ("lp__")
as well as individual model variables.
Examples of the latter are the algorithm state at each step of an interactive process.
For downstream analysis we need to evaluate the goodness of fit  (R-hat, ESS, etc),
and compute statistics for all model parameters and quantities of interest.

For backwards compatibility, we will maintain the current CmdStan Stan CSV output file format, as is.
We propose to develop additional output handlers which produce multiple output streams,
each reporting on one facet of the model-data-inference process.
Given a designated directory, the output handler will create appropriately named output files in this directory.
These streams will be in known, standard formats, allowing for easier downstream processing.


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

For a given run of an inference algorithm given a model and data,
the outputs of interest can be categorized in terms of information source and content
and information structure.

The structure of these outputs can be best represented either as table or as a nested list.
There are three sources of information:  the Stan model, the inference algorithm, and the inference run.

**The Stan model**. The Stan services layer helper methods call the Stan model class
[``stan::model::model_base``](https://github.com/stan-dev/stan/blob/develop/src/stan/model/model_base.hpp).

  + `log_prob` provides access to the model parameters and transformed parameters on the unconstrained scale.
  + `write_array` provides access to parameters, transformed parameters, and generated quantities on the constrained scale.
  + `transform_inits` can be used to transform parameters from the constrained to the unconstrained scale.
  + a number of methods provide meta-information about the model:  `model_name`, `(un)constrained_param_names`, `get_dims`.

**The Inference algorithm**.  Currently, the inference engine outputs are flattened into per-iteration reports, starting with `lp__`
and comment blocks are used to report global information, e.g., stepsize and metric for NUTS-HMC and stepsize for ADVI.
However for complex methods we wish to report on iterative or multi-stage algorithms, e.g., for the NUTS-HMC sampler,
successive leapfrog steps.  Therefore we need to decouple the outputs from the inference engine from the outputs from the model.

**The inference run**.  When CmdStan is used to do inference,
it uses the initial set of the comments in the Stan CSV file to record the complete set of configuration options
and the final block of comments to record timing information.
Not recorded explicitly are the chain and iteration information, when running multiple chains,
or timestamp information for processing events.

For example, if we use the CmdStan interface to run the sampler for a single chain
by default the output is written to a file `output.csv` and if we use the new `num_chains` argument,
e.g., `num_chains=4` the output is a set of files `output_1.csv`, ..., `output_4.csv`.
Under this proposal, we would factor the information `output.csv` as follows:

- Structured non-tabular data (nested dictionaries and or/lists) would be output as JSON:

  + `model_metatdata.json` - information on model variable names, types, dimensions, and block 
  + `sampler_metatdata.json` - information on the configuration of the sampler
  + `hmc_parameters.json` - information on the stepsize, metric type, and metric.

- Tabular data would be output either as CSV file format or Apache Arrow binary format:

 + `model_sample` - draws from the sampler on the constrained scale
 + `model_params_unconstrained` - draws on the unconstrained scale (parameter and transformed parameters only)
 + `log_prob` - the value of `lp__`
 + `sampler_state` - outputs from the sampler
 + `sampler_events` - timestamp plus string descriptor


## Current implementation

A CSV file is designed to hold a single table's worth of data in plain text where
each row of the file contains one row of table data, and all rows have the same number of fields.
The CSV format is not precisely defined.  Common usage allows
allows the first row of data to be treated as a row of column labels
(the "header row"), and also allows comment rows which start with a designated comment prefix character.
Because the initial focus of the project was MCMC sampling, the CSV file allowed for a
straightforward representation of the posterior sample one row per draw,
one column per output from the Stan program.
Over time, the Stan CSV file has come to be an amalgam of information about the inference engine configuration,
the algorithm state, and the algorithm outputs.

### Output mechanism:  callback writers

Outputs are handled by objects of base class `stan::callbacks::writer`
which is constructed from an output stream.
Through function call operator overloading, the writer
can handle the following data structures:

+ a vector of strings (names), used for CSV header row
+ a vector of doubles (data), used for (part of) the data row
+ a string (message), used for CSV comments
+ nothing - blank input

The inference methods wrapped by the Stan serv methods on the Stan services layer 

The Stan services layer provides a set of utility classes which manage one or more streams;
these are 



When the user sends a request to the interface to do some kind of inference given a model and data,
the interfaces first instantiate the Stan model object and the writer callbacks,
then pass these in to `stan::services` functions which invoke the appropriate algorithm.
The use of writer callbacks keeps the inference algorithms output-format agnostic.



The current `stan::services` layer utilities are completely Stan CSV format-centric and will need to be refactored.


### Stan program outputs

The Stan model class `write_array` method returns a vector of doubles for all
parameter, transformed parameter, and generated quantities (non-local) variables,
in order of declaration in the Stan program.

The model class methods `constrained_param_names`, `unconstrained_param_names`, `get_constrained_sizedtypes`, `get_unconstrained_sizedtypes`
provide name, type, and shape information.
The reason that the model reports on both the constrained and unconstrained parameters is the Stan parameter types
simplex, correlation, covariance, and Cholesky factors have different shapes on the constrained, unconstrained scale.
For example, a simplex parameter is a vector whose elements sum to one on the constrained scale which means that it has $N-1$ free parameters
when computing on the unconstrained scale.
The Stan model parameter inputs and outputs are on the *constrained* scale, therefore the number of parameter values reported by the `write_array` method
is reported by the `get_constrained_sizedtypes` method.
The sampler computes on the *unconstrained* scale, therefore the size of the metric (inverse mass matrix) is reported by the `get_unconstrained_sizedtypes` method.
(Note: A further complication for optimization is that the optimization algorithm computes on the unconstrained scale, which means that the Hessian of the covariance matrix is on the unconstrained scale.)


### Inference algorithm outputs

The outputs from the inference algorithm necessarily differ according to the method, and to a lesser degree, according to the developers.
The NUTS-HMC sampler does full Bayesian inference by assembling a set of draws from the posterior distribution using an HMC sampler
with tuning parameters step-size and metric.
The `stan::services::util::mcmc_writer` class is constructed with a callback writer and provides methods
`write_sample_names`, `write_sample_params`, `write_adapt_finish`, `write_timing`.

- The `write_sample_names` and `write_sample_params` produce the CSV header row and data rows, respectively.
The initial columns consist of sampler state and diagnostic information from the `stan::mcmc::sample` object,
(called `sample_params`), the remaining columns are the Stan model variable names and values returned by
the `constrained_param_names` and `write_array` methods.

- The `write_adapt_finish` and `write_timing` produce comment blocks in the CSV file.
Adaptation information consists of the stepsize and metric.  This comment block follows
the CSV header row, either immediately, or following the warmup data rows.
The timing information comments are written out at the end.


### Interface-level outputs

The CmdStan interface dumps all configuration information into the Stan CSV file as a series of initial comment lines.
The CmdStan argument parser uses indentation to indicate nested argument structure.
Following the argument parser are several more comment lines of key-value pairs of information
about the software version and compiler options used to compile the Stan model executable.


## Functional specification

We propose to break down the information in the current Stan CSV file into several files
according to information source, whose format matches the information structure of the contents.
The default file format for tabular data will be CSV.
The default file format for hierarchical data will be JSON.

Tabular data:

- The Stan model variables,
i.e., the `constrained_param_names` method generates the output column names
and the `write_array` method generates the output data.

- The inference method variables (`sampler_params` for HMC, tbd for optimization, variational inference).

- The HMC metric (?).  The HMC metric is either a matrix diagonal vector or a dense matrix.
It is a dense, symmetric positive definite matrix.
The sampler algorithms allow the user to specify the initial mass matrix (in JSON or rdump formats).

- The HMC stepsize is a scalar.  It can trivially be output in CSV or JSON format.


Hierarchical data:

- Stan model variables schema: block, name, type, shape, size, output column name(s)

- Information about the inference engine run:  all information currently jammed into the Stan CSV file header
and the closing timing comments.

The user interfaces will manage creating and naming the suite of output files.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The callback writer is a good design but the `mcmc_writer` class needs to be refactored.
Multiple output files require one callback writer per file.
These writers are managed by a composite object which manages a set of callback writer objects
and defines the appropriate set of output methods needed to dispatch information
to the correct writer.

# Drawbacks
[drawbacks]: #drawbacks

The more different kinds of output files, more effort required on the part of the user
to configure and manage these outputs.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?

This refactoring is in line with the original design.

- What other designs have been considered and what is the rationale for not choosing them?

For the output formats, we considered using Google's protocol buffers.
These offer data compression, but would require us to develop a set of schemas
for all outputs.
Furthermore, protocol buffers are a Google library with no guarantee of backwards compatibility,


- What is the impact of not doing this?

All the interfaces and downstream consumers of Stan output have
to implement ad-hoc parsers to deal with the multiplicity of information
in a Stan CSV file.
Providing appropriately structured outputs facilitates development
of more, better, and faster downstream analyses.

# Prior art
[prior-art]: #prior-art

N/A (This is a refactor.  The existing system is the prior art.)

For previous discussion on Discourse and a nascent proposal, see:  https://discourse.mc-stan.org/t/universal-static-logger-style-output/4851/21

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?

Agreement on division of sampler / model outputs in separate but parallel CSV files.

- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?

Use of Apache Arrow/Parquet formats as alternatives for tabular data.

- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

Input readers and converters between data formats.




