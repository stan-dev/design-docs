# PyCmdStan Functional Specification

PyCmdStan provides the necessary objects and functions to compile a Stan program
and to do either MCMC sampling for full Bayesian inference
or optimization to provide a point estimate at the posterior mode from within
a Python program or the interpreter.

## Goals and design considerations

- clean interface to (Cmd)Stan services so that PyCmdStan keeps up with Stan releases

- choices for naming and structuring objects and functions should reflect the Stan workflow.

- flat structure for specifying arguments to (Cmd)Stan services

- favor immutable objects

- minimal Python library dependencies: numpy, pandas. additional libs: scipy, matplotlib

## Objects

#### model

A model is a specification of a joint probability density in the form of a Stan program.
Models are translated to c++ by the `stanc` compiler (CmdStan `bin/stanc`).

#### data

This is either a string which contains the (full path)name of a file
or the name of a Python `dict` object.

If this is a string, then it is treated as the (full) pathname of a file,
the contents of which are either a single JSON object or an Rdump file.
The JSON object or Rdump file must contain entries for all data variables specified by the model.
Each entry must be of the correct type and shape and meet all constraints for that data variable.

In order to fit a Stan model to data in the Python environment, this data must be
assembled into a Python `dict` with entries for all data variables specified by the model
and serialized to a file in JSON format.

#### posterior sample

A posterior sample is a set of draws from the sampler.
It consists of a N x M matrix of real-valued numbers, one row per draw,
one column per parameter value or sampler state diagnostic, including chain ID.

#### posterior estimate

A posterior estimate is an array of point estimates (real-valued numbers) for the model parameters.

## Functions

##### compile_file

Compile Stan model, returning immutable instance of a compiled model.
Always compiles model, even if compiled object exists which is newer than source file.

```
model = compile_file(path = None,
                     cpp_compiler = 'clang++',
                     cpp_optimization_level = 2,  // or 3
                     num_threads = 1,             // or system(-logical)
                     mpi = false)                 // path to MPI?
```

discussion points:

- installation-specific compiler flags and options - are these environment variables (as in current PyCmdStan)?
  + need to allow overriding generic compiler flags as well
  + add a cpp_flags arg that is pasted into the compilation cmd last
  + path to MPI - users set flag MPICXX (which sets include flags, and library locations).


##### _missing function:  condition model on data_

Allows user to evaluate model specification and correctness of data inputs.
Feasible, but work done in this step can't be saved.

##### sample using HMC/NUTS

Produce sample output using diagonal metric for NUTS.
This is the recommended verson of HMC.
Verbose name:  `sample_nuts`

```
posterior_sample = sample(model = None,
                          data = None,
                          ...)
```

Produce sample output using dense metric for NUTS.

```
posterior_sample = sample_nuts_dense(model = None,
                                     data = None,
                                     ...)
```

discussion points:  

In order to check that the set of draws returned by the sampler come from
the true posterior distribution, it is necessary to run multiple chains.
The `sample` command can run these chains in parallel or sequentially.

When all chains have completed without error, the output files need to be
combined into a single output.


##### optimize_lbfgs

Produce posterior mode estimate.  

```
posterior_mode = optimize_lbfgs(model = None,
                                data = None,
                                ...)
```

##### laplace_approximate_lbfgs

Produce posterior sample using Laplace approximation.  For now,
we'd have to follow R in using finite diffs on gradients to get
the Hessian, which we'd Cholesk decompose to do efficient generation
of approximate draws.

```
posterior_sample = laplace_approximate_lbfgs(model = None,
                                             data = None,
                                             ...)
```

##### vb_advi, vb_advi_dense

Produce posterior mean plus variance (covariance with dense).

```
approximate_posterior = vb_advi(model = None,
                                data = None,
                                ...)
approximate_posterior_dense = vb_advi_dense(model = None,
                                            data = None,
                                            ...)
```


##### vb_approximate_advi, vb_approximate_advi_dense
Produce posterior sample using variational approximation.

```
posterior_sample = vb_approximate_advi(model = None,
                                       data = None,
                                       ...)
posterior_sample = vb_approximate_advi_dense(model = None,
                                             data = None,
                                             ...)
```


##### extract

Extract a simple list of structured draws for the specified parameter.
This is harder to write than it looks.  It will collapse the draws
from multiple chains and then impose the structure.  We could have
this work for a single parameter (e.g., sigma[2,3]) or a simple
list of parameters, and it'd be a lot faster.

```
draws = extract(posterior_sample = None, parameter = None)
```

##### other services:  run_standalone_gqs

given set of draws and model with new generated quantities block, re-run gqs.
not yet available in cmdstan.



### POSTERIOR ANALYSIS

These functions belong in a separate package.
Included here because the
output from function `sample` is input to posterior analysis functions.
(Also `model` object?)

##### posterior_summary

Return structured report of posterior means, sd, mcmc std err,
quantiles, r-hat, n_eff.  The strucutre should be printable in
standard report form---that may require a different function---I
don't now how Python handles prints.

```
summary = posterior_summary(posterior_sample, quantiles = {0.1, 0.5, 0.9})
```

##### importance_sample

Return a summary including posterior means, posterior sd, and mcmc std
error based on Pareto-smoothed importance sampling.  This should help
adjust the approximations from Laplace or VB.

```
expectation_summary = importance_sample(model, posterior_sample)
```

