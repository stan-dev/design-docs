- Feature Name: interpolation
- Start Date: 2020-03-31
- RFC PR: 
- Stan Issue: 

# Summary
[summary]: #summary

In this pull request <https://github.com/stan-dev/math/pull/1814>
I added a function that does interpolation of a set of function values, 
(x_i, y_i), specified by the user. The algorithm works by first doing a 
linear interpolation between points and then smoothing that linear 
interpolation by convolution with a Gaussian.

There are a number of design choices to be made in this project and I 
have discussed some of these with @bbbales2 but we wanted to get a wide
range of opinions on this. 

# Motivation
[motivation]: #motivation

The need for an interpolation scheme has come up several times on
discourse and in math issues:

https://github.com/stan-dev/stan/issues/1165

https://github.com/stan-dev/math/issues/58

https://discourse.mc-stan.org/t/vectors-arrays-interpolation-other-things/10253


# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

We've introduced a function that does interpolation by first doing 
linear interpolation and then smoothing the resulting function by
convolving with a Gaussian. Interpolation of a Gaussian with a 
line is can be evaluated analytically aside from a call to 
an error function and the derivative of the convolution is analytic.

The file `stan/math/prim/fun/conv_gaus_line.hpp` contains the 
function that evaluates the convolution of a line with a gaussian
and also its derivative. 

The file `stan/math/rev/fun/conv_gaus_line.hpp` contains the implementation
of its derivative in reverse mode autodiff. 

The file `stan/math/prim/fun/gaus_interp.hpp` contains the main interpolation
function: 

`gaus_interp` 

which takes as input a function tabulated at (xs[i], ys[i]) and returns a 
std::vector with the interpolated function at inputted points. 

----------

Here is one possibility for how this would look in a Stan program:

In this example we're solving the ODE

`f'(x) = g(x) * f(x)`

where `g` is some unknown function that we have tabulated at a set of points. 
In order to solve the above ODE, we will need to evaluate `g` in 
between points where we have `g` tabulated. Here are two possible Stan programs for 
doing this interpolation, in one case with a linear interpolation and in the other 
a smooth interpolation.

Linear interpolation Stan program:

The new function `lin_interp(xs, ys, t)` takes as input a function tabulated 
at the points `(xs[i], ys[i])` and evaluates the linear interpolation at `t`.

```
functions {
  real[] dz_dt(real t, real[] z, real[] theta,
             real[] x_r, int[] x_i) {
      int n = x_i[1];
      return { lin_interp(x_r[1 : n], x_r[n + 1 : 2 * n], t) * z[1] };
    }
}

data {
  int N;
  int n_interp;
  real ts[N];
  real xs[n_interp];
  real ys[n_interp];
}

transformed data {
  int x_i[1] = {n_interp};
  real x_r[2 * n_interp];
  x_r[1 : n_interp] = xs
  x_r[n_interp + 1 : 2 * n_interp] = ys
}

transformed parameters {
  real z_init[1] = {1.0};
  real theta[1] = {0.0};
  real z[N, 1]
    = integrate_ode_rk45(dz_dt, z_init, 0, ts, theta,
                         x_r, x_i, 1e-10, 1e-10, 1e3);
}
```

Smooth interpolation:

With this interpolation, the function `precomp_gaus_interp(xs, ys)` called in 
"Transformed Data" takes as input a function tabulated at the points `(xs[i], ys[i])` 
and computes certain parameters of the smooth interpolation that will be used later on. 
Those parameters are returned in the vector `x_r` and passed to `gaus_interp`.

```
functions {
  real[] dz_dt(real t, real[] z, real[] theta,
             real[] x_r, int[] x_i) {
      return { gaus_interp(x_r, t) * z[1] };
    }
}

data {
  int N;
  int n_interp;
  real t0;
  real xs[N];
  real ys[N];
}

transformed data {
  real x_r[3 * n_interp + 1];
  x_r = precomp_gaus_interp(xs, ys); 
}

transformed parameters {
  real z_init[1] = {1.0};
  real theta[1] = {0.0};
  real z[N, 1]
    = integrate_ode_rk45(dz_dt, z_init, 0, ts, theta,
                         x_r, x_i, 1e-10, 1e-10, 1e3);
}
```


# Drawbacks
[drawbacks]: #drawbacks

There are many types of interpolation schemes that could be more useful 
depending on how users would be using this interpolation. It's not clear 
to me what is needed by users or how users would use this interpolation 
feature.

This function has a smoothing factor that is calculated based on the minimum
distance between successive points. This can lead to potentially undesired 
behavior. For example, it might only slightly smooth. As of now, the user
doesn't have control over this.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

This interpolation scheme has the advantage that the interpolated
function and its derivative are easy to evaluate. Another benefit is that the 
algorithm is fast and the interpolation goes through the user-specified
points. 

Cubic splines is an alternative. The downside is that sometimes the 
interpolated function acts in undesired ways between interpolation points. 

There are schemes like interpolation using Chebyshev polynomials, but 
these will either be very oscilitory between points or they will
not go through the interpolation points.

# Prior art
[prior-art]: #prior-art

Ben Goodrich has pointed out that Boost is coming out with new 
interpolation schemes in an upcoming release.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Is this the sort of interpolation that is useful to users? 
- Which interpolation-related functions should be exposed?
- How should functions be organized? Which functions in which files? 
