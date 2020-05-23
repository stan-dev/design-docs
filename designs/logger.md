- Feature Name: Loggers, writers, and interrupts in one object
- Start Date: 2018-05-25
- RFC PR: ??
- Stan Issue:

See [discourse](http://discourse.mc-stan.org/t/proposal-for-consolidated-output/4263) for discussion, see history for whodunit.

## Problem

The current design has problems for moving forward:

1. There's an init writer, a sample writer, and a diagnostic writer + logger.  The sample writer gets algorithm parameters (mixed types) and model parameters (doubles) and is responsible for writing them all.  The diagnostic writer gets (for sampling) the momenta (doubles) for each parameter as well as the gradients (doubles) for each parameter.  The overall problem is that the separation of concerns is not clean (so, e.g. momenta and gradients are interleaved in the diagnostic writer) and some outputs don't have a clear place to go.  For example in CmdStan the diagonal of the mass matrix is output as a comment in the middle of the csv + comments output.
2. The logger would be an ideal place to log additional info (such as optionally, as Martin has suggested, divergence-related information) but all logger output is text and it's creating extra work to, e.g., translate std::vector<double> -> text -> native R type.  The interfaces have to work too hard to implement basic functionality and they are diverging because of it.
3. Output has to be manipulated within the algorithm implementations to fit right into the writers.  There's no reason for the algorithm to know about how its output is handled, it should just pass it on.

## Current goals:

1. Run a each Stan algorithm, from each interface, and produce output with minimal interface-specific code.
2. Maintenance. Be able to expand the output to accommodate new inference algorithms in addition to updating output for existing inference algorithms.
3. Be able to add new streams of diagnostic information easily (see e.g. [thread on adding ends of divergent transitions](http://discourse.mc-stan.org/t/getting-the-location-gradients-of-divergences-not-of-iteration-starting-points/4226/) )

## Future goals (so current non-goals):
1. Interoperability between interfaces. We should be able to run in one interface and perform analysis in another interface.  This will be a breaking change and is therefore Stan3 material.
2. Use subsets of the output. RStan and PyStan currently have features to only record certain values. CmdStan doesn't save the warmup by default. The interface implementation could be shared between RStan/PyStan/CmdStan and allow filtering. This is not a breaking change since default behavior can match current default behavior.

## Problem in detail

We currently have these inference algorithms:

- Sampling (13)
  1. fixed\_param
  2. hmc\_nuts\_dense\_e
  3. hmc\_nuts\_dense\_e\_adapt
  4. hmc\_nuts\_diag\_e
  5. hmc\_nuts\_diag\_e\_adapt
  6. hmc\_nuts\_unit\_e
  7. hmc\_nuts\_unit\_e\_adapt
  8. hmc\_static\_dense\_e
  9. hmc\_static\_dense\_e\_adapt
  10. hmc\_static\_diag\_e
  11. hmc\_static\_diag\_e\_adapt
  12. hmc\_static\_unit\_e
  13. hmc\_static\_unit\_e\_adapt
- Optimization (3)
  1. bfgs
  2. lbfgs
  3. newton
- (Experimental) Variational Inference (2)
  1. mean field
  2. full rank

Currently, the output approach works well for sampling since it's gotten most attention but not so much for optimization/ADVI.  For example ADVI has no obvious point density to calculate and currently outputs a confusing default value (NA or something?). This has posed difficulty with implementing new algorithms (e.g.- ADVI) and led to hacks in the interfaces or incomplete implementation of accessors for algorithm data.  All the algorithms have typed output (e.g.-error messages, mass matrix) that get converted to text and piped into the logger, which is not ideal since the interfaces have to take text and parse it to produce basic diagnostic output.  To add new outputs we need to pass more and more types of writers which modifies the signatures of services and breaks the interfaces.

## Solutions:

1) A simple struct (let's call it "relay") with member variables that hold smart pointers to writers.  The *interface* is responsible for instantiating the struct using smart pointers to writers for handling each of the types of outputs required by the algorithms in `stan-dev/stan`.  The algorithms (in `stan-dev/stan`) are responsible for calling the right logger at the site where output must be produced: `relay.hmc_algorithm_parameter_writer(stepsize, accept_stat, ...)` or `relay.model_parameter_writer(parameters)`.  Then the members of relay can be writers and the code in `relay` ends up documenting what is required of the interfaces (which kinds of writers can be used to initialize a `relay`).  The code in each writer documents how the interface can interact with it, and writers can be re-used in a relay (so that the per-iteration values for parameters, their gradients, and their momenta could all share a writer).  **Maintenance**: This way we get as many `relay` classes as we have algorithms, and if we want to re-use `writer` classes we can (so we end up with 13 + 3 + 2 relays (one per algorithm, could be reduced by templating or at least organized with inheritance) and 4 writers (logger, key-value, heterogeneous table , homogeneous table, with lots of templating).

2) The reason so many relay classes are required is just to differentiate
between which relay is called in which algorithm, and the difference within the 13 HMC relay versions
are discrete (diagonal vs. unit mass matrix) and combinatorial (only 2 kinds of HMC, 3 kinds of mass matrices, plus adapt/no-adapt).  Instead of having a whole relay class for each algorithm class, you could use a policy-based design where the information about, e.g., the kind of mass matrix the algorithm will end up writing lives in a policy class (https://en.wikipedia.org/wiki/Policy-based_design).  Martin [implemented](https://repl.it/repls/TidyExtrasmallProlog) something like this.  Krzysztof [separated the code out into separate files so it's clearer who would be responsible for what](https://repl.it/@KrzysztofSakrej/TidyExtrasmallProlog-1)


## What the objects are:
1. A `relay` that is 1) constructed by the interface code; 2) used as an argument to service functions; and 3) called in `stan-dev/stan` at the site where output needs to be relayed to the interface.  This is at least a struct holding a set of purpose-specific writers.  It can also be a templated class as in Martin's code.
2. For each output type: structs (are they usually called tags?) that define what each output type is.
3. Interface-defined data stream types that describe how each output type defined by a tag will be handled.

