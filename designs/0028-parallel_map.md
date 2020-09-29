- Feature Name: parallel_map
- Start Date: 2020/09/29
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

The proposed ```parallel_map``` functionality provides a means of within-chain parallelisation that does not require the sum of iterations be returned (i.e., ```reduce_sum```) or any complex argument-packing (i.e., ```map_rect```).

# Motivation
[motivation]: #motivation

While the ```reduce_sum``` framework has been very popular for its ease of use, it's limited to situations where the goal is to return the sum of independent computations. Many users have models with large functions/computations that return vectors or matrices in full, rather than their sum. For these cases, users seeking parallelisation are limited to the ```map_rect``` functionality, which has a non-zero barrier to entry due to the need for argument packing and unpacking. The ```parallel_map``` framework aims to provide a means of parallelising these operations in a manner which is easy for users to understand and implement.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

## Target Loop
As an example, let's say the user wanted to calculate the log of the beta function from two vectors of size 10000:
```
for (int i = 0; i < 10000; ++i) {
  result[i] = lgamma(a[i]) + lgamma(b[i]) - lgamma(a[i] + b[i])
}
```

There are two key components to parallelising this loop via ```parallel_map```: an indexing function and an computation/application function.

## Index Function
The indexing function is the workhorse of the framework, as it allows ```parallel_map``` to manipulate only the variables that are needed by a given thread. This is in contrast to ```reduce_sum```, which will only 'slice' one argument and copy the rest in full to all threads. For the above loop we want to loop over both arguments (```a``` and ```b```), this means that the indexing function will be:
```
auto index_fun = [&](int i, const auto& fun, const auto& x, const auto& y) {
  return fun(x[i], y[i]);
};
```

As you can see, this approach allows for a great deal of flexibility in the indexing of arguments. For example, if in the loop above, ```a``` was a vector of size 10000, and ```b``` was a scalar to broadcast to each element of ```a```, the indexing function would instead be:
```
auto index_fun = [&](int i, const auto& fun, const auto& x, const auto& y) {
  return fun(x[i], y);
};
```

Further, it's not required that the indexing function return scalars, *as long as the result of the computation/application function is a scalar*. This means that given two matrices, for example, the indexing function could be:
```
auto index_fun = [&](int i, const auto& fun, const auto& x, const auto& y) {
  return fun(x.row(i), y.col(i));
};
```

Additionally, ```parallel_map``` supports looping over two indexes. If ```a``` and ```b``` were both matrices then the index function would use two indexes (row & column):
```
auto index_fun = [&](int i, int j, const auto& fun, const auto& x, const auto& y) {
  return fun(x(i, j), y(i, j));
};
```

## Apply Function
Returning to the original loop, once the indexing function has been specified, the next step is to specify the function to be applied to the indexed arguments. This function should be specified assuming that the arguments have already been indexed (i.e., assuming that the inputs are scalars, rather than vectors/matrices that need to be indexed). For the above loop, this function would be:

```
auto app_fun = [&](const auto& x, const auto& y) {
  return lgamma(x) + lgamma(y) - lgamma(x + y);
};
```

## parallel_map Call
The final step before applying these functions to the inputs is to declare the output/result container that each iteration of the loop should be evaluated into. A limitation of the framework is that this result container needs to be declared beforehand and passed to the ```parallel_map``` call, as while it is simple to deduce the return type it is not (yet) possible to deduce the size of the return type.

Once the result container has been declared, we can then call ```parallel_map```:
```
parallel_map(app_fun, index_fun, std::forward<result_type>(result), grainsize,
             std::forward<a_type>(a), std::forward<b_type>(b))
```

Alternatively, if the loop to be parallelised is over two indexes (i.e., matrices), then both a row-wise and column-wise grainsize need to be provided to ```parallel_map```:
```
parallel_map(app_fun, index_fun, std::forward<result_type>(result), row_grainsize,
             col_grainsize, std::forward<a_type>(a), std::forward<b_type>(b))
```

Once ```parallel_map``` has finished executing the loop, the result container (```result``` above) will contain the results from each iteration.



# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

As with ```reduce_sum```, the scheduling of threads and distribution of work amongst them is managed by the TBB. The grainsize(s) then give the user some measure of control over the amount of work distributed to each thread.

When used with primitive types only, there is little overhead additional to that required by scheduling. With reverse-mode autodiff there are several areas that introduce additional cost. Because the parallel computations have to be conducted in an AD stack separate (nested) from the main AD stack, both the ```varis``` and the ```vars``` at each iteration need to be deep copied to the nested stack in each thread. The copy costs of this are minimised thanks to the indexing function, as it allows for only the needed ```varis```/```vars``` to be deep copied, rather than the entire object.

This requirement of a nested AD stack in each thread further introduces additional overhead. At each iteration of the parallelised loop in a given thread, the ```grad()``` function has to be called (in addition to the function computation itself) to compute and extract the adjoints for each of the input arguments. Once all of the threads have finished, the result container then has to be looped over to pack the computed values and adjoints into new vars in the main AD stack. This means that for a loop of size N, ```parallel_map``` will have to evaluate a loop of size N twice (once in parallel, and once in serial):

 - Parallel: Compute function, extract values, call ```grad()```, extract adjoints
 - Serial: Pack ```vari```, values, and adjoints into new ```vars``` on main stack
 
This means that ```parallel_map``` will be most effective in cases where the computational cost of a given function outweighs the cost of traversing the loop length twice.

# Drawbacks
[drawbacks]: #drawbacks

As covered earlier, the additional costs with reverse mode means that the parallelisation will not increase performance in all cases. For example, unary functions have not seen much benefit, as the computation at each iteration is not heavy enough to outweigh the repeated ```grad()``` calls and double-traversal of the loop length. When introducing this functionality to users, it will need to be emphasised that not all loops will benefit.

Additionally, there are three requirements to the loops that can be parallelised:

 - Each iteration must return a scalar
 - Each iteration cannot depend on the result of another iteration
 - There can only be one or two indexes
 
Requirements 1 & 3 could possibly be relaxed at a later date, but requirement 2 cannot be worked around as there is no guarantee that the iterations will be completed in a particular order.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

This approach is desirable because it is highly flexible. Any loop can be parallelised as long as it meets the above requirements - regardless of the number of arguments or how they're indexed. It is also simple to implement - no argument packing/unpacking required.

# Prior art
[prior-art]: #prior-art

This framework is similar to (and heavily inspired by) ```reduce_sum```, as both are built around TBB functionality (```parallel_reduce``` and ```parallel_for```).

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Should we change the name from ```parallel_map```? Sebastian raised the point that we don't preface any other parallel functionality with "parallel"
- Is it going to be feasible to handle the index function in Stan? In c++ this needs to have an ```auto``` return type so that it can be used for copying ```varis```, ```vars```, and applying the computation function. How will this work with Stan where a return type needs to be specified for functions?
- Any other ideas for improving performance and usability are also very welcome
