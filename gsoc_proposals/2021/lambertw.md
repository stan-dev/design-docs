## Lambert W Transforms

### Abstract

This project will add [Lambert-W transforms](https://discourse.mc-stan.org/t/adding-lambert-w-transforms-to-stan/13906) to the Stan language. Lambert-W transforms will allow users to center parameters in models whose data has skewness and asymmetric kurtosis.

| **Intensity**                          | **Priority**              | **Involves**  | **Mentors**              |
| -------------                          | ------------              | ------------- | -----------              |
| Hard | Low/Medium | Stan, R/Python, C++ |[Steve Bronder](https://github.com/SteveBronder), [Sean Pinkney](https://github.com/spinkney) |

### Project Details

Lambert-W transforms are a method for modeling skewness and asymmetric kurtosis in a distribution. For example, using the [`LambertW`]() R package it's possible to gaussianize a cauchy distribution such that after the Lambert-W tranform the data is normally distributed.

```R
# Univariate example
library(LambertW)
set.seed(20)
y1 <- rcauchy(n = 100)
plot(density(y1))
out <- Gaussianize(y1, return.tau.mat = TRUE)
plot(density(out$input) # huh!
x1 <- get_input(y1, c(out$tau.mat[, 1]))  # same as out$input
test_normality(out$input) # Gaussianized a Cauchy!
```

![](https://aws1.discourse-cdn.com/standard14/uploads/mc_stan/original/2X/6/6f039d1b23ce1ed4d75036bce63e374b0cb4cfdf.png)

Lambert-W transforms can be estimated by either maximum likelihood estimation or moment matching and discussion is ongoing as to which will be better for the Stan language. Ideally the student would implement both, compare the outcomes and code complexity, and provide recommendations on when each approach is suitable. 

The maximum likelihood approach can directly be ported to the Stan language to utilize MCMC methods instead of MLE. The issue with this approach is that one must specify the original distribution in which the transformation applies and each distribution will need its own specialization. The upside, however, is that this is the most efficient - in terms of parameter accuracy. 

The second way of estimating the distribution is by moment matching. In fact, TF does this with their [`gaussianize`](https://www.tensorflow.org/tfx/transform/api_docs/python/tft/scale_to_gaussian) function. TF bases their code on the [Characterizing Tukey h and hh-Distributions through L-Moments and the L-Correlation](https://opensiuc.lib.siu.edu/cgi/viewcontent.cgi?article=1005&context=epse_pubs) by Headrick and Pant. The TF code uses [binary search](https://github.com/tensorflow/transform/blob/879f2345dcd6096104ae66027feacb099e228e66/tensorflow_transform/gaussianization.py) to numerically solve for the left and right parameters when the distribution is asymmetric.

With the L-moments method it is possible to write a tukey_symmetric_lpdf and tukey_skew_lpdf that Stan samples from on the normal 0,1 scale. Along with estimating the location and scale, the symmetric versions would take in `h` and the skew versions an `h_l` and `h_r` as parameters. An ambitious student can also implement the multivariate version - something TF does not currently do - by a multi_tukey specification. Each marginal density would contain its own skew and/or kurtosis, connected via a correlation matrix. See equation 4.1 in the paper that uses the Cholesky factor of the correlation matrix values.

### Expected Results and Milestones

By the end of the project users will be able to utilize Lambert-W distributions inside of their Stan models.

#### Milestone 1

Implement the MLE version of Lambert-W transforms directly as a function written in the Stan language along with data generating processes. Then use both of these to perform [Simulation Based Calibration](https://mc-stan.org/docs/2_23/stan-users-guide/simulation-based-calibration.html) to verify the correctness of the model.

#### Milestone 2

1. Work with Stan developers to make a prototype of the MLE version of the Lambert-W transforms in C++. 
2. In parallel, begin work on the moment-matching estimator in the Stan language.

#### Milestone 3

1. Add the MLE prototype to the [Stan Math library](https://github.com/stan-dev/math). 
2. Compare the moment-matching estimator to the model(s) and SBC implemented in milestone 1.

#### Extra Credit 
1. Implementation of the moment-matching code in C++.
2. Super extra credit. Add the multivariate extension.

### Helpful Prerequisite Experience

The student should have some familiarity or be able to learn

- Stan
- C++
- Bayesian Modeling


### What Will You Learn?

By the end of the summer, the student will have experience with:
 - Bayesian modeling/computing.
 - Writing performant C++
 - Working in a large, international open-source development team.
 - Algorithm development

### What Can You do To Prepare?

Students should read over the [original paper](https://www.hindawi.com/journals/tswj/2015/909231/) on Lambert-W transforms as well as the associated R package [LambertW](https://cran.r-project.org/web/packages/LambertW/index.html).
