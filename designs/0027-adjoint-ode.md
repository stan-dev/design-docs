- Feature Name: ode-adjoint
- Start Date: 2021-02-02
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Ordinary differential equations (ODEs) are currently severly costly to
fit in Stan for larger systems. This is due to the multiplicative
scaling of the required computing ressources with the ODE system size
N and the number of parameters M defining the ODE. Currently we
implement in Stan the so-called forward-mode ODE method in order to
obtain in addition to the solution of the ODE the sensitivities of the
ODE. The cost of this method scales as 

$$ N \cdot M . $$

The computational cost of the adjoint method is much more favorable
in comparison which is

$$ 2 \cdot N + M .$$

The advantage of the adjoint methods shows in particular whenever the
number of parameters are relatively large in comparison to the number
of states. Most importantly, the computational cost grows only
linearly in the number of states and parameters (while forward grows
exponentially). Thus, this method can scale to much larger problems
without exponentially increasing computational cost.

# Motivation
[motivation]: #motivation

Stan is currently practically limited to solve problems with ODEs
which are small in the number of states and parameters. If either of
them gets large, the computational cost explodes quickly. With the
adjoint ODE solving method Stan will be able to scale to much larger
problems involving more states and more parameters. Examples are large
pharmacokinetic / pharmacodynamic systems or physiological based
pharmacokinetic models or bigger susceptible infectious & removed
models. The adjoint ODE method will grow the computational cost only
linearly with states and parameters and therefore the modelers can
more freely increase the complexity of the ODE model without having to
worry too much about infeasible inference times.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The new solver `ode_adjoint` will follow in it's design the variadic
ODE functions. As the new solver is numerically more involved (see
reference level) there are merely more tuning parameters needed for
the solver. The actual impementation will be provided by the CVODES
package which we already include in Stan.

From a more internal stan math perspective, the key difference to the
existing forward mode solvers will be that the gradients are not any
more precomputed during the forward sweep of reverse mode autodiff
(AD). Instead, during the forward sweep of reverse mode autodiff, the
ODE is solved only for the N states (without any sensitivities). When
reverse mode AD then performs the backward sweep, the adjoints of the
input operands are directly computed given the input adjoints. This
involves a backward solve in time with N states and solving $M$
quadrature problems in addition.

The numerical complexity is higher for the adjoint method in
comparison to the forward method. While most of the complexity is
handled by CVODES, the numerical procedure seems to require more
knowledge about the tuning parameters. At least at the moment it
appears not possible to make an easy to use interface of this
functionality available without most tuning parameters. We need to
first collect some experience before a simpler version can be made
available (if that is feasible at all). The tuning parameters exposed
as proposed are:

- absolute & relative tolerance forward solve; absolute tolerance
  should be a vector of length N, the number of states
- absolute & relative tolerance backward solve
- absolute & relative tolerance quadrature problem
- forward solver: bdf-dense / bdf-iterated / adams - 1 / 2 / 3
- backward solver: bdf-dense / bdf-iterated / adams - 1 / 2 / 3
- checkpointing: number of checkpoints every X steps
- checkpointing: hermite or polynomial approximation - 1 / 2