For example see original code: https://repl.it/repls/TidyExtrasmallProlog
Also see how code could be split in Stan: https://repl.it/@KrzysztofSakrej/TidyExtrasmallProlog-1

## What the output layer will provide to the algorithms:

A 'relay' object that has methods to dump output into _without conversion_, methods on the relay object will cover
1. key-value output `relay.kv<handler_type>(string key, T value)`
2. heterogeneous table output with:
  - Column types specified at template instantiation
  - Column names are specified at construction
  - Proper usage w.r.t. types is checked at construction
  - Proper usage w.r.t. number of columns checked at run-time
  - `relay.table<handler_type>(T1 v1, T2 v2, ...);`
  - (MAYBE): `relay.table<handler_type>(T v);` they do have to be
    pushed in correct order but do not have to be collected prior to push.
3. homogenous table output with:
  - Column types specified at template instantiation
  - Column names are specified at construction
  - Proper usage w.r.t. types is checked at construction
  - Proper usage w.r.t. number of columns checked at run-time
  - requirement that an entire row is written at once.
  - `relay.array<handler_type>(std::vector<T>/Eigen::vector<T>)`
4. logger output (using the current logger), this is the text-output stream of last resort.

The algorithm should use the simplest one available and prefer to not modify output.  For example sampler parameters should be in a heterogeneous table if they are available near the same call site, key-value output can be used with irregularly-produced output, homogeneous tables are best for model parameters, and we should avoid separating output types with special suffixes (e.g.-the current situation with lp__, treedepth__, etc...).  The `handler_type` (consumer?) specifies types for the table/array and how different types are handled in the key/value call.

## What the output implementation will provide to the interfaces

1. Interfaces should only have to write the `handler_type` classes for each array to cover
2. We should provide common handler_type classes for, e.g., file output
3. We should provide common handler_type classes for ignoring output

... more not done

## What algorithm implementations will have to provide to interfaces

Description of the required `handler_type`s

... more not done
