- Feature Name: parallel_chain_api
- Start Date: 2021-04-06
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

This outlines a services layer API for running multiple chains in one Stan program.

# Motivation
[motivation]: #motivation

Currently, to run multiple chains for a given model a user or developer must use higher level parallelization tools such as `gnu parallel` or R/Python parallelism schemes. The high level approach is partly done because of intracacies at the lower level around managing Stan's thread local stack allocators along with multi-threaded IO. Providing a service layer API for multiple chains in one Stan program will remove the requirment of interfaces to impliment all the necessary tools for parallel chains in one Stan program independently. Moreover, we have access to the TBB and with it a schedular for managing hierarchical parallelism. We can utilize the TBB to provide service API's for running multiple chains in one program and safely account for possible parallelism within a model using tools such as `reduce_sum()`.

The benefits to this scheme are mostly in memory savings and standardization of multi chain processes in Stan. Because a stan model is immutable after construction it's possible to share that model across all chains. For a model that uses 1GB of data running 8 chains in parallel means we use 8GB of RAM. However by sharing the model across the chains we simply use 1GB of data.

Having a standardized IO and API for multi chain processes will allow researchers to develop methods which utilize information across chains. This research can allow for algorithms such as automated warmup periods where instead of hard coding the number of warmups, warmups will only happen until a set of conditions are achieved and then we can begin sampling.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Each of the servies layers in [`src/stan/services/`](https://github.com/stan-dev/stan/blob/147fba5fb93aa007ec42744a36d97cc84c291945/src/stan/services/sample/hmc_nuts_dense_e_adapt.hpp) will have the current API for single chain processes as well as an API for running multi chain processes. Their inputs are conceptually the same, but several of the inputs have been changed to be vectors of the single chain processes arguments in order to account for multiple chains. For instance, the signature of a single chain for `hmc_nuts_dense_e_adapt` now has `std::vector`s for the initialial values, inverse metric, init writers, sample writers, and diagnostic writers.

```cpp
template <class Model>
int hmc_nuts_dense_e_adapt(
    Model& model,
    const stan::io::var_context& init,
    const stan::io::var_context& init_inv_metric,
    unsigned int random_seed,
    unsigned int init_chain_id, double init_radius, int num_warmup, int num_samples,
    int num_thin, bool save_warmup, int refresh, double stepsize,
    double stepsize_jitter, int max_depth, double delta, double gamma,
    double kappa, double t0, unsigned int init_buffer, unsigned int term_buffer,
    unsigned int window,
    callbacks::interrupt& interrupt,
    callbacks::logger& logger,
    callbacks::writer& init_writer,
    callbacks::writer& sample_writer,
    callbacks::writer& diagnostic_writer)
```

```cpp
template <typename Model, typename InitContext, typename InitInvContext,
          typename InitWriter, typename SampleWriter, typename DiagnosticWriter>
int hmc_nuts_dense_e_adapt(
    Model& model,
    size_t num_chains,
    // now vectors
    const std::vector<InitContext>& init,
    const std::vector<InitInvContext>& init_inv_metric,
    unsigned int random_seed, unsigned int init_chain_id, double init_radius,
    int num_warmup, int num_samples, int num_thin, bool save_warmup,
    int refresh, double stepsize, double stepsize_jitter, int max_depth,
    double delta, double gamma, double kappa, double t0,
    unsigned int init_buffer, unsigned int term_buffer, unsigned int window,
    // interrupt and logger must be threadsafe
    callbacks::interrupt& interrupt,
    callbacks::logger& logger,
    // now vectors
    std::vector<InitWriter>& init_writer,
    std::vector<SampleWriter>& sample_writer,
    std::vector<DiagnosticWriter>& diagnostic_writer)
```

Additionally the new API has an argument `num_chains` which tells the backend how many chains to run and `init_chain_id` instead of `chain`. `init_chain_id` will be used to generate PRNGs for each chain as `seed + init_chain_id + chain_num` where `chain_num` is the i'th chain being generated. All of the vector inputs must be the same size as `num_chains`. `InitContext` and `InitInvContext` must have a valid `operator*` which returns back a reference to a class derived from `stan::io::var_context`.

The elements of the vectors for `init`, `init_inv_metric`, `interrupt`, `logger`, `init_writer`, `sample_writer`, and `diagnostic_writer` must be threadsafe. `init` and `init_inv_metric` are only read from so should be threadsafe by default. Any of the writers which write to `std::cout` are safe by the standard, though it is recommended to write any output to an local `std::stringstream` and then pass the fully constructed output so that thread outputs are not mixed together. See the code [here](https://github.com/stan-dev/stan/pull/3033/files#diff-ab5eb0683288927defb395f1af49548c189f6e7ab4b06e217dec046b0c1be541R80) for an example. Additionally if the elements of `init_writer`, `sample_writer`, and `diagnostic_writer` each point to unique output they will be threadsafe as well.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The services API on the backend has a prototype implementation found [here](https://github.com/stan-dev/stan/blob/147fba5fb93aa007ec42744a36d97cc84c291945/src/stan/services/sample/hmc_nuts_dense_e_adapt.hpp#L206). The main additions to this change are in creating the following for each chain.

1. PRNGs
2. Initializations
3. Samplers
4. inverse metrics

Then a [`tbb::parallel_for()`](https://github.com/stan-dev/stan/blob/147fba5fb93aa007ec42744a36d97cc84c291945/src/stan/services/sample/hmc_nuts_dense_e_adapt.hpp#L261) is used to run the each of the samplers.

PRNGs will be initialized such as the following pseudocode, where a constant stride is used to initialize the PRNG.

```cpp
inline boost::ecuyer1988 create_rng(unsigned int seed, unsigned int init_chain_id, unsigned int chain_num) {
  // Initialize L’ecuyer generator
  boost::ecuyer1988 rng(seed);

  // Seek generator to disjoint region for each chain
  static uintmax_t DISCARD_STRIDE = static_cast<uintmax_t>(1) << 50;
  rng.discard(DISCARD_STRIDE * (init_chain_id + chain_num - 1));
  return rng;
}
```

The constant stride guarantees that models which use multiple chains in one program and multiple programs using multiple chains are able to be reproducible given the same seed as noted below.  

### Recommended Upstream Initialization

Upstream packages can generate `init` and `init_inv_metric` as they wish, though for cmdstan the prototype follows the following rules for reading user input.

If the user specifies their init as `{file_name}.{file_ending}` with an input `id` of `N` and chains `M` then the program will search for `{file_name}_{N..(N + M)}.{file_ending}` where `N..(N + M)` is a linear integer sequence from `N` to `N + M`. If the program fails to find any of the `{file_name}_{N..(N + M)}.{file_ending}` it will then search for `{file_name}.{file_ending}` and if found will use that. Otherwise an exception will occur.

For example, if a user specifies `chains=4`, `id=2`, and their init file as `init=init.data.R` then the program
will first search for `init.data_2.R` and if it finds it will then search for `init.data_3.R`,
`init.data_4.R`, `init.data_5.R` and will fail if all files are not found. If the program fails to find `init.data_2.R` then it will attempt
to find `init.data.R` and if successful will use these initial values for all chains. If neither
are found then an error will be thrown.

Documentation must be added to clarify reproducibility between a multi-chain program and running multiple chains across several programs. This requires

1. Using the same random seed for the multi-chain program and each program running a chain.
2. Starting each program in the multi-chain context with the `ith` chain number.

For example, the following two sets of calls should produce the same results up to floating point accuracy.

```bash
# From cmdstan example folder
# running 4 chains at once
examples/bernoulli/bernoulli sample data file=examples/bernoulli/bernoulli.data.R chains=4 id=1 random seed=123 output file=output.csv
# Running 4 seperate chains
examples/bernoulli/bernoulli sample data file=examples/bernoulli/bernoulli.data.R chains=1 id=1 random seed=123 output file=output1.csv
examples/bernoulli/bernoulli sample data file=examples/bernoulli/bernoulli.data.R chains=1 id=2 random seed=123 output file=output2.csv
examples/bernoulli/bernoulli sample data file=examples/bernoulli/bernoulli.data.R chains=1 id=3 random seed=123 output file=output3.csv

examples/bernoulli/bernoulli sample data file=examples/bernoulli/bernoulli.data.R chains=1 id=4 random seed=123 output file=output4.csv
```

In general the constant stride allow for the following where `n1 + n2 + n3 + n4 = N` chains.

```
seed=848383, id=1, chains=n1
seed=848383, id=1 + n1, chains=n2
seed=848383, id=1 + n1 + n2, chains=n3
seed=848383, id=1 + n1 + n2 + n3, chains=n4
```



# Drawbacks
[drawbacks]: #drawbacks

This does add overhead to existing implementations in managing the per chain IO.