During an experimental phase of this feature we can hopefully learn
which of these are relevant and which can be dropped for a final
release of the `ode_adjoint` function.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The adjoint method for ODEs is relatively involved mathematically. The
main challenge comes from a mix of different notation and conventions
used in different fields. Here we relate commonly used notation within
Stan math to the [user guide of
CVODES](https://computing.llnl.gov/sites/default/files/public/cvs_guide-5.6.1.pdf),
the underlying library we employ to handle the numerical
solution. The goal of reverse mode autodiff is to calculate the
derivative of some function $l(\theta)$ wrt. to it's parameters
$\theta$ at some particular realization of $\theta$. The function $l$
now depends on the solution of an ODE given as initial value problem

\begin{align}
\dot{y} &= f(y,t,p) (\#eq:odeDef) \\
 y(t_0) &= y^{(0)}. (\#eq:odeInitial)
\end{align}

The ODE has $N$ states, $y=(y_1, \ldots, y_N)$, and is
parametrized in terms of parameters $p$ which are a subset of
$\theta$. Let's now further assume for simplicity that the function
$l$ only depends on the solution of the ODE at the time-point
$T$. During the reverse sweep of reverse mode autodiff we are then
given the adjoints of $a_{l,y_n}$ wrt to the output state $y(T,p)$ which
are the partials of $l$ wrt to each state

$$ a_{l,y_n} = \left.\frac{\partial l}{\partial y_n}\right|_{t=T} $$

and we must calculate the contribution to the adjoint of the parameters

$$ a_{l,p_m} = \sum_{n=1}^{N} \left. a_{l,y_n} \,  \frac{\partial y_n}{\partial p_m}\right|_{t=T}, $$

which involves for each parameter $p_m$ the partial of every state
$y_n$ wrt to the parameter $p_m$. Note that the computational benefit of the
adjoint method stems from calculating the above sums *directly* in
contrast to the forward method which calculates every partial
$\left. \frac{\partial y_n}{\partial p_m}\right|_{t=T}$ separatley.

In the notation of the CVODES user manual, the function $g(t,y,p)$
**is equal to** $l(\theta)$ essentially. Through the use of Lagrange
multipliers, the adjoint problem is transferred to a backward problem
in equation 2.20 of the CVODES manual ([see here for a step-by-step
derivation](https://arxiv.org/abs/2002.00326)),

\begin{align}
\dot{\lambda} &= - \left(\frac{\partial f}{\partial y}\right)^*
\lambda - \left(\frac{\partial g}{\partial y}\right)^* (\#eq:lambdaOde) \\
 \lambda(T) &= 0. (\#eq:lambdaInitial)
\end{align}

This ODE is referred to as the *backward* problem, since we fix the
solution $\lambda$ at the final end-point $T$ instead of the initial
condition at $t_0$ (it's a terminal value problem rather than an
initial value problem). The CVODES manual then proceeds with deriving
that

\begin{equation}
\left.\frac{d g}{d p}\right|_{t=T} = \mu^*(t_0) \, s(t_0) +
\left.\frac{\partial g}{\partial p}\right|_{t=T} + \int_{t_0}^{T}
\mu^* \, \frac{\partial f}{\partial p} \, dt.
(\#eq:derivg)
\end{equation}

Here $s(t_0)$ is the state sensitivity wrt to the parameters at the
initial time-point. The term $\left.\frac{\partial g}{\partial
p}\right|_{t=T}$ is the partial derivative wrt to the parameters of
$g(t,y,p)$. This term is determined by the terms in $g(t,y,p)$ which directly
depend on the parameters and not implicitly due to the parameters
affecting the ODE state. Thus, this term is being computed by the
autodiff system of stan-math itself as part of the adjoints of the
parameters, $a_{l,p_m}$. Finally, $\mu = \frac{d \lambda}{d T}$ such
that $\mu$ is obtained by the equivalent backward problem (taking the
total derivative of $\dot{\lambda}$ in \@ref(eq:lambdaOde) wrt to $T$)

\begin{align}
\dot{\mu} &= - \left(\frac{\partial f}{\partial y}\right)^* \, \mu
(\#eq:muODE) \\
\mu(T) &= \left(\frac{\partial g}{\partial y}\right)^*_{t=T}. (\#eq:muInitial)
\end{align}

If we now recall that $g(t,y,p)$ is equal to the function $l(\theta)$
being subject to autodiff we see that

$$\left(\frac{\partial g}{\partial y_n}\right)^*_{t=T} = a_{l,y_n}^*, $$

which is the input we get during reverse mode autodiff (the conjugate
transpose does not apply for Stan math using reals only).

It is important to note that the backward ODE problem requires as
input the adjoint $a_{l,y_n}^*$ such that the backward problem must be
solved during the reverse pass of reverse mode autodiff. Thus, CVODES
is used during the forward pass to *solve (forward)* the ODE in
\@ref(eq:odeDef). Once the backward pass is initiated, the adjoints
$a_{l,y_n}^*$ are used as the terminal value in order to solve the
*backward problem* of \@ref(eq:muODE). Whenever any parameter
sensitivities are requested, then we must solve along the backward
problem an additional quadrature problem, which is the integrand in
equation \@ref(eq:derivg).

So far we have only considered the case of a single time-point
$T$. For multiple time-points one merely starts the backward
integration from the last time-point and keeps accumulating the
respective terms which result from integrating backwards in steps
until $t_0$ is reached.

In total we need to solve 3 integration problems which consist of a
forward ODE problem, a backward ODE problem and a backward quadrature
problem. The forward ODE and the backward ODE problem can be solved
with either a non-stiff Adams or a stiff BDF solver of CVODES (the
choice is independent for each problem). For the Newton steps of the
BDF routine a linear solver routine is required. The routine can
either be a dense solver or an approximate iterative solver. As we
target large ODE systems it can be useful to allow users to choose the
solver being used. For example, whenever the number of ODE states is
very large, then an iterative solver may be preferable. The reason is
that the dense solver will require the calculation of the full
Jacobian $\frac{df}{dy}$ of the ODE RHS in \@ref(eq:odeDef) wrt to the
states $y$. In contrast, the iterative solver only needs to evaluate
Jacobian-vector products $\frac{df}{dy}\,v$, which we can compute
directly using *forward mode*. In addition all 3 integration problems
have their own relative and absolute tolerance targets.



The proposed function should has the following signature:

```stan
vector[] ode_adjoint_tol_ctl(F f,
    vector y0,
    real t0, real[] times,
    real rel_tol_f, vector abs_tol_f,
    real rel_tol_b, vector abs_tol_b,
    real rel_tol_q, real abs_tol_q,
    int max_num_steps,
    int num_checkpoints,
    int interpolation_polynomial,
    int solver_f, int solver_b
    T1 arg1, T2 arg2, ...)
```

The arguments are:  
1. ```f``` - User-defined right hand side of the ODE (`dy/dt = f`)  
2. ```y0``` - Initial state of the ode solve (`y0 = y(t0)`)  
3. ```t0``` - Initial time of the ode solve  
4. ```times``` - Sorted arary of times to which the ode will be solved (each
  element must be greater than t0)  
5. ```rel_tol_f``` - Relative tolerance for forward solve (data)  
6. ```abs_tol_f``` - Absolute tolerance vector for each state for
   forward solve (data)  
7. ```rel_tol_b``` - Relative tolerance for backward solve (data)  
8. ```abs_tol_b``` - Absolute tolerance vector for each state backward solve (data)  
9. ```rel_tol_q``` - Relative tolerance for backward quadrature (data)  
10. ```abs_tol_q``` - Absolute tolerance for backward quadrature (data)  
11. ```max_num_steps``` - Maximum number of timesteps to take in integrating
  the ODE solution between output time points for forward and backward
  solve (data)  
12. ```num_checkpoints``` number of steps between checkpointing forward
    solution (data)  
13. ```interpolation_polynomial``` can be 1 for hermite or 2 for
    polynomial interpolation method of CVODES  
14. ```solver_f``` solver used for forward ODE problem: 1=Adams,
    2=bdf, 3=bdf_iterated  
15. ```solver_b``` solver used for backward ODE problem: 1=Adams,
    2=bdf, 3=bdf_iterated  
16. ```arg1, arg2, ...``` - Arguments passed unmodified to the ODE right
hand side. The types ```T1, T2, ...``` can be any type, but they must match
the types of the matching arguments of ```f```.

In addition a function version is made available which mimics the
existing ode interface for tolerances. This version will allow users
to quickly try out the new adjoint interface. **The extra control
parameters will be set based on best guesses as of now and are subject
to change**:


```stan
vector[] ode_adjoint_tol(F f,
    vector y0,
    real t0, real[] times,
    real rel_tol, real abs_tol,
    int max_num_steps,
    T1 arg1, T2 arg2, ...)
```

The arguments are:  
1. ```f``` - User-defined right hand side of the ODE (`dy/dt = f`)  
2. ```y0``` - Initial state of the ode solve (`y0 = y(t0)`)  
3. ```t0``` - Initial time of the ode solve  
4. ```times``` - Sorted arary of times to which the ode will be solved (each
  element must be greater than t0)  
5. ```rel_tol``` - Relative tolerance for all solves (data)  
6. ```abs_tol``` - Absolute tolerance for all solves (data)  
7. ```max_num_steps``` - Maximum number of timesteps to take in integrating
  the ODE solution between output time points for forward and backward
  solve (data)  
8. ```arg1, arg2, ...``` - Arguments passed unmodified to the ODE right
hand side. The types ```T1, T2, ...``` can be any type, but they must match
the types of the matching arguments of ```f```.


# Drawbacks
[drawbacks]: #drawbacks

It's some work to be done. Other than that there are no alternatives
to my knowledge to get large ODE systems working in Stan. What we are
missing out for now is to exploit the sparsity structure of the
ODE. This would allow for more efficient solvers and even larger
systems, but this is not possible at the moment to figure out
structurally the inter-dependencies of inputs and outputs. However,
the matrix free bdf method may already take advantage sufficiently
enough of the sparsity, since in this case we avoid evaluation of the
full Jacobian to some extent.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

There is no other analytical technique available which scales in a
comparable way. Hence, larger ODE problems ( many parameters and/or
states) are currently out of scope for Stan and the adjoint technique
does enable Stan to cope with these larger systems.

The numerical complexities are rather involved as 3 nested
integrations are performed. This makes things somewhat fragile and
less robust. What makes the backward integration in
particular involved is that the solution of the forward problem must
be stored as a continuous function in memory and hence an
interpolation of the forward solve is required. This is provided by
CVODES via a checkpointing procedure. In summary, we do heavily rely
on CVODES infrastructure as these building blocks are rather complex
and heavy to craft on our own.

# Prior art
[prior-art]: #prior-art

The adjoint sensitivity method is not very widley used. It's somewhat
present in engineering literature and found it's way into packages
like `DifferentialEquations.jl` in Julia. Another noticeable reference
is [FATODE](https://www.mcs.anl.gov/~hongzh/publication/zhang-2014/SISC_FATODE_final.pdf)
and a [discourse post from Ben](https://discourse.mc-stan.org/t/on-adjoint-sensitivity-of-ode-pde/5148/16).

Another domain where the adjoint sensitivity method is beind used is
in systems biology. The [AMICI](https://github.com/AMICI-dev/AMICI)
toolkit has been build to solve ODE system for large scale systems
biology equation systems to be used within optimizer software. The
adjoint method is implemented in AMICI using CVODES and has been
benchmarked on various problems from systems biology as
[published](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1005331)
(see also [this arxiv pre-print](https://arxiv.org/abs/2012.09122)).

Discuss prior art, both the good and the bad, in relation to this proposal.
A few examples of what this can include are:


# Unresolved questions
[unresolved-questions]: #unresolved-questions

The main unresolved question at this point is to settle on the set of
exposed tuning parameters. Currently the proposal is to expose in an
experimental version a large super-set of tuning parameters and ask
the Stan community to experiment with it in order to weed out some
tuning parameters if possible.
