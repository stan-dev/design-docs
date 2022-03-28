- Feature Name: stan-output-formats
- Start Date: 2022-01-11
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

In order to monitor the progress of CmdStan's inference algorithms,
the outputs from CmdStan must be available to downstream readers on a streaming basis.
This design provides an alternative to the use of a single
[Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html)
in which information about the algorithm state and model estimates
are combined into a single data table, plus unstructured comment strings.
We propose to use a single output directory instead, which will contain multiple
files, each of which contains a single kind of information in a type-appropriate
format, supported by commonly used processing libraries.


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


* The Stan CSV file must necessarily use a single table to hold both the inference algorithm state as well as
the model outputs produced by the model class's `write_array`.
By convention, the initial columns contain inference algorithm state.
The fist column is the estimated joint log probability `lp__`.
Depending on the inference algorithms, there are zero or more columns whose names end in `__`.
For HMC these are `accept_stat__`,`stepsize__`,`treedepth__`,`n_leapfrog__`,`divergent__`,`energy__`,
for ADVI these are `log_p__` and `log_g__`.
The optimization algorithms don't report any state information beyond `lp__`.

* Because each row of the CSV file corresponds to one draw, there is no way to monitor the inner workings
of the inference algorithm, e.g., leapfrog steps or gradient trajectories.

* Although we can now run multiple chains in a single process, it is still necessary to produce per-chain CSV files,
with the chain id baked into the filename.   An alternative solution would be to combine all outputs in a single file,
adding a column for chain-id but the downside to this would be that having multiple chains write to a single output file
increases the code complexity.

