## Garch Modeling in BRMS

### Abstract

The student will implement common General Autoregressive Conditional Heteroskedasticity ([GARCH](https://vlab.stern.nyu.edu/docs/volatility)) style models for users in the [brms](https://cran.r-project.org/web/packages/brms/index.html) R package. The R package brms is a frontend for Stan that allows R users to write R formula syntax for models that is translated and compiled into a Stan model. Currently brms allows for [`arma`](https://github.com/paul-buerkner/brms/issues/708) style models on the mean, but does not support GARCH style models on the variance. The student will code up several of these models in Stan, testing with simulation based calibration that the models are well calibrated, write a technical document describing the GARCH model form and how it can be incorporated into brms, then implement these models directly into brms.

| **Intensity** | **Priority** | **Involves**  | **Mentors** |
| ------------- | ------------ | ------------- | ----------- |
| Medium | Low | R, Bayesian Modeling  |[Paul-Christian Bürkner](https://github.com/paul-buerkner), [Asael A Matamoros](https://github.com/asael697), [Steve Bronder](https://github.com/SteveBronder) |

### Project Details

An Autoregressive Moving Average model (ARMA) is of the form

![\Large Y_t = \sum_{i=1}^p\rho_i Y_{t-i} + \sum_{i=1}^q\theta_i \epsilon_{t-i}](https://latex.codecogs.com/svg.latex?Y_t&space;=&space;\sum_{i=1}^p\rho_i&space;Y_{t-i}&space;&plus;&space;\sum_{i=1}^q\theta_i&space;\epsilon_{t-i})

where
- `Y_t` is the series at time `t`,
- `p` and `\rho_i` is the number of autoregressive parameters and autoregressive parameters
- `q` and `\theta_i` is the number of moving average parameters and moving average parameters.
- `epsilon_t` is the error at time `t`

Currently, brms users are able to express autoregressive and moving average components of the mean of their model with syntax such as

```R
# Only auto regressive
y ~ ar(time | group, p = 1)
# Only moving average
y ~ ma(time | group, q = 1)
# Both
y ~ arma(time | group, p = 1, q = 1)
```

We would like to extend this functionality to support General Autoregressive Conditional Heteroskedasticity ([GARCH](https://vlab.stern.nyu.edu/docs/volatility)) style models which have the form

<img src="https://latex.codecogs.com/svg.latex?\small&space;\begin{align*}&space;y_t&\sim\mu_t&space;&plus;&space;\epsilon_t&space;\\&space;\epsilon_t&space;&\sim&space;\mathcal{N}{\left(0,\sigma_t^2\right)}&space;\\&space;\sigma_t^2&=\omega&space;&plus;&space;\sum_{i=1}^p&space;\beta_i\sigma_{t-i}^2&space;&plus;&space;\sum_{i=1}^q&space;\alpha_i\epsilon_{t-i}^2&space;\\&space;\end{align*}" title="\small \begin{align*} y_t&\sim\mu_t + \epsilon_t \\ \epsilon_t &\sim \mathcal{N}{\left(0,\sigma_t^2\right)} \\ \sigma_t^2&=\omega + \sum_{i=1}^p \beta_i\sigma_{t-i}^2 + \sum_{i=1}^q \alpha_i\epsilon_{t-i}^2 \\ \end{align*}" />

Where

- `y` is the series with mean `mu` and error `epsilon` at time `t`
- `epsilon` is normally distributed with mean 0 and variance `sigma_t^2` at time `t`
- `sigma_t^2` is modeled with
  - `p` autoregressive parameters `beta`
  - `q` moving average components `alpha`

As you can see, ARMA and GARCH are pretty similar! The fun starts happening when we are talking about real life modeling where it's very common to have very nasty tails on volatility models. Then we start building models such as asymmetric GARCH (AGARCH) models where one side of volatility leads to more conditional heteroskedasticity than the other.

<img src="https://latex.codecogs.com/svg.latex?\small&space;\sigma_t^2=\omega&space;&plus;&space;\sum_{i=1}^p&space;\beta_i\sigma_{t-i}^2&space;&plus;&space;\sum_{i=1}^q&space;\alpha_i(\epsilon_{t-i}&space;-&space;\gamma_i)^2&space;\\" title="\small \sigma_t^2=\omega + \sum_{i=1}^p \beta_i\sigma_{t-i}^2 + \sum_{i=1}^q \alpha_i(\epsilon_{t-i} - \gamma_i)^2 \\" />

Here, `gamma` acts like a weight that when positive amplifies the expected volatility if previous errors were negative.

Inside of brms it's possible to [model parameters]() and so for `sigma` we would like to allow syntax such as

```R
# Only autoregressive
sigma ~ ar(time | group, p = 1)
# Only moving average
sigma ~ ma(time | group, q = 1)
# Both autoregressive and moving average
sigma ~ garch(time | group, p = 1, q = 1)
# Asymmetric autoregressive
sigma ~ aar(time | group, q = 1)
# Asymmetric autoregressive and moving averag
sigma ~ agarch(time | group, p = 1, q = 1)
```



### Expected Results and Milestones

The expected result of this project is that brms users will have access to a simple way to incorporate standard volatility models into their overall model structure.

#### Milestone 1
Take models from [NYU Stern Volatility lab](https://vlab.stern.nyu.edu/docs/volatility) and write them in Stan along with data generating processes. Then use both of these to perform [Simulation Based Calibration](https://mc-stan.org/docs/2_23/stan-users-guide/simulation-based-calibration.html)

#### Milestone 2
Write tech spec as an issue in BRMS suggesting the syntax style, supported models, outstanding issues, any good default priors for the parameters that were found, etc. (Paul you'd probably need to lay out the template here).

#### Milestone 3
Make a prototype with tests, prediction methods, and docs for simple a simple `garch(p, q)` on sigma

#### Milestone 3
Add additional garch flavors such as GJR-GARCH, EGARCH, APARCH, AGARCH, etc.

### Helpful Prerequisite Experience

- Knowledge of the tools behind developing R packages
- Experience with Stan and Bayesian modeling
- Studies in time series and volatility modeling

### What Will You Learn?

By the end of the project students will have experience in R package development and working with a large, international open source development team, the algorithms behind volatility modeling, an understanding of the workflow in developing Bayesian models.

### What Can You do To Prepare?

It would be very good to read materials related to time series modeling with Bayesian Statistics [link](https://mc-stan.org/docs/2_20/stan-users-guide/time-series-chapter.html), be familiar with [Simulation Based Calibration](https://mc-stan.org/docs/2_23/stan-users-guide/simulation-based-calibration.html), and try some practice models in the Stan programming language.
