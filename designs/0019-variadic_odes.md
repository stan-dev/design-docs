- Feature Name: Variadic arguments for ODE solvers
- Start Date: 2020-04-20
- RFC PR: 19
- Stan Issue:

# Summary
[summary]: #summary

This proposal is to make a set of ODE solvers that take a variadic list of
arguments.

# Motivation
[motivation]: #motivation

The goal is to avoid the argument packing and unpacking that the current solvers
depend on.

Argument packing is inconvenient, makes code hard to read, and introduces a lot
of possible errors.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

For the bdf solver, I am proposing introducing two new functions: `ode_bdf` and
`ode_tol_bdf` (there will be two functions similarly introduced for the rk45 and
adams solvers).

The first is a BDF solver with default tolerance settings, and the second
requires the tolerances to be set manually. This is different from the current
solvers where tolerances are presented as overloads to the same function name.
With the variadic argument this isn't possible anymore so the function with
tolerances is broken out separately. The difference between `ode_bdf` and
`ode_bdf_tol` is described later. For now, just focus on `ode_bdf` (where
there are no tolerance arguments).

The proposed `ode_bdf` interface is:
```
vector[] ode_bdf(F f,
                 vector y0,
                 real t0, vector times,
                 T1 arg1, T2 arg2, ...)
```

The arguments are:
1. ```f``` - User-defined right hand side of the ODE (`dy/dt = f`)
2. ```y0``` - Initial state of the ode solve (`y0 = y(t0)`)
3. ```t0``` - Initial time of the ode solve
4. ```times``` - Sequences of times to which the ode will be solved (each
  element must be greater than t0).
5. ```arg1, arg2, ...``` - Arguments passed unmodified to the ODE right hand
  side (`f`). Can be any non-function type.

In this proposal, the user-defined ODE right hand side interface is:

```
vector f(real t, vector y, T1 arg1, T2 arg2, ...)
```

The arguments are:
1. ```t``` - Time at which to evaluate the ODE right hand side
2. ```y``` - State a which to evaluate the ODE right hand side
3. ```arg1, arg2, ...``` - Arguments pass unmodified from the `ode_bdf` call.
  The types `T1`, `T2`, etc. need to match between this function and the
  `ode_bdf` call.

A call to `ode_bdf` returns the solution of the ODE specified by the right hand
side (`f`) and the initial conditions (`y0` and `t0`) at the time points given
by the `times` argument. The solution is given by an array of vectors.

The proposed `ode_bdf_tol` interface is:
```
vector[] ode_bdf_tol(F f,
                     vector y0,
                     real t0, vector times,
                     real rel_tol, real abs_tol,
		     int max_num_steps,
                     T1 arg1, T2 arg2, ...)
```

The arguments are:
1. ```f``` - User-defined right hand side of the ODE (`dy/dt = f`)
2. ```y0``` - Initial state of the ode solve (`y0 = y(t0)`)
3. ```t0``` - Initial time of the ode solve
4. ```times``` - Sequences of times to which the ode will be solved (each
  element must be greater than t0).
5. ```rel_tol``` - Relative tolerance for solve (data)
6. ```abs_tol``` - Absolute tolerance for solve (data)
7. ```max_num_steps``` - Maximum number of timesteps to take in the solve (data)
5. ```arg1, arg2, ...``` - Arguments passed unmodified to the ODE right hand
  side (`f`). Can be any non-function type.

There is no way to optionally only provide some of the `rel_tol`, `abs_tol`, or
`max_num_steps` arguments. We can keep the current defaults (`1e-6`, `1e-6`,
`1e6`) for `ode_bdf`. 

There are a few changes from the previous implementation.

1. `theta`, `x_real`, and `x_int` are no longer broken out. All parameters,
real data, and integer data should be passed through as a trailing argument
(with no rules on naming).
2. The state is written in terms of `vector`s instead of real arrays. ODE states
are mathematically written and expressed as vectors, so given the interface is
changing we might as well change this to be consistent.
3. I shorted the arguments `initial_state` and `initial_time` to `y0` and `t0`.
These are standard ways to refer to these quantities.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The implementation of these features is relatively straightforward given the
code from the
[reduce_sum](https://github.com/stan-dev/design-docs/blob/master/designs/0017-reduce_sum.md)
design doc and the existing ODE infrastructure. There is not any significant new
technology needed.

The old `integrate_ode_bdf`, `integrate_ode_adams`, and `integrate_ode_rk45`
functions should be deprecated with the introduction of these new functions.

They can remain in the code to provide compatibility to models written with the
old interfaces. These functions can all be written to wrap around the new
interfaces so there will not be much technical debt accrued maintaining them.

# Drawbacks
[drawbacks]: #drawbacks

I guess a drawback is that we should update as much of the existing ODE
documentation we can to point at the new interfaces. The old interfaces could
remain for backwards compatibility though, so if we miss anything it is okay.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The most obvious alternatives are:

* Do nothing (technically everything done here could be done in the old
interfaces).

I believe the current interface is difficult to use and should be replaced
as soon as we can.

* Change the scope of the functions block to include variables defined in
the `data`, `transformed data`, `parameters`, and `transformed parameters`
block.

I'm not opposed to this, but there hasn't been any discussion of it and it is
probably harder than the proposal here. This also isn't incompatible with the
current proposal, though it would probably require some extra work.

* Wait until closures are available so that the ODE right hand side can be
defined by a closure (which would then have the scope to use any variable
that could otherwise be passed to through as a right hand side argument here).

I'm not opposed to this either, and this also isn't incompatible with the
current proposal, though it would probably require some extra work.

# Prior art
[prior-art]: #prior-art

This builds directly on the existing ODE solver interfaces. This sort of
pass-along-the-arguments thing is more necessary for Stan than other languages
because in other languages it is easier to take advantage of function scope
to access external variables.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

I think we should change ODE state to be a vector.

I'm not convinced time should be a vector though. It seems like for convenience
we'd make it a vector argument (so it wasn't like one argument of `ode_bdf`
needs to be a vector and one doesn't). However, then it seems like the output
of `ode_bdf` would be a matrix. I think the output makes more sense as an array
of vectors.
