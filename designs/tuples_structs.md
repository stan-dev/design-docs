- Feature Name: Tuples and Structs
- Start Date: 2020-04-23
- RFC PR: ??
- Stan Issue:

NOTE:  THIS HASN'T BEEN MERGED INTO A PROPER RFC FORMAT;  IT WAS JUST
COPIED FROM THE WIKI WHERE IT WAS FIRST POSTED

## Declaring Tuples

A declaration would look something like this:

```
(T1, ..., TN) x;
```

where `T1` through `TN` are sized type specifications.

<b>Issue:</b>  To make this fly, we need to have a way of declaring sized types contiguously.  Right now, declarations like `int x[3]` split the `int` and `[3]`.  Mitzi's working on this as part of the general refactor of the underlying type system.

## Tuple Expressions

The expression for creating tuples can follow the array notation (`{ a, b, c }`) and vector notation (`[a, b, c]`) and use `(a, b, c)`.  This will create a tuple of type `(typeof(a), typeof(b), typeof(c))`, which will be inferrable.

## Tuple Accessors

We can't have general access by integer because we can't figure out the type statically and Stan is strongly statically typed.  So we'll have to hardcode the accessors, as in:

```
tuple(S, T, U) x;
...
S a = x.1;
T b = x.2;
U c = x.3;
// x.4 causes compilation error
```

And just to say this again, we can't have `x[n]` for some runtime-determined `n` because we need to determine return type statically.


## Heads, Tails, and Concatenations

We can follow Lisp and define some basic operations on tuples as lists, including heads (car),

```
T1
head((T1, ..., TN) a);
```

tails (cdr),

```
(T2, ..., TN)
tail((T1, T2, ..., TN) a);
```

and concatenation (cat)

```
(T1, T2, ..., TN)
concat(T1 a, (T2, ..., TN) b);
```



## Lvalues

We want to allow tuples and elements of tuples on the left-hand side of assignments, as in:

```
(double, int) a;
a = (3.7, 2);  // assign to
a.1 = 4.2;
```

## Promotion (Covariance)

Should tuples be fully covariant?  That means that whenever `a` is a subtype of `b` (e.g., `int` is a subtype of `real`), then `(..., a, ...)` is a subtype of `(..., b, ...)` in a tuple.  This would allow us to assign an integer and double tuple to a pair of double value tuples, `(int, double, matrix)` assignable to `(double, double, matrix)`.  If that doesn't work, the expression construction syntax is going to be confusing when `int` doesn't act like `double`.

## Alternative syntax

Instead of `(T1, ..., TN)`, we could use `tuple(T1, ..., TN)`.  It's a little more explicit.  The implicit version matches behavior in Python.

## Not R lists

Tuple are not meant to be dynamic heterogeneous containers like lists in R.  The types are declared statically like every other variable in Stan.



## C++ Implementation

We can drop down to C++11 tuple types if they scale or use a Lisp-type encoding.

```
struct nil_tuple {
  nil_tuple() { }
};

template <typename H, typename T>
class tuple {
private:
  H head_;
  T tail_;
public:
  tuple(const H& head, const T& tail) : head_(head), tail_(tail) { }
  H& head() { return head_; }  // const return?
  T& tail() { return tail_; }  // const return?
};
```


# Summary
[summary]: #summary

The reduce_sum function is an attempt to add a parallelization utility that is much easier to use than map-rect without requiring a substantial changes to the autodiff stack.

# Motivation
[motivation]: #motivation

The goal of reduce_sum is to make it easier for users to parallelize their models by streamlining how arguments are handled, hiding work scheduling, and making it more difficult to program something that will accidentally be inefficient.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

```reduce_sum``` is a tool for parallelizing operations that can be represented as a sum of functions, `g: U -> real`.

For instance, for a sequence of ```x``` values of type ```U```, ```{ x1, x2, ... }```, we might compute the sum:

```g(x1) + g(x2) + ...```

In terms of probabilistic models, comes up when there are N conditionally independent terms in a likelihood. In these cases each conditionally indepedent term can be computed in parallel. If dependencies exist between the terms, then this isn't possible. For instance, in evaluating the log density of a Gaussian process ```reduce_sum``` would not be very useful.

```reduce_sum``` doesn't actually take ```g: U -> real``` as an input argument. Instead it takes ```f: U[] -> real```, where ```f``` computes the partial sum corresponding to the slice of the sequence ```x``` passed in. For instance:

```
f({ x1, x2, x3 }) = g(x1) + g(x2) + g(x3)
f({ x1 }) = g(x1)
f({ x1, x2, x3 }) = f({ x1, x2 }) + f({ x3 })
```

If the user can write a function ```f: U[] -> real``` to compute the necessary partial sums in the calculation, then we can provide a function to automatically parallelize the calculations (and this is what ```reduce_sum``` is).

If the set of work is represented as an array ```{ x1, x2, x3, ... }```, then mathematically it is possible to rewrite this sum with any combination of partial sums.

For instance, the sum can be written:

1. ```f({ x1, x2, x3, ... })```, summing over all arguments, using one partial sum
2. ```f({ x1, ..., xM }) + reduce({ x(M + 1), x(M + 2), ...})```, computing the first M terms separately from the rest
3. ```f({ x1 }) + f({ x2 }) + f({ x3 }) + ...```, computing each term individually and summing them

The first form uses only one partial sum and no parallelization can be done, the second uses two partial sums and so can be parallelized over two workers, and the last can be parallelized over as many workers as there are elements in the array ```x```. Depending on how the list is sliced up, it is possible to parallelize this calculation over many workers.

```reduce_sum``` is the tool that will allow us to automatically parallelize this calculation.

For efficiency and convenience, ```reduce_sum``` allows for additional shared arguments to be passed to every term in the sum. So for the array ```{ x1, x2, ... }``` and the shared arguments ```s1, s2, ...``` the effective sum (with individual terms) looks like:

```
g(x1, s1, s2, ...) + g(x2, s1, s2, ...) + g(x3, s1, s2, ...) + ...
```

which can be written equivalently with partial sums to look like:

```
f({ x1, x2 }, s1, s2, ...) + f({ x3 }, s1, s2, ...)
```

where the particular slicing of the ```x``` array can change.

Given this, the signature for reduce_sum is:

```
real reduce_sum(F func, T[] x, int grainsize, T1 s1, T2 s2, ...)
```

1. ```func``` - User defined function that computes partial sums
2. ```x``` - Argument to slice, each element corresponds to a term in the summation
3. ```grainsize``` - Target for size of slices
4-. ```s1, s2, ...``` - Arguments shared in every term

The user-defined partial sum functions have the signature:

```
real func(T[] x_subset, int start, int end, T1 arg1, T2 arg2, ...)
```

and take the arguments:
1. ```x_subset``` - The subset of ```x``` (from ```reduce_sum```) for which this partial sum is responsible (```x[start:end]```)
2. ```start``` - An integer specifying the first term in the partial sum
3. ```end``` - An integer specifying the last term in the partial sum (inclusive)
4-. ```arg1, arg2, ...``` Arguments shared in every term  (passed on without modification from the reduce_sum call)

The user-provided function ```func``` is expect to compute the ```start``` through ```end``` terms of the overall sum, accumulate them, and return that value. The user function is passed the subset ```x[start:end]``` as ```x_subset```. ```start``` and ```end``` are passed so that ```func``` can index any of the tailing ```sM``` arguments as necessary. The trailing ```sM``` arguments are passed without modification to every call of ```func```.

The ```reduce_sum``` call:

```
real sum = reduce_sum(func, x, grainsize, s1, s2, ...)
```

can be replaced by either:

```
real sum = func(x, 1, size(x), s1, s2, ...)
```

or the code:

```
real sum = 0.0;
for(i in 1:size(x)) {
  sum = sum + func({ x[i] }, i, i, s1, s2, ...);
}
```

As an example, in the regression:
```
data {
  int N;
  int y[N];
  vector[N] x;
}

parameters {
  vector[2] beta;
}

model {
  beta ~ std_normal();
  y ~ bernoulli_logit(beta[1] + beta[2] * x);
}
```

the likelihood term:

```
y ~ bernoulli_logit(beta[1] + beta[2] * x);
```

can be written equivalently (up to a constant of proportionality) as a sum over terms:

```
for(n in 1:N) {
  target += bernoulli_logit_pmf(y | beta[1] + beta[2] * x);
}
```

Because this sum can be broken up into partial sums, ```reduce_sum``` can be used
to parallelize this model. Writing the function for the partial sums and
updating the model block to use ```reduce_sum``` gives:

```
functions {
  real partial_sum(int[] y_subset,
                   int start, int end,
                   vector x,
                   vector beta) {
    return bernoulli_logit_lpmf(y_subset | beta[1] + beta[2] * x[start:end]);
  }
}

data {
  int N;
  int y[N];
  vector[N] x;
}

parameters {
  vector[2] beta;
}

model {
  int grainsize = 100;
  beta ~ std_normal();
  target += reduce_sum(partial_sum, y,
                       grainsize,
                       x, beta);
}
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

Regarding the first term (N), if ```x``` does not contain autodiff types, no autodiff copy is performed.

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
real sum = reduce_sum(func, x, s1, s2, ...)
```

can be replaced by:

```
real sum = func(x, 1, size(x), s1, s2, ...)
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
