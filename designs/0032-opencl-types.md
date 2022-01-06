- Feature Name: opencl\_types
- Start Date: 2022-01-02
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Introduce new Stan types that would represent data, parameters or generated quantities
on the GPU. With these types users would have manual control when to use OpenCL/GPU
supported function in the Stan Math backend.

The new types would be `vector_cl[N]`, `row_vector_cl[N]`, `matrix_cl[N]` and `int_cl[N]`,
representing `vector[N]`, `row_vector[N]`, `matrix[N]` and `array[N] int` Stan variables
on the OpenCL device.

This would be a valid Stan model:

```stan
data {
  int N;
  int_cl[N] n_redcards;
  int_cl[N] n_games;
  vector_cl[N] rating;
}
parameters {
  vector[2] beta;
}
model {
  beta ~ normal(0,1);

  vector_cl[N] temp = beta[1] + beta[2] * rating;
  n_redcards ~ binomial_logit(n_games , temp);
}
```

All computation of this model, apart from setting the prior statement would use OpenCL-supported
functions.

Please note that this design document uses the term OpenCL device. In the majority of cases, the
target OpenCL device will be a GPU, but as this could be any other OpenCL-supported device
as well, we use the more general term OpenCL device.

# Motivation
[motivation]: #motivation

The biggest motivation is that the majority of Stan Math functions and all density and mass functions
have OpenCL support but are not being exposed to the Stan user. Currently, if the `--use-opencl` flag
is set (this flag is used in CmdStan if `STAN_OPENCL` is set in the make/local file), stanc3 does a
sort of an optimization pass where it tries to find some opportunities to use OpenCL-supported
functions. This optimization pass is quite trivial and expanding it is a difficult task, particularly
in testing, which is why it has not been expanded. We have also gotten the sense that users would like
to have the option of manually specifying when to move a part of computation to the OpenCL device.



# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation




# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation




# Drawbacks
[drawbacks]: #drawbacks

This adds additional types to the language, which adds addtional code
to maintain in stanc3 and additional documentation to keep up-to-date.

This exposes a bit more of the computational backend to the user,
making them focus on that aspect of modeling as well, which we try to mostly avoid in Stan.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

An alternative approach to this design could be to expand the current optimization
pass to be similar to how we are trying to handle immutable matrices (vars of matrices)
in the optimization framework. Though I think both of these approaches could co-exist
and adding types would actually simplify that optimization as well.

# Prior art
[prior-art]: #prior-art

N/A

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Naming the types. Are `int_cl`, `matrix_cl`, `vector_cl`, `row_vector_cl` good names?

- How to handle the case when a used does not use the `--use-opencl` flag, but does use the OpenCL/GPU types? 
We can automatically downgrade them to CPU types or stop with a helpful error message.

Other unresolved questions are mostly on the implementation level. For example whether to
implement reader support for the new types or create intermediate CPU variables and 
explictily transfer.