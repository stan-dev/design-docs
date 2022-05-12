## Technical Specification

To accomplish the above require changes to parts of the `stan::services` layer.
We will add algorithm-specific output handler objects to `stan::services`.
which manage multiple writer callback objects e.g., `hmc_output_handler`, `advi_output_handler`, `optimization_output_handler`.

These handler objects will be instantiated by the Stan interfaces.
The interface will determine which information is output and where it is sent to.
through use of a mapping from output types to `stan::callbacks::writer` objects.
We will add new signatures to the `stan::services` layer calling methods
to pass these output handlers to the inference algorithms, replacing the current slots for writer callbacks with
a single slot for the output handler.
This will allow for new output handlers, while still allowing for use of the
current output formats for backwards compatibility.

To decouple the output format from the output writer, we will use formatter callbacks.
These classes will provide functions like `write_draws`, `write_unconstrained_params`
which route the information from the inference engine or model to the appropriate callback writer
using the appropriate formatter.

We will expand the set of data types that the `stan::callbacks::writer` object can handle to include:

+ a vector of ints
+ Eigen array, matrix, and vector types


### Creating Apache Arrow schemas for inference algorithm and Stan model data

The instantiated model object provides the information used to create an Apache Arrow schema
used to serialize the values produced by the model's `write_array` function.
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

