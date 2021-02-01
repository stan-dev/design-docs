- Feature Name: rowwise_framework
- Start Date: 2021-02-01
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

This proposal outlines a framework for specifying custom row- and column-wise functions in Stan. The proposed framework allows for both the inputs to be iterated over, and the shared inputs, to be variadic. The specification and use largely follows that of R's ```mapply``` function. 

# Motivation
[motivation]: #motivation

The proposed framework will allow for a more flexible specification of Stan models.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The ```rowwise``` and ```colwise``` functions have signatures:
```
rowwise(iterated arguments, functor, shared arguments)
```

As an applied example, take the following (arbitrary) Stan program:
```
parameters {
  matrix[R,C] input1;
  matrix[R,C] input2;
  real input3;
}

transformed parameters {
  matrix[R,C] out;

  for(r in 1:R) {
    out[r] = cumulative_sum(input1[r] - input2[r]  * input3);
  }
}
```

To rewrite this using ```rowwise```, first the desired operation needs to be specified as a function:
```
functions {
  row_vector custom_func(row_vector a, row_vector b, real c) {
    return cumulative_sum(a - b * c);
  }
}
```

This functor is then used in the call to ```rowwise``` to distinguish between the inputs that will be iterated over by row (i.e., ```input1``` and ```input2```), and those that are used in full at each iteration (i.e., ```input3```):
```
out = rowwise(input1, input2, custom_func, input3)
```

As a full model:
```
functions {
  row_vector custom_func(row_vector a, row_vector b, real c) {
    return cumulative_sum(a - b * c);
  }
}

parameters {
  matrix[R,C] input1;
  matrix[R,C] input2;
  real input3;
}

transformed parameters {
  matrix[R,C] out = rowwise(input1, input2, custom_func, input3);
}
```

There are no restrictions to the number of iterated and shared arguments. Similarly, if no shared arguments are needed then the function can be specified without them. For example if the ```real``` argument above (```input3```) was not needed, then the call to ```rowwise``` would be:
```
out = rowwise(input1, input2, custom_func)
```

The specification and application of ```colwise``` follows the same idiom.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

While the Eigen library provides the ```.colwise()``` and ```.rowwise()``` member functions, these only support a limited range of functions (e.g., basic arithmetic). Custom functions, like ```log_sum_exp(mat.rowwise())```, are not compatible. As such, the c++ implementation of the proposed framework is simply a loop.

The code complexity comes from disambiguating the iterated and shared arguments, and also iterating over these.

The framework takes a single parameter pack:
```
template <typename... TArgs>
auto rowwise(const TArgs&... args)
```

And determines the position of the user-specified functor at compile-time:
```
// Get location of functor in parameter pack
constexpr size_t pos = internal::type_count<internal::is_stan_type,
                                            TArgs...>();
constexpr size_t arg_size = sizeof...(TArgs);
```

This is used to 'split' the parameter pack into two tuples, one of iterated arguments and one of shared:
```
// Split parameter pack into two tuples, separated by the functor
decltype(auto) t1 = internal::subset_tuple(std::forward<TupleT>(args_tuple),
                      std::make_index_sequence<pos>{});
decltype(auto) t2 = internal::subset_tuple(std::forward<TupleT>(args_tuple),
                      internal::add_offset<pos+1>(
                        std::make_index_sequence<arg_size-pos-1>{}));
```

For each iteration, the iterated arguments are extracted to a separate tuple, concatenated to the tuple of shared arguments, and the user-specified functor applied:
```
    rtn.row(i) = as_row_vector(
      apply([&](auto&&... args) { return f(args...); },
        std::tuple_cat(internal::row_index(std::forward<decltype(t1)>(t1), i),
                       std::forward<decltype(t2)>(t2)))
    );
```

# Drawbacks
[drawbacks]: #drawbacks

This may be introducing additional abstraction in the code, which risks reducing the readability of models.

The tuple packing and unpacking may introduce overhead additional to that from the simple loops, despite the heavy use of forwarding references. More testing and optimisations may be needed.


# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The primary alternative is a simple loop. However, the ```rowwise```/```colwise``` functions may allow for more complex function specifications. 

# Prior art
[prior-art]: #prior-art

As mentioned earlier, this largely follows the design of the ```mapply``` function in R.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

Is this design/framework appealing to Stan users? Is this appealing over a simple loop?

Are there areas for optimisation that should be considered?
