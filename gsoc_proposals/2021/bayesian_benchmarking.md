## Bayesian Benchmarking 

### Abstract
The project aims to develop a suite of models for benchmarking Bayesian computation. In concert with the mentors, the student will gather data/models with a variety of inferential structure for coding and optimization in Stan. The resulting canonical models and posteriors will be submitted for inclusion in the posteriorDB database to serve as reference points against which new approaches to Bayesian computation can be compared. 


| **Intensity**                          | **Priority**              | **Involves**  | **Mentors**              |
| -------------                          | ------------              | ------------- | -----------              |
| Easy/Moderate | Low | Stan; Bayesian modeling | Andrew Gelman, [Måns Magnusson](https://github.com/MansMeg), [Mike Lawrence](https://github.com/mike-lawrence)   |

### Project Details

The goal of this project is to set up a set of posteriors that will be useful as benchmarks. We are especially interested in more complex posteriors that will push Bayesian computations further.

#### Use Cases of benchmark set of models
The purpose or use cases for such a set of benchmark models are:
Testing implementations of inference algorithms with asymptotic bias (such as variational inference)
Testing implementations of inference algorithms with asymptotically decreasing bias and variance (such as MCMC)
Efficiency comparisons of inference algorithms with asymptotically decreasing bias and variance
Exploratory analysis of algorithms
Testing out new algorithms on interesting models

The project will consist of identifying relevant models to include in a set of benchmarks, implementing them in Stan together with data, and then optimizing these Stan programs with respect to performance.


### Expected Results and Milestones
By the end of the project the student will have implemented a number of models from a diverse set of use cases, optimized for performance. 

#### Milestone 1
Identify models that would be of relevance to include as benchmark models.

#### Milestone 2
Implement all models in Stan and add them to posteriorDB.

#### Milestone 3
Optimize the models for performance

### Helpful Prerequisite Experience
Some knowledge about Bayesian statistics and computation.

### What Will You Learn?
By the end of the summer, the student will have experience with using probabilistic programming languages for a wide array of posteriors and how these type of models can be optimized.

### What Can You Do To Prepare?

You can read up on [Stan](https://mc-Stan.org), [Bayesian workflows](https://betanalpha.github.io/assets/case_studies/principled_bayesian_workflow.html) and [posteriorDB](https://github.com/stan-dev/posteriordb).