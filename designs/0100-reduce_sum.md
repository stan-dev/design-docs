- Feature Name: Reduce Sum Parallelization
- Start Date: 2020-03-10
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

The reduce_sum function is an attempt to add a parallelization utility that is much easier to use than map-rect without requiring a substantial changes to the autodiff stack.

# Motivation
[motivation]: #motivation

The overall goal of reduce_sum is to make it easier for users to parallelize their models by streamlining how arguments are handled, hiding work scheduling, and making it more difficult to program something that will accidentally be inefficient.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

reduce_sum is effectively a parallel-for combined with a sum.

For a set of input arguments, ```args0, args1, args2, ...``` and a scalar function ```f```, reduce_sum computes the scalar:

```f(args0) + f(args1) + f(args2) + ...```

In terms of probabilistic models, this is useful when there are N terms in a likelihood that combine multiplicatively. In this case, computing the log likelihood means computing the sum of the log of each of these terms. If a function ```f``` can be written that computes an individual log likelihood, then reduce_sum can be used to compute them all in parallel and accumulate the results.

The actual meaning of N is flexible here. In a regression model, N might be the N different rows of the input dataframe, each which can be evaluated separately. In a hierarchical model, N might correspond to different groups -- perhaps there is some complex shared calculation for each group but these can all be done in parallel.

reduce_sum is not useful, however, when there are dependencies between these likelihood terms. This can happen, for instance, if there were N terms in a Gaussian process likelihood. reduce_sum will not be useful for accelerating this.

The signature we settled on for reduce_sum (which balances the different tradeoffs described in the Summary) is:

```
real reduce_sum(F func, T[] sliced_arg, int grainsize, T1 arg1, T2 arg2, ...)
```

where the function ```func``` has a signature like:

```
real func(int start, int end, T[] sliced_arg, T1 arg1, T2 arg2, ...)
```

The array ```sliced_arg``` in each case represents the list of calculations to perform and sum. The user-provided function ```func``` is expect to compute the ```start``` through ```end``` terms of the overall sum, accumulate them, and return that value. The trailing arguments ```argN``` are passed without modification to every call of ```func```.

An overall call to ```reduce_sum``` can be replaced by either:

```
real sum = func(1, size(sliced_arg), sliced_arg, arg1, arg2, ...)
```

or (modulo differences due to rearrangements of summations) the code:

```
real sum = 0.0;
for(i in 1:size(sliced_arg)) {
  sum = sum + func(i, i, { sliced_arg[i] }, arg1, arg2, ...);
}
```

The argument ```sliced_arg``` is called the sliced argument because func only receives the elements of ```sliced_arg``` for which it is responsible. All the other ```argN``` arguments are shared completely between every call to func.

By requiring that the user provided function perform the calculation over a range of inputs, it is possible for the scheduler to lump smaller pieces of work together into big ones (and increase efficiency). This is done by adjusting the ```grainsize``` argument. The scheduler will try to cut up the N parallel terms into groups of size grainsize.

As an example, the hierarchical model code:
```
vector[N_subset] mu = temp_Intercept + Xc[1:N_subset] * b;
for (n in 1:N_subset) {
  mu[n] += r_1_1[J_1[n]] * Z_1_1[n] + r_1_2[J_1[n]] * Z_1_2[n] +
    r_2_1[J_2[n]] * Z_2_1[n] +
    r_3_1[J_3[n]] * Z_3_1[n] + r_3_2[J_3[n]] * Z_3_2[n] +
    r_4_1[J_4[n]] * Z_4_1[n] +
    r_5_1[J_5[n]] * Z_5_1[n] +
    r_6_1[J_6[n]] * Z_6_1[n] + r_6_2[J_6[n]] * Z_6_2[n] +
    r_7_1[J_7[n]] * Z_7_1[n] + r_7_2[J_7[n]] * Z_7_2[n] +
    r_8_1[J_8[n]] * Z_8_1[n] +
    r_9_1[J_9[n]] * Z_9_1[n] +
    r_10_1[J_10[n]] * Z_10_1[n] +
    r_11_1[J_11[n]] * Z_11_1[n] + r_11_2[J_11[n]] * Z_11_2[n];
}
target += binomial_logit_lpmf(Y[1:N_subset] | trials[1:N_subset], mu);
```

