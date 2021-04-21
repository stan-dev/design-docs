- Feature Name: parallel_chain_api
- Start Date: 2021-04-06
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

This outlines a services layer API for running multiple chains in one Stan program.

# Motivation
[motivation]: #motivation

Currently, to run multiple chains for a given model a user or developer must use higher level parallelization tools such as `gnu parallel` or R/Python parallelism schemes. However, we have access to the TBB and with it a schedular for managing hierarchical parallelism. We can utilize the TBB to provide service API's for running multiple chains in one program and safely account for possible parallelism within a model using tools such as `reduce_sum()`.

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
template <class Model, typename InitContext, typename InitInvContext,
          typename InitWriter, typename SampleWriter, typename DiagnosticWriter>
int hmc_nuts_dense_e_adapt(
    Model& model,
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
    std::vector<DiagnosticWriter>& diagnostic_writer,
    size_t num_chains)
```

Additionally the new API has an argument `num_chains` which tells the backend how many chains to run and `init_chain_id` instead of `chain`. `init_chain_id` will be used to generate PRNGs for each chain as `seed + init_chain_id + chain_num` where `chain_num` is the i'th chain being generated. All of the vector inputs must be the same size as `num_chains`. For optional flexibility, `InitContext` and `InitInvContext` can either be any type inheriting from `stan::io::var_context` or either `std::shared_ptr<>` or `std::unique_ptr<>` with an underlying pointer whose type is derived from `stan::io::var_context`. Within the new API these arguments are accessed through a function `stan::io::get_underlying(const T& x)` which for any of the above inputs returns a reference to the object inheriting from `stan::io::var_context`. For upstream APIs such as rstan which uses `Rcpp` this function can be overloaded to support smart pointers such as `Rcpp::Xptr`.

```cpp
namespace stan {
namespace io {
template <typename T>
const auto& get_underlying(const Rcpp::Xptr<T>& x) {
  return *x;
}
}
}
```

This scheme allows for flexibility, where a user can pass one initialization for all chains and the program can make one shared pointer used in all instances of the vector.

The elements of the vectors for `init`, `init_inv_metric`, `interrupt`, `logger`, `init_writer`, `sample_writer`, and `diagnostic_writer` must be threadsafe. `init` and `init_inv_metric` are only read from so should be threadsafe by default. Any of the writers which write to `std::cout` are safe by the standard, though it is recommended to write any output to an local `std::stringstream` and then pass the fully constructed output so that thread outputs are not mixed together. See the code [here](https://github.com/stan-dev/stan/pull/3033/files#diff-ab5eb0683288927defb395f1af49548c189f6e7ab4b06e217dec046b0c1be541R80) for an example. Additionally if the elements of `init_writer`, `sample_writer`, and `diagnostic_writer` each point to unique output they will be threadsafe as well.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The services API on the backend has a prototype implementation found [here](https://github.com/stan-dev/stan/blob/147fba5fb93aa007ec42744a36d97cc84c291945/src/stan/services/sample/hmc_nuts_dense_e_adapt.hpp#L206). The main additions to this change are in creating the following for each chain.

1. PRNGs
2. Initializations
3. Samplers
4. inverse metrics

Then a [`tbb::parallel_for()`](https://github.com/stan-dev/stan/blob/147fba5fb93aa007ec42744a36d97cc84c291945/src/stan/services/sample/hmc_nuts_dense_e_adapt.hpp#L261) is used to run the each of the samplers.

### Recommended Upstream Initialization

Upstream packages can generate `init` and `init_inv_metric` as they wish, though for cmdstan the prototype follows the following rules for reading user input.

If the user specifies their init as `{file_name}.{file_ending}` with an input `id` of `N` and chains `M` then the program will search for `{file_name}_{N..(N + M)}.{file_ending}` where `N..(N + M)` is a linear integer sequence from `N` to `N + M`. If the program fails to find any of the `{file_name}_{N..(N + M)}.{file_ending}` it will then search for `{file_name}.{file_ending}` and if found will use that. Otherwise an exception will occur.

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



# Drawbacks
[drawbacks]: #drawbacks

This does add overhead to existing implimentations in managing the per chain IO.


### Open Questions

The main open question is whether to recommend upstream users of services to generate N models or a single model
whenever a Stan program uses `*_rng()` functions in transformed data for methods such as Simulation Based Calibration.
With 1 model the transformed data will be shared across all chains. With SBC we commonly want to run multiple
data sets and the question is whether we want multiple chains over one dataset or a chain for each data set.
If we would like to have multiple models in one program if the user uses an `*_rng()` there is a [`stanc3 PR`](https://github.com/stan-dev/stanc3/pull/868) to add a method to check whether the user uses an rng function in
tranformed data. Upstream service users can generate one model, then ask it if an rng is used in transformed data
to decide whether it wants to generate N more models.

Personally, I think it makes since to run multiple chains for each generated dataset (having 1 model).
This makes sense to me as we can check for recovery of parameters given K datasets and N chains per dataset.
