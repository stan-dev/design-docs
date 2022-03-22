- Feature Name: stan-output-formats
- Start Date: 2022-01-11
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

Provide alternatives to the [Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html)
for outputs of the Stan inference algorithms which are exposed by the `stan::services` layer.

# Motivation
[motivation]: #motivation


The [Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html) contains a record
of the inference algorithm outputs.  This is the output format used by CmdStan, and therefore by the
CmdStan wrapper interfaces CmdStanPy and CmdStanR.  
This format is limited and limiting for several reasons.

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

To overcome these problems, we need to refactor and extend the core Stan output mechanisms
so that so that the inference algorithm and Stan model outputs are factored into discrete units,
using output formats which correspond to the structure of the information,
as detailed in the following sections.


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

For a given run of an inference algorithm given a model and data,
the outputs of interest can be categorized in terms of information source and content
and information structure.

There are three sources of information:

1. The Stan model, class  [``stan::model::model_base``](https://github.com/stan-dev/stan/blob/develop/src/stan/model/model_base.hpp).
The model class method `log_prob` provides access to the model parameters and transformed parameters on the unconstrained scale.
The model class method `write_array` provides access to parameters, transformed parameters, and generated quantities on the constrained scale.
The method `transform_inits` can be used to transform parameters from the constrained to the unconstrained scale.
Finally, a number of methods provide information about the model itself:  `model_name`, `(un)constrained_param_names`, `get_dims`.

2. Inference engine outputs: various diagnostics.
The inference engine outputs are flattened into per-iteration reports.
For the NUTS-HMC sampler, the current outputs are the stepsize and metric, and the per-iteration sampler variables (state).
ADVI reports stepsize `eta` and per-iteration state, and 
The optimization and variational algorithms also report on their respective iterations.


3. Interface-level outputs:
   + model name, compile options, Stan compiler and (Cmd)Stan version and compile options.
   + inference algorithm, user-specified configuration options, and default config.
   + input and output data descriptors.
   + process-level information:  chain, iteration.
   + timing information: timestamp information reported by processing events.

There are two general kinds of information structure: tabular and hierarchical.
[CSV files](https://en.wikipedia.org/wiki/Comma-separated_values) are tabular,
as are R and Python dataframes and database tables.
JSON is a [structured data formats](https://en.wikipedia.org/wiki/Data_exchange#Data_exchange_languages)
which can represent hierarchical structures and arrays.

## Current implementation

We review the way in which the current Stan CSV file is generated for a run of the NUTS-HMC sampler.

### Output mechanism:  callback writers

Outputs are handled by objects of base class `stan::callbacks::writer`
which is constructed from an output stream.
Through function call operator overloading, the callback writer class
methods provide the appropriate formatting for different kinds of data.
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

This refactoring cleans up aspects of the Stan services layer at the cost of making the interfaces do more work.


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

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?

Agreement on division of sampler / model outputs in separate but parallel CSV files.

- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?

Use of Apache Arrow/Parquet formats as alternatives for tabular data.

- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

Input readers and converters between data formats.





