- Feature Name: stan-output-formats
- Start Date: 2022-01-11
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

This design provides an alternative to the use of a single
[Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html)
in which information about the algorithm state and model estimates
are combined into a single data table, plus unstructured comment strings.
We propose to replace the single output file with an  output directory.
This will result in a clean separation of different kinds of information
into type-appropriate, commonly used formats and will make it easier to
do downstream analysis.


# Motivation
[motivation]: #motivation

The [Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html) contains a record
of the inference algorithm outputs.  This is the output format used by CmdStan, and therefore by the
CmdStan wrapper interfaces CmdStanPy and CmdStanR.  This format is limited and limiting for several reasons.

* While the plain-text format is human readable, the drawbacks are that conversion to/from binary
is expensive and may lose precision, unless default settings are overridden, which in turn will
result in large output file size.  The plain text format is untyped, therefore we cannot distinguish
between integer, real, or complex numbers.

* The HMC sampler uses comment rows following the header row to report the stepsize, metric type, and metric
and a final set of comment rows to report sampler timing information.
This requires writing ad-hoc parsers to recover this information and precludes the use of many fast CSV parser libraries.

* The Stan CSV file must necessarily use a single table to hold both the inference algorithm state as well as
the model outputs produced by the model class's `write_array` method for each iteration of the inference algorithm.
By convention, the initial columns contain inference algorithm state.
The fist column is the estimated joint log probability `lp__`.
Depending on the inference algorithms, there are zero or more columns whose names end in `__`.
For HMC these are `accept_stat__`,`stepsize__`,`treedepth__`,`n_leapfrog__`,`divergent__`,`energy__`,
for ADVI these are `log_p__` and `log_g__`.
The optimization algorithms don't report any state information beyond `lp__`.

* Because each row of the CSV file corresponds to one iteration, there is no way to monitor the inner workings
of the inference algorithm, e.g., leapfrog steps or gradient trajectories.
The single-row format necessarily flattens structured objects, i.e.,
a Stan model variable `foo` of type `matrix[N,M]` is output as a series of columns `foo[1,1]` ... `foo[N,M]`.

* For MCMC methods, to check for convergence we must run multiple sampler chains.
Stan can now use multi-threading to run multiple chains in a single process,
but it is still necessary to produce per-chain CSV files and this set of files
should be organized so that we can run cross-chain diagnostics.