can be replaced with a function for computing the partial sums:
```
real parallel(int start, int end, int[] Y, int[] trials,
              real temp_Intercept, matrix Xc, vector b,
              vector r_1_1, int[] J_1, vector Z_1_1, vector r_1_2, vector Z_1_2,
              vector r_2_1, int[] J_2, vector Z_2_1,
              vector r_3_1, int[] J_3, vector Z_3_1, vector r_3_2, vector Z_3_2,
              vector r_4_1, int[] J_4, vector Z_4_1,
              vector r_5_1, int[] J_5, vector Z_5_1,
              vector r_6_1, int[] J_6, vector Z_6_1, vector r_6_2, vector Z_6_2,
              vector r_7_1, int[] J_7, vector Z_7_1, vector r_7_2, vector Z_7_2,
              vector r_8_1, int[] J_8, vector Z_8_1,
              vector r_9_1, int[] J_9, vector Z_9_1,
              vector r_10_1, int[] J_10, vector Z_10_1,
              vector r_11_1, int[] J_11, vector Z_11_1, vector r_11_2, vector Z_11_2) {
  int N = size(Y);
  vector[N] mu = temp_Intercept + Xc[start:end] * b;

  for (n in start:end) {
    mu[n - start + 1] += r_1_1[J_1[n]] * Z_1_1[n] + r_1_2[J_1[n]] * Z_1_2[n] +
      r_2_1[J_2[n]] * Z_2_1[n] +
      r_3_1[J_3[n]] * Z_3_1[n] + r_3_2[J_3[n]] * Z_3_2[n] +
      r_4_1[J_4[n]] * Z_4_1[n] +
      r_5_1[J_5[n]] * Z_5_1[n] +
      r_6_1[J_6[n]] * Z_6_1[n] + r_6_2[J_6[n]] * Z_6_2[n] +
      r_7_1[J_7[n]] * Z_7_1[n] + r_7_2[J_7[n]] * Z_7_2[n] +
      r_8_1[J_8[n]] * Z_8_1[n] +
      r_9_1[J_9[n]] * Z_9_1[n] +
      r_10_1[J_10[n]] * Z_10_1[n] +
      r_11_1[J_11[n]] * Z_11_1[n] + r_11_2[J_11[n]] * Z_11_2[n];
  }

  return binomial_logit_lpmf(Y | trials[start:end], mu);
}
```

And the model block call:
```
target += reduce_sum(parallel, Y[1:N_subset], grainsize, trials,
                     temp_Intercept, Xc[1:N_subset], b,
                     r_1_1, J_1, Z_1_1, r_1_2, Z_1_2,
                     r_2_1, J_2, Z_2_1,
                     r_3_1, J_3, Z_3_1, r_3_2, Z_3_2,
                     r_4_1, J_4, Z_4_1,
                     r_5_1, J_5, Z_5_1,
                     r_6_1, J_6, Z_6_1, r_6_2, Z_6_2,
                     r_7_1, J_7, Z_7_1, r_7_2, Z_7_2,
                     r_8_1, J_8, Z_8_1,
                     r_9_1, J_9, Z_9_1,
                     r_10_1, J_10, Z_10_1,
                     r_11_1, J_11, Z_11_1, r_11_2, Z_11_2);
```

I'd like to emphasize the similarity between the original code in the model block and the new user-defined function. This mechanism should make it substantially easier to write parallel code in Stan.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The argument packing/unpacking is avoided by using lots of C++ parameter packs.

The parallelization is managed by the existing TBB autodiff extensions (each TBB worker thread gets its own separate nested autodiff stack).

By requiring that the output of all the functions to be a scalar, this calculation can be embedded efficiently in the forward pass by computing the Jacobian of the operation. In this way the autodiff work is parallelized without having to add any parallelization mechanism to the reverse mode sweep.

# Drawbacks
[drawbacks]: #drawbacks

I believe the main drawback is maintenance. I'm hoping this makes most uses of threaded map-rect defunct. Similarly parallelization in reverse mode autodiff might make this not so useful eventually, in which case we have the question of maintenance and backwards compatibility.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The reduce_sum parallelization mechanism is desirable largely because it doesn't require any large reworking of the autodiff system and can be implemented with threads in the TBB pretty painlessly.

One limitation we might remove from reduce sum would be to allow non-scalar outputs. The issue here is that to make use of autodiff efficiently in this case we would need to do parallel calculations during the reverse mode sweep. This currently isn't possible with Stan's autodiff.

There was some discussion of backends for this functionality (MPI vs. threading). There is no reason this could not be ported to work with MPI, though the performance characteristics would change.

# Prior art
[prior-art]: #prior-art

The previous example of parallelization in Stan is map-rect. Using map-rect was awkward primarily because of the argument packing.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

There are performance problems with the current design. In isolated testing, we can get linear speedup with the number of cores. In practical models, the speedups seem much more limited. See discussions in https://discourse.mc-stan.org/t/parallel-autodiff-v4/13111.