* Currently, the HMC sampler can also be configured to produce a [diagnostic_file](https://mc-stan.org/docs/2_29/cmdstan-guide/mcmc-config.html#sampler-diag-file)
which contains the per-iteration latent Hamiltonian dynamics of all model parameters,
as described here:  https://discourse.mc-stan.org/t/sampler-hmc-diagnostics-file/15386.
To do this, the calling functions to the HMC sampler in `stan::services` layer
have two output file argument slots:  one for the Stan CSV file and one for the diagnostics file.
This design doesn't easily admit of adding more kinds of output files.

To overcome these problems, we need to add new output mechanisms to core Stan.
For models which require extended processing we need to be able to monitor progress of both
the resulting inferences and the internals of the inference algorithm.
Examples of the former as the per-draw state of the joint model log probability ("lp__")
as well as individual model variables.
Examples of the latter are the algorithm state at each step of an interactive process.
For downstream analysis we need to evaluate the goodness of fit  (R-hat, ESS, etc),
and compute statistics for all model parameters and quantities of interest.

We propose to develop additional output handlers which produce multiple output streams,
each reporting on one facet of the model-data-inference process.
Given a designated directory, the output handler will create appropriately named output files in this directory.
These streams will be in known, standard formats, allowing for easier downstream processing.
For backwards compatibility we will maintain the current CmdStan Stan CSV output file format, as is.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

For a given run of an inference algorithm with a specific model and dataset,
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
The current format doesn't allow for fuller reporting of per-iteration computation, e.g., for the NUTS-HMC sampler,
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
The formats of the per-inference algorithm outputs are described in the
[appendix of the CmdStan User's Guide](https://mc-stan.org/docs/2_29/cmdstan-guide/stan_csv.html)

### Output mechanism:  callback writers

Outputs are handled by objects of base class `stan::callbacks::writer`
which is constructed from an output stream.
The use of writer callbacks keeps the inference algorithms output-format agnostic.
Through function call operator overloading, the writer
can handle the following data structures:

+ a vector of strings (names)
+ a vector of doubles (data)
+ a string (message)
+ nothing - blank input

The `stan::services` layer provides the set of functions which wrap the inference algorithms.
To do inference given a model, data, and config,
the Stan interfaces first instantiate the Stan model object and the writer callback,
which are passed in to the appropriate `stan::services` function.
The sampling and variational services provide arguments
for both a output and an auxiliary output writers (`diagnostic_writer`)
while the optimization and standalone generated quantities services only provide a single output writer.
In CmdStan, the callback instance is a `stan::callbacks::stream_writer` object
which formats data as CSV comments, header row, and data rows.
The PyStan and RStan interfaces provide R and Python appropriate writer objects.

### Stan program outputs

The Stan model class `write_array` method returns a vector of doubles for all
parameter, transformed parameter, and generated quantities (non-local) variables,
in order of declaration in the Stan program.

The model object's member functions `constrained_param_names`, `unconstrained_param_names`, `get_constrained_sizedtypes`, `get_unconstrained_sizedtypes`
provide name, type, and shape information.
The reason that the model reports on both the constrained and unconstrained parameters is the Stan parameter types
simplex, correlation, covariance, and Cholesky factors have different shapes on the constrained, unconstrained scale.
For example, a simplex parameter is an N vector whose elements sum to one on the constrained scale which means that it has N-1 free parameters
when computing on the unconstrained scale.
The Stan model parameter inputs and outputs are on the *constrained* scale, therefore the number of parameter values reported by the `write_array` method
is reported by the `get_constrained_sizedtypes` method.
The sampler computes on the *unconstrained* scale, therefore the size of the metric (inverse mass matrix) is reported by the `get_unconstrained_sizedtypes` method.

### Inference algorithm outputs

The outputs from the inference algorithm necessarily differ according to the method.
The inference algorithm either sends information to the callback directly, or, in the case
of the HMC samplers, helper functions make use of  utility class `stan::services::utils::mcmc_writer`
which assembles the outputs from the Stan model and the inference algorithm into
a single row's worth of information sent to the writer callbacks.


### Interface-level outputs

The CmdStan interface dumps all configuration information into the Stan CSV file as a series of initial comment lines.
The CmdStan argument parser uses indentation to indicate nested argument structure.
Following the argument parser are several more comment lines of key-value pairs of information
about the software version and compiler options used to compile the Stan model executable.
To save a record of the inference run, we wish to store this in a structured format
allowing for lists, maps, and nested lists and maps.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

We propose to break down the information from the Stan inference algorithms into a series of output streams
where each stream handles one kind of information and whose format is appropriate for further processing.
Tabular data will be output either in CSV format (human readable) or using the Apache Arrow binary formats.
For hierarchical data we will use JSON format.

Tabular information includes:

- The output from the Stan model class `write_array` function: the computed values for all Stan model variables on the constrained scale.
- The Stan model parameter variables on the unconstrained scale returned by the `log_prob` function.
- The inference algorithm state at each step of the iterative algorithm.

Structured information includes:

- The HMC tuning parameters:  metric and stepsize.  The HMC metric is a symmetric positive definite matrix, either a diagonal or a dense matrix.
The former is reported as just the vector that is matrix diagonal, the latter is reported as the full matrix.  The HMC stepsize is a scalar.

- Stan model variables schema: a list of all model variables including: block, name, type, shape, size, output column name(s)

- Information about the inference run:  algorithm configuration, Stan version, model compiler version and compile options, and timing information.

## Implementation

To improve and generalize the outputs and output formats, we propose to:

- implement new classes which extend the `stan::callbacks::writer` base class in an algorithm-specific fashion
and which will be passed in to the `stan::services` layer wrapper functions.
Like the existing `stan::callbacks::unique_stream_writer`, the algorithm specific writers will
manage multiple output streams.  This will 

- decouple the output format from the writer through the use of formatter callbacks.
For tabular data we will implement CSV and Apache Arrow formatters.
For extra-tabular structured data we will implement a JSON formatter.

For the HMC sampler algorithms we 
propose to refactor the utility class `stan::servhices::utils::mcmc_writer`
into a callback writer, i.e., `stan::callbacks::hmc_writer`.
The callback writer is supplied with a filesystem directory name and data formatters.
The calling signatures for services layer wrapper functions to the HMC sampler will take a single
`stan::callbacks::hmc_writer` argument, instead of two `stan::callbacks::writer` arguments.
The `stan::callbacks::hmc_writer` class will include the same set of methods as are currently
implemented on the `stan::services::utils::mcmc_writer` class.
For the optimization algorithms, we would need to introduce an `optimization_writer`,
likewise for ADVI, we would introduce an `advi_writer`.

The CSV structured data formatter corresponds to the current set of methods on the base callbacks writer class.
The JSON and Apache Arrow formatters would need to be able to handle lists and dictionaries, for the former,
and scalar and vectors of ints and doubles for the latter.


# Drawbacks
[drawbacks]: #drawbacks

The more different kinds of output files, more effort required on the part of the user
to configure and manage these outputs.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?

The proposed refactoring uses the writer callbacks and extends them.

- What other designs have been considered and what is the rationale for not choosing them?

For the output formats, we considered using Google's protocol buffers.CmdStan output have
This is a Google library which has been open-source since 2008.
They provide good data compression and fast transport.
However, the compressed format requires schemas used for serialization and deserialization.
From the perspective of downstream processing applications, Apache Arrow files are easier to work with,
as the schema is sent as the first part of the file.
While Apache Arrow files are larger, they are still far smaller than regular text files.

- What is the impact of not doing this?

Continuing to use the Stan CSV file format means that 
downstream consumers of these files must to implement ad-hoc parsers
and corresponding data structures to deal with the multiple kinds of data in a Stan CSV file.
Providing appropriately structured outputs facilitates development
of more, better, and faster downstream analyses.

# Prior art
[prior-art]: #prior-art

For previous discussion on Discourse and a nascent proposal, see:  https://discourse.mc-stan.org/t/universal-static-logger-style-output/4851/21

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?

  + Which information should be recorded as metadata.

- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?

  + Appropriate C++ data structures needed to create JSON objects
  + Creating Apache Arrow schemas for inference algorithm and Stan model data.

- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

  + Input readers and converters between data formats.