The `stan::services` layer provides a set of calling functions which
wrap the available inference algorithms.
These wrapping functions have approximately 20 argument slots which are needed
to completely configure the inference run.
Program outputs are managed by `stan::callbacks::writer` objects.
This imposes a one-to-one mapping between the writer and the output file.
The HMC sampler and ADVI calling functions provide two slots for writer callbacks:
the CSV file contining the sampler outputs and a 
[diagnostic_file](https://mc-stan.org/docs/2_29/cmdstan-guide/mcmc-config.html#sampler-diag-file)
which contains the per-iteration latent Hamiltonian dynamics of all model parameters,
as described here:  https://discourse.mc-stan.org/t/sampler-hmc-diagnostics-file/15386;
the optimization algorithms only provide a single slot.

############## Bob comments

In my own uses of CmdStan, I would take the CSV files and try to read them into R in order to do plotting or to compare adaptations from different runs. I would also read them into C++ through stansummary to print posterior summaries. The non-standard format in the CSV output makes this challenging. I see this design as making this process easier for workaday CmdStan users as well as for the CmdStan developers. I think particularly for what I'm calling hierarchical outputs, it'd be more natural to output them in their own JSON files, which are both human and machine readable. They're even easier on humans because you don't have to fish the relevant example out of CSV comments. If you really want a single file for output, zip it.
############## Bob comments


## Current implementation and proposed changes

A CSV file is designed to hold a single table's worth of data in plain text where
each row of the file contains one row of table data, and all rows have the same number of fields.
The CSV format is not precisely defined, but almost all modern CSV parsers 
allow for the first row of data to be treated as a row of column labels
(the "header row") and also allows comment rows which start with a designated comment prefix character.
Because the initial focus of the Stan project was to do MCMC sampling, the CSV file allowed for a
straightforward representation of the posterior sample one row per draw,
one column per output from the Stan program.
Over time, the Stan CSV file has come to be an amalgam of information about the inference engine configuration,
the algorithm state, and the algorithm outputs.
The formats of the per-inference algorithm outputs are described in the
[appendix of the CmdStan User's Guide](https://mc-stan.org/docs/2_29/cmdstan-guide/stan_csv.html)

We propose to break down the information from the Stan inference algorithms into multiple output files
where each file contains one kind of information.
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



# Functional Specification
[functional-spec]: #functional-spec

We propose to develop output handler objects which can manage a set of output streams,
each  of which reports on one facet of the model-data-inference process.
We will add new signatures to the `stan::services` layer to pass these output handlers
to the inference algorithms, replacing the current slots for writer callbacks with
a single slot for the output handler.
This will allow for new output handlers, while still allowing for use of the
current output formats for backwards compatibility.

Given a designated directory, the output handler will create appropriately named output files in this directory.
The outputs will be in known, standard formats, allowing for easier downstream processing.
Tabular data will be either in CSV file format or Apache Arrow format.
Data currently output as string comments in the CSV files will be structured into JSON,
using dictionaries, lists and nested combinations thereof.
Output handlers can be subclassed to handle the different inference algorithm outputs.

This richer set of outputs will make it easier to develop tools which can do online monitoring
of the inference engine run as well as post-process analysis of the program and model outputs.
Examples of the former as the per-draw state of the joint model log probability ("lp__"),
the algorithm state, and individual variable estimates.
For downstream analysis we need to evaluate the goodness of fit  (R-hat, ESS, etc),
and compute statistics for all model parameters and quantities of interest.

For a given run of an inference algorithm with a specific model and dataset,
the outputs of interest can be classified in terms of information source and content
and information structure.
The structure of these outputs can be best represented either as table or as a named list of heterogenous elements.
A cross-cutting classification is whether or not the outputs are one-time outputs or streaming.
The header row and comment sections of the Stan CSV file are generated once during the inference run.
The CSV data rows are produced on a streaming basis.

There are three sources of information:  the Stan model, the inference algorithm, and the inference run.

**The Stan model**. The Stan services layer methods call the following functions on the Stan model class
[``stan::model::model_base``](https://github.com/stan-dev/stan/blob/develop/src/stan/model/model_base.hpp):

+ `log_prob` returns the unnormalized target density and its gradient given the unconstrained model parameters,
thus providing access to the model parameters and transformed parameters on the unconstrained scale.
This is called any number of times during inference, depending on the algorithm.

+ `write_array` provides access to parameters, transformed parameters, and generated quantities on the constrained scale.
Each call produces one row's worth of data, which is streamed to the CSV file.

+ a number of methods provide meta-information about the model:  `model_name`, `(un)constrained_param_names`, `get_dims`.
These are used to create the CSV header row, i.e., they need only be called once per inference run.

**The Inference algorithm**.  Currently, the inference engine outputs are flattened into per-iteration reports, starting with `lp__`.
These are combined with the outputs from the call to `write_array` to produce a single row's worth of CSV data, which is
streamed to the output file.
Other information from the inference algorithm is produced once per run and is reported via comment blocks.
This includes stepsize and metric for NUTS-HMC and stepsize for ADVI.
The current format doesn't allow for fuller reporting of per-iteration computation, e.g., for the NUTS-HMC sampler,
successive leapfrog steps.  Therefore we need to decouple the outputs from the inference engine from the outputs from the model.

**The inference run**.  When CmdStan is used to do inference,
it uses the initial set of the comments in the Stan CSV file to record the complete set of configuration options
and the final block of comments to record timing information.
Not recorded explicitly are the chain and iteration information, when running multiple chains,
or timestamp information for processing events.

The structure of this information can be categorized in two ways:
one-time vs streaming and tabular data or extra-tabular structured data,
yielding the following:

- algorithm config: one-time, hierarchical
- initialization: one-time, tabular
- sample & algorithm diagnostics: streaming, tabular
- metric & step size: one-time, tabular
- timing information: one-time, hierarchical

These distinctions are not well supported at either the stan services layer because the output streams are overloaded and have no hierarchical structure, and they're not well supported at the cmdstan layer because everything gets packed into one CSV file with non-standard encodings through comments.
To address this, the Stan CSV output and diganostic files will be refactored into a series of tables.
For the sake of example we propose the following names:

  + `sample` - the model estimates on the constrained scale; 1 column per variable (element), one row per iteration.
  + `sample_params_unconstrained` - the model parameter and transformed parameter estimates on the unconstrained scale.
  + `log_prob` - the value of `lp__`
  + `algorithm_state` - the per-iteration state of the inference algorithm, e.g. `accept_stat__`, `log_p__`. 
  + `algorithm_internal_state` - this would allow for finer-grained reporting of the inference engine state for development, testing, and debugging purposes.

If we adjoin all the columns in tables `log_prob`, `algorithm_iter_state`, and `model_sample`, the resulting data table would contain the equivalent information in the current Stan CSV file, but critically, not the comment blocks, which would break existing ad-hoc parsers,
e.g., CmdStanPy's `from_csv` method.

Information which is naturally structured as dictionaries, lists, possibly nested, would be output as JSON:

  + `model_metatdata` - model variable names, types, dimensions, and block 
  + `config` - algorithm configuration, for HMC, including stepsize and metric.
  + `timestamps` - a list of timestamps + event descriptors

Using this classification, using Stan to do inference would result in one directory's worth of output files.
The client should be able to specify which files are created and which are omitted.
For example, running the NUTS-HMC sampler for 4 chains and saving only the information currently output
in the Stan CSV files (not the diagnostics file), using Apache Arrow's `parquet` format for the output,
would result in the following output files:

-  `sample_1.parquet` .... `sample_4.parquet`
-  `log_prob_1` .... `log_prob_4.parquet`
-  `algorithm_state_1.parquet` .... `algorithm_state_4.parquet`

-  `model_metdata_1.json` .... `model_metadata_4.json`
-  `config_1.json` .... `config_4.json`
-  `timestamps_1.json` .... `timestamps_4.json`

Downstream clients can use the appropriate Apache Arrow interface to stream the parquet files.
An Apache Arrow parquet file consists of an schema followed by one or more rows of data.
The schema describes the structure of the data objects in each row, allowing the downstream
process to reconstitute structured objects properly.
The Arrow libraries can be used to monitor the outputs to a file on a streaming basis.




### Output mechanism:  callback writers and output handlers

Outputs are handled by objects of base class `stan::callbacks::writer`
which is constructed from an output stream.
The use of writer callbacks keeps the inference algorithms output-format agnostic.
The base writer class uses function call operator overloading
to hand the following kinds of output data:

+ a vector of strings (names)
+ a vector of doubles (data)
+ a string (message)
+ nothing ()

We propose to add new methods to handle:

+ a vector of ints
+ Eigen array, matrix, and vector types

As discussed in the previous section, the `stan::services` layer
provides calling functions which wrap the inference algorithms.
Currently, the Stan interfaces must first instantiate a Stan model object and writer callback(s),
then pass them in to the wrapper function.
The sampling and variational services provide arguments
for both a output and an auxiliary output writers (`diagnostic_writer`)
while the optimization and standalone generated quantities services only provide a single output writer.
In CmdStan, the callback instance is a `stan::callbacks::stream_writer` object
which formats data as CSV comments, header row, and data rows.
The PyStan and RStan interfaces provide R and Python appropriate writer objects.

We propose to add a set of algorithm-specific output handlers which can manage multiple writer callback objects
e.g., `hmc_output_handler`, `advi_output_handler`, `optimization_output_handler`, and to add
a new set of calling functions which take these objects instead of callback writers.
To decouple the output format from the output writer, we will use formatter callbacks.
These classes will provide functions like `write_draws`, `write_unconstrained_params`
which route the information from the inference engine or model to the appropriate callback writer
using the appropriate formatter.


### Stan program outputs

The Stan model class `write_array` method populates a vector of doubles with the values for all
parameter, transformed parameter, and generated quantities (non-local) variables,
in order of declaration in the Stan program.
This vector constitute's one row of data in tabular format, either CSV or Arrow/parquet.

We will use JSON format to record the model variables:  for each we map the variable name
to block declared in, type, unconstrained dimensions, constrained dimensions.
The model object's member functions `constrained_param_names`, `unconstrained_param_names`, `get_constrained_sizedtypes`, `get_unconstrained_sizedtypes`
provide name, type, and shape information.
The reason that the model reports on both the constrained and unconstrained parameters is the Stan parameter types
simplex, correlation, covariance, and Cholesky factors have different shapes on the constrained, unconstrained scale.
For example, a simplex parameter is an N vector whose elements sum to one on the constrained scale which means that it has N-1 free parameters
when computing on the unconstrained scale.
The Stan model parameter inputs and outputs are on the *constrained* scale, therefore the number of parameter values reported by the `write_array` method.
is reported by the `get_constrained_sizedtypes` method.
The sampler computes on the *unconstrained* scale, therefore the size of the metric (inverse mass matrix) is reported by the `get_unconstrained_sizedtypes` method.


### Inference algorithm outputs

The outputs from the inference algorithm necessarily differ according to the method.
Currently, the
inference algorithm either sends information to the callback directly, or, in the case
of the HMC samplers, helper functions make use of  utility class `stan::services::utils::mcmc_writer`
which assembles the outputs from the Stan model and the inference algorithm into
a single row's worth of information sent to the writer callbacks.

The output handler classes will be similar to the `mcmc_writer` class, but instead of
aggregating multiple kinds of output into a single row's worth of data or multiple comment lines
they will send each kind of information to its corresponding callback writer using the
appropriate formatter.



### Interface-level outputs

Currently, the CmdStan interface dumps all configuration information into the Stan CSV file as a series of initial comment lines.
The CmdStan argument parser uses indentation to indicate nested argument structure.
Following the argument parser are several more comment lines of key-value pairs of information
about the software version and compiler options used to compile the Stan model executable.

We propose to output this information as a single JSON object,
allowing for a set of key-value pairs, mapping strings to values,
either a scalar, list, or dictionary object.

# Scope of changes
[scope]: #scope

The changes in this proposal will directly functions in `stan-dev/stan` at the `stan::services` layer.

Keeping the existing `stan::services` layer method signatures will avoid the need for changes to CmdStan.

The input formats used by the inference algorithms are:

- data variable definitions in JSON or [rdump](https://mc-stan.org/docs/cmdstan-guide/rdump.html)
- initial parameter variables in JSON or rdump
- for the standalone generated quantities, inputs include the Stan CSV file which contains the a sample from the fitted model.

The Stan CSV output format will continue to be used for CmdStan outputs. in addition to the new output formats discussed above.


# Drawbacks
[drawbacks]: #drawbacks

The more different kinds of output files, more effort required on the part of the user
to configure and manage these outputs.

Implementing and testing the output handlers and formatters is a non-trivial effort,
especially the effort required to implement the Apache Arrow formatters.
This will require writing functions which translate the model variable structure
into an Arrow schema at the start of processing.
Furthermore, adding Apache Arrow libraries complicates the build process.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?

This is the result of discussions with core Stan developers.  The design refactors
and standardizes output for the support inference algorithms, building on the core
mechanisms:  callback writers and the methods on the Stan model class.

- What other designs have been considered and what is the rationale for not choosing them?

For the output formats, we considered using Google's protocol buffers,
a Google library which has been open-source since 2008.
Protobufs provide good data compression and fast transport.
However, the compressed format requires schemas used for serialization and deserialization,
and these schemas need to be both code-generated and then compiled,
whereas the Apache arrow schema is handled programmatically.
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





