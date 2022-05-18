- Feature Name: stan-output-formats
- Start Date: 2022-01-11
- RFC PR:
- Stan Issue:

## Summary
[summary]: #summary

This design addresses the problem of creating a general and extensible framework
for handling the outputs of the core Stan inference algorithms.
It provides an alternative to the use of the non-standard
[Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html)
as the single record of one run of an inference algorithm.
Instead, the outputs will consist of multiple files, using
standard human- and machine-readable formats, resulting in
a clean separation of different kinds of information into type-appropriate, commonly used formats
which will make it easier to use and create tools for analysis and visualization.
This framework will also make it easier to add new outputs and diagnostics to the inference algorithms.

## Motivation
[motivation]: #motivation

For a given run of an inference algorithm with a specific model and dataset,
the outputs of interest can be classified in terms of information source and content,
information structure, and whether or not they are output once or on a streaming basis,
i.e., for an iterative process, the results are output at the end of each iteration.
There are three sources of information:  the Stan model, the inference algorithm, and the inference run.

**The Stan model**. The Stan services layer methods call the following functions on the Stan model class
[``stan::model::model_base``](https://github.com/stan-dev/stan/blob/develop/src/stan/model/model_base.hpp):

+ `log_prob` returns the unnormalized target density and its gradient given the unconstrained model parameters,
thus providing access to the model parameters and transformed parameters on the unconstrained scale.
This is called any number of times during inference, depending on the algorithm.

+ `write_array` returns an array of doubles over all values on the constrained scale
for all model parameters, transformed parameters, and generated quantities variables.
This is called any number of times during inference, depending on the algorithm.

+ a number of methods provide meta-information about the model:  `model_name`, `(un)constrained_param_names`, `get_dims`.
These need only be called once per inference run as this information is always the same.

**The Inference algorithm**.  Currently, the inference engine state is output once per draw.
This information and the outputs from the call to `write_array` are currently combined into
a single row's worth of data in the Stan CSV file.
Other information from the inference algorithm is produced once per run and is reported via comment blocks:
stepsize and metric for NUTS-HMC; stepsize for ADVI.

**The inference run**.  When CmdStan is used to do inference,
it uses the initial set of the comments in the Stan CSV file to record the complete set of configuration options
and the final block of comments to record timing information.
Not recorded explicitly are the chain and iteration information, when running multiple chains,
or timestamp information for processing events.

The structure of these outputs can be best represented either as table,
i.e., a 2d array of named columns and one or more rows of data,
or as a named list of heterogenous elements.
A cross-cutting classification is whether or not the data it output
once or many times per inference run on a streaming basis.

- Algorithm configuration -  output once, at the start of the inference run.
This information is best structured as a set of name, value pairs, which can be output as a JSON object.

- Parameter initial values - output once, in tabular format.

- Posterior sample - output once per draw - streaming data in tabular format

- Algorithm diagnostic - currently output once per draw - streaming data in tabular format

- Metric & step size - output once, at end of adaptation - the step-size is scalar, the metric is tabular, the metric type is implicit - unit, diagonal, full matrix.

- Timing information - output once at the end of the inference run.  This information is hierarchical.

### Current Outputs - limitations

The [Stan CSV file format](https://mc-stan.org/docs/cmdstan-guide/stan_csv.html)
is the output format used by CmdStan, and therefore by CmdStanPy and CmdStanR.
It provides a record of the inference run and all resulting diagnostics and estimates
which is used for downstream analysis and visualization.
When building models for a given dataset or
developing new inference algorithms, the
output file format sometimes provides too much information,
more commonly, key pieces of information about the sampler and
fitted model state are missing.

A CSV file is designed to hold a single table's worth of data in plain text where
each row of the file contains one row of table data, and all rows have the same number of fields.
For MCMC sampling, the Stan CSV file consists of one draw from the posterior per row
and one Stan program variable per column.
Over time, the Stan CSV file has come to be an amalgam of information about the inference engine configuration,
the algorithm state, and the algorithm outputs.
This format is limited and limiting for several reasons.

* Because the CSV data table is used for the Stan model variable estimates and sampler state,
blocks of CSV comment lines are used to record global information.
For example, the HMC sampler uses comments to report the stepsize, metric type, and metric at the
end of adaptation and another set of comment lines to report timing information.
The use of comment lines anywhere in the CSV file precludes the use of most fast CSV parser libraries.
It is necessary to write an ad-hoc parser to recover the information in the comment block; the
result is slow, error-prone, and brittle.

* While the plain-text format is human readable, it is suboptimal for further processing.
Conversion to/from binary is expensive and may lose precision, unless default settings are overridden, which in turn will
result in large output file size.  The plain text format is untyped, therefore we cannot distinguish
between integer, real, or complex numbers.

* The tabulur row, column format flattens the per-draw outputs.  Both the inference algorithm state
and the Stan program estimates are concatenated into a single row.  Multi-dimensional Stan program variables
are serialized in column-major order.

* Because each row of the CSV file corresponds to one iteration, there is no way to monitor the inner workings
of the inference algorithm, e.g., leapfrog steps or gradient trajectories.

* For MCMC methods, to check for convergence we must run multiple sampler chains
and then manage the resulting set of per-chain CSV files.
Stan can now use multi-threading to run multiple chains in a single process,
but still produces per-chain CSV files.

### Future Outputs - desiderata

This list of limitations can be recast as the set of features we want to support going forward.

* Standard formats for which (efficient, open-source) libraries exist for C++, R, Python, and Julia.

* Binary formats for numeric data.

* Formats which can represent structured data.

* A way to cleanly identify the different kinds of information produced by the interface, inference algorithm, and Stan program.

* A way to configure the output mechanism to control which information is output.

* For MCMC methods, adding chain id information.

This richer set of outputs will make it easier to develop tools which can do online monitoring
of the inference engine run as well as post-process analysis of the program and model outputs.
Examples of the former as the per-draw state of the joint model log probability ("lp__"),
the algorithm state, and individual variable estimates.
For downstream analysis we need to evaluate the goodness of fit  (R-hat, ESS, etc),
and compute statistics for all model parameters and quantities of interest.


## Current implementation

Program outputs are managed by `stan::callbacks::writer` object
which are constructed from a single output stream.
The use of writer callbacks keeps the inference algorithms output-format agnostic.
In CmdStan, the callback instance is a `stan::callbacks::stream_writer` object
which formats data as CSV comments, header row, and data rows.
The PyStan and RStan interfaces provide R and Python appropriate writer objects.
The base writer class uses function call operator overloading
to hand the following kinds of output data:

+ a vector of strings (names)
+ a vector of doubles (data)
+ a string (message)
+ nothing ()

The `stan::services` layer provides a set of calling functions which
wrap the available inference algorithms.
Stan interfaces instantiate the `writer` object and pass it into the `services` layer method
which in turn passes this along to the inference algorithm.
The calling functions for the HMC sampler and ADVI provide two arguments slots for
`stan::callbacks::writer` used for CSV output files:
the CSV file contining the sampler outputs and a 
[diagnostic_file](https://mc-stan.org/docs/2_29/cmdstan-guide/mcmc-config.html#sampler-diag-file)
which contains the per-iteration latent Hamiltonian dynamics of all model parameters,
as described here:  https://discourse.mc-stan.org/t/sampler-hmc-diagnostics-file/15386;
the optimization algorithms only provide a single output CSV file slot.

The CmdStan interface instantiates the `stan::callbacks::writer` object for the Stan CSV file
and writes a series of header comment lines which record the full set of CmdStan arguments as well
as configuration information about both the Stan version and the model object.
The remainder of the Stan CSV file contents are generated by the `services` layer method.


## Functional Specification

The results from one run of the Stan inference engine will be factored into
a series of information and type-specific outputs.
An end-user will be able to specify the outputs of interest.
The interfaces will have control over the output streams.
For a file-based iterface, such as CmdStan, filesystem directories will be used to organize
the resulting set of output files, e.g., instead of command-line argument `file=output.csv`,
the interface will have argument `directory=output`.


### Kinds of outputs, suggested names

Files which are updated with each iteration (i.e., streaming data), which can be monitored by downstream processes:

- `sample` - A table containing the per-draw estimates of all model variables on the constrained scale; 1 column per variable (element), one row per iteration.

- `log_prob` - A table containing the value of `lp__`, the joint log probability density, one row per iteration.
- `algorithm_state` - A table containing the per-iteration state of the inference algorithm, e.g. `accept_stat__`, `log_p__`, one row per iteration.

Note that if we adjoin all the columns in tables `log_prob`, `algorithm_state`, and `_sample`, the resulting data table would contain the equivalent information
in the data table rows of Stan CSV file.

Files which contain global information, produced once per inference algorithm run:

- `hmc_adaptation` - A hierarchical object which contains entries:
   + `stepsize` - A positive scalar value.
   + `metric` - A table which contains the inverse mass matrix arrived at by adaptation.
   + `metric_type` - One of `unit`, `diag`, `dense`.

- `model_metatdata` - A hierarchical object which contains the model variable names, types, dimensions, and declaration block.
- `config` - A hierarchical object which contains the algorithm configuration, model name, and inference type.
- `timestamps` - A table containing pairs of timestamps, event descriptors one row per event.

Optional outputs (under the current interfaces):

- `sample_params_unconstrained` - A table containing the per-draw estimates of just the model parameter and transformed parameters on the unconstrained scale; 1 column per variable (element), one row per iteration.

Outputs not currently available:

- `algorithm_internal_state` - A table which provides finer-grained reporting of the inference engine state for development, testing, and debugging purposes, one row per operation, e.g., leapfrog step.

### Output formats

JSON notation will be used for hierarchical and structured data.
Tabular data will be either in

- CSV format (human-readable)

- Apache Arrow format, which is a self-describing binary data format.
An Apache Arrow parquet file consists of an schema followed by one or more rows of data.
The schema describes the structure of the data objects in each row, allowing the downstream
process to reconstitute structured objects properly.
The Arrow libraries for R and Python will allow downstream analysis packages
to process these files, either during inference or afterwards.

- Unformatted - the binary values returned by methods on the algorithm and model;
all responsibility for handling these outputs lies with the caller.

The Stan CSV output format will remain available via CmdStan.

### Input formats

Outputs from one inference can become inputs to a subsequent one.
The input formats used by the inference algorithms are:

- data variable definitions in JSON or [rdump](https://mc-stan.org/docs/cmdstan-guide/rdump.html)
- initial parameter variables in JSON or rdump
- for the standalone generated quantities, inputs include the Stan CSV file which contains the sample from the fitted model.

Information from one inference run which would become either data or parameter inits would require converting CSV files to JSON.
For standalone generated quantities, a sample in Apache format would need to be converted to CSV format.
We will use existing converter libraries to handle this.

## Technical Specification

To implement the features outlined in the Functional Specification
will require changes in the `stan::services` and `stan::callbacks` layers.

We will define two [C++ Enumeration](https://en.cppreference.com/w/cpp/language/enum)
classes: `InfoType` and `OutputFormat`.

- The values of enum class `InfoType` correspond to the information items listed in
the functional specification, e.g., `LP` (log_prob), `sample`, `metric`, etc.
This provides an extensible mechanism for adding future outputs.

- The values of enum class `OutputFormat` correspond to available output formats.
We expect to implement at least the following:

    + `Arrow` - tabular data in Apache Arrow, other structured data is JSON
    + `Csv` - tabular data in CSV, other structured data is JSON
    + `Raw` - tabular data is output as vector of binary values
    + `StanCsv` - legacy Stan CSV format

We will define an `OutputWriter` class which and we will add new methods to
the services layer calling functions which take a single argument `output_writer`u
(instead of arguments `sample_writer` and `diagnostic_writer`).
The `OutputWriter` class will be sub-classed by output format:
`ArrowOutputWriter` `CsvOutputWriter`, `RawOutputWriter`, `StanCsvOutputWriter`.

The `OutputWriter` object will be instantiated by the Stan interfaces
from a Stan model object and a set of outputs of interest.
The instantiated model object provides the information needed to format and filter
the values produced by the model's  `write_array` function.

The `OutputWriter` class provides a callback method `write_info`
which is parameterized by information type, and its corresponding data.
Based on the information type, the `OutputWriter` object will write
the data to the appropriate output stream.

## Scope of changes
[scope]: #scope

The changes in this proposal will affect the `stan-dev/stan` module.
We will add new functions and logic to `stan::services` and `stan::callbacks`.
We will keep the existing `stan::services` layer method signatures for backwards compatibility with CmdStan.


## Rationale and alternatives
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

## Prior art
[prior-art]: #prior-art

For previous discussion on Discourse and a nascent proposal, see:  https://discourse.mc-stan.org/t/universal-static-logger-style-output/4851/21

## Unresolved questions
[unresolved-questions]: #unresolved-questions



- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

  + Input readers and converters between data formats.
