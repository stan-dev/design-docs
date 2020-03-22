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

```reduce_sum``` is a tool for parallelizing operations that can be represented as a parallel-for combined with a sum (that returns a scalar).

In terms of probabilistic models, an example of this comes up when N terms in a likelihood combined multiplicatively and can be computed independently of each other (where independence here is in the computational sense, not necessarily the statistical sense). In this case, computing the log density means computing the sum of a number of terms that can each be computed separately. 

```reduce_sum``` is not useful when there are dependencies between the terms. This can happen, for instance, if there were N terms in a Gaussian process likelihood. ```reduce_sum``` will not be useful for accelerating this.

If for a set of input arguments, ```args0, args1, args2, ...``` and a scalar function ```f```, the log likelihood can be computed as:

```f(args0) + f(args1) + f(args2) + ...```

then this calculation can be written as a reduction over the set of arguments. If this reducing function is called ```reduce```, then it would need to perform the operations:

```reduce({ args0, args1, args2, ... }) = f(args0) + f(args1) + f(args2) + ...```

If the user can write a function like ```reduce```, then it is trivial for us to provide a function to automatically parallelize the calculations.

Again, if the set of work is represented as a list of arguments ``{ args0, args1, args2, ... }```, then mathematically it is possible to rewrite this sum with any combination of partial-reduces.

For instance, the sum can be written:

1. ```reduce({ args0, args1, args2, ... })```, summing over all arguments, using one reduce function
2. ```reduce({ args0, ..., args(M - 1) }) + reduce({ argsM, args2, ...})```, computing the first M terms separately from the rest
3. ```reduce({ args0 }) + reduce({ args1 }) + reduce({ args2 }) + ...```, computing each term individually and summing them

The first function call is completely serial, the second can be parallelized over two workers, and the last can be parallelized over as many workers as there are arguments. Depending on how the list is sliced up, it is possible to parallelize this calculation over many workers.

```reduce_sum``` is the tool that will allow us to automatically parallelize these reduce operations (and sum them together).

To implement this efficiently in Stan, the individual arguments are split into two types. The first are the arguments that are specific to each term in the reduction. These are called the sliced arguments (because we will slice these up to determine how to distribute the work). The second type of arguments are shared arguments, and are information that is shared in the computation of every term in the sum.

Given this, the signature for reduce_sum is:

```
real reduce_sum(F func, T[] sliced_arg, int grainsize, T1 arg1, T2 arg2, ...)
```

1. ```func``` - The user-defined reduce function
2. ```sliced_arg``` - An array of any type, with each element of the array corresponding to a term of the final summation (the length of ```sliced_arg``` is the total number of terms to sum)
3. ```grainsize``` - A hint to the runtime of how many terms of the summation to compute in each reduction
4-. ```arg1, arg2, ...``` - All the arguments that are to be shared in the calculation of every term in the sum

The user-defined reduce function is slightly different:

```
real func(int start, int end, T[] subset_sliced_arg, T1 arg1, T2 arg2, ...)
```

and takes the arguments:
1. ```start``` - An integer specifying the first element of the sequence of terms this reduce call is responsible for computing
2. ```end``` - An integer specifying the last element of the sequence of terms this reduce call is responsible for computing
3. ```subset_sliced_arg``` - The subset of sliced_arg for which this reduce is responsible (```sliced_arg[start:end]```)
4-. ```arg1, arg2, ...``` all the shared arguments -- passed on without modification from the reduce_sum call

The user-provided function ```func``` is expect to compute the ```start``` through ```end``` terms of the overall sum, accumulate them, and return that value. The user function is only passed the subset ```sliced_arg[start:end]``` of sliced arg (as ```subset_sliced_arg```). ```start``` and ```end``` are passed so that ```func``` can index any of the ```argM``` appropriately. The trailing arguments ```argM``` are passed without modification to every call of ```func```.

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
target += reduce_sum(parallel, Y, grainsize, trials,
                     temp_Intercept, Xc, b,
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

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The argument packing/unpacking is avoided by using lots of C++ parameter packs, the parallelization is managed by the existing TBB autodiff extensions (each TBB worker thread gets its own separate nested autodiff stack), and by requiring that the output of all the functions to be a scalar, this calculation can be done efficiently with nested forward mode autodiff. In this way the autodiff work is parallelized without having to add any parallelization mechanism to the reverse mode sweep.

There are hidden costs associated with the nested autodiff, however. If there are N items, TBB, depending on the grainsize, schedules chunks of work to be done by different threads. For each of these chunks of work, we figure out how many autodiff variables there are on the input and make copies of them on the specific thread-local stacks. We make sure that any autodiff done on these copied variables does not affect the autodiff variables on the main stack. Without this copying, we would have to deal with race conditions.

As such, there are up to N + M * P autodiff variable copies performed for each reduce_sum where:

1. N is the number of individual operations over which we are reducing
2. M is the number of blocks of work that TBB sections work up into

and

3. P is the number of autodiff variables in ```(arg1, arg2, ...)``` (... meaning all the trailing arguments)

reduce_sum was designed specifically for the case that ```N >> P```.

Regarding the first term (N), if the sliced_arg is of underlying type double or int, there is no autodiff copy performed.

M (the number of blocks of works that TBB chooses) will be decided by the number of work individual operations (N) and the grainsize. It should roughly be N / grainsize. If grainsize is small compared to the number of autodiff variables in the input arguments, then the overhead of copying disconnecting the nested autodiff stack from the main one will probably become evident. Experimentally, a large grainsize can be detrimental to performance overall, though, so grainsize will probably have to be implemented manually via user experimentation.

Regarding P, consider the variables defined by the C++ code:
```
var a = 5.0; // one autodiff variable
double b = 5.0; // zero autodiff variables
int c = 5; // zero autodiff variables
std::vector<var> d = {1.0, 2.0} // two autodiff variables
std::vector<double> e = {1.0, 2.0} // zero autodiff variables
std::vector<int> f = {1, 2} // zero autodiff variables
Eigen::Matrix<var, Eigen::Dynamic, 1> g(3); // three autodiff variables
Eigen::Matrix<double, Eigen::Dynamic, 1> h(3); // zero autodiff variables
Eigen::Matrix<var, 1, Eigen::Dynamic> i(4); // four autodiff variables
Eigen::Matrix<double, 1, Eigen::Dynamic> j(4); // zero autodiff variables
Eigen::Matrix<var, Eigen::Dynamic, Eigen::Dynamic> k(5, 5); // twenty-five autodiff variables
Eigen::Matrix<double, Eigen::Dynamic, Eigen::Dynamic> l(5, 5); // zero autodiff variables
```

Now, together as a collection of arguments:
```
(a, b, c) // P = 1
(e, g, i, l) // P = 7
(a, d, g) // P = 6
```

Repeat autodiff arguments are counted multiple times:
```
(a, a, a) // P = 3
```

# Drawbacks
[drawbacks]: #drawbacks

The main drawback of this new function is the danger that this is replaced by some more advanced and easier to use parallelization mechanism. If that happens, it will be very easy to implement a failsafe backwards compatibility version of reduce_sum that leans on the fact that:

```
real sum = reduce_sum(func, sliced_arg, arg1, arg2, ...)
```

can be replaced by:

```
real sum = func(1, size(sliced_arg), sliced_arg, arg1, arg2, ...)
```

where ```func``` was always provided by the user.

In isolated testing, we can get linear speedup with the number of cores. In practical models, the speedups seem much more limited. See discussions in https://discourse.mc-stan.org/t/parallel-autodiff-v4/13111. For memory bound problems, it is difficult to get more than a 2x or 3x speedup. For larger problems, more is possible. In any case, ```reduce_sum``` is just as efficient as ```map_rect```.

Choosing grainsize (the ideal number of terms the tbb scheduler will try to compute in each reduce) is a tricky thing. It is possible for the grainsize to be too small (in which case autodiff overhead slows down the sum) or get the grainsize too large (in which case things slow down too -- probably because of memory usage). We will have to add to the docs instructions on how to pick this, and perhaps an example of performance vs. grainsize for a given model and number of threads.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The reduce_sum parallelization mechanism is desirable largely because it doesn't require any large reworking of the autodiff system and can be implemented with threads in the TBB pretty painlessly.

In the future it is possible that the scalar output assumption is lifted, but that will only realistically be reasonable once it is possible to do parallel computions during the reverse mode sweep. This currently isn't possible with Stan's autodiff.

There was some discussion of backends for this functionality (MPI vs. threading). There is no reason this could not be ported to work with MPI, though the performance characteristics would change.

# Prior art
[prior-art]: #prior-art

The previous example of parallelization in Stan is map-rect. Argument packing made using map-rect difficult, and the goal here is to overcome that difficulty.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

