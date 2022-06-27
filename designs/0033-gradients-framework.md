- Feature Name: generalized_function_gradients
- Start Date: 2022-06-07
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

This document proposes a C++ framework for defining gradients for both reverse- and forward-mode at the same time as the definition of the function. This allows for reducing code duplication and boilerplate, and also provides an interface for user-provided gradients in the future.

# Motivation
[motivation]: #motivation

Currently, when specifying forward- and reverse-mode gradients for functions, developers are required to create additional `fwd` and `rev` headers, with the boilerplate specific to each AD type (e.g., `make_callback_var`). This provides an additional barrier to entry for new developers, as they have to familiarise themselves with the various Math-specific frameworks (e.g., `arena<T>`, `var<Matrix>`, `fvar<var>`). Additionally, scalar functions (generally) have the same gradient specifications for both `fwd` and `rev`, leading to further code duplication.

The proposed framework aims to simplify specification of gradients for functions, and create a facility for user-specified gradients.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

## Scalar Functions (Same Gradient Functions)

Take the `hypot` function for example, we first define a functor providing the primitive return value:

```cpp
  auto val_fun = [&](auto&& x, auto&& y) {
    using std::hypot;
    return hypot(x, y);
  };
```

Next, we specify a functor for each input that calculates the respective gradients. These functors should have the value and adjoint as the first two arguments, and then all inputs as the remaining arguments:

```cpp
  auto grad_fun_a
      = [&](auto&& val, auto&& adj, auto&& x, auto&& y) {
        return elt_multiply(adj, elt_divide(x, val));
      };
  auto grad_fun_b
      = [&](auto&& val, auto&& adj, auto&& x, auto&& y) {
        return elt_multiply(adj, elt_divide(y, val));
      };
```

Finally, a tuple of the input arguments, the value functions, and a tuple of the gradient functions are passed to the `function_gradients` functor:

```cpp
  return function_gradients<true>(std::forward_as_tuple(a, b),
                            std::forward<decltype(val_fun)>(val_fun),
                            std::forward_as_tuple(grad_fun_a, grad_fun_b));
```

Where the `<true>` flag boolean indicates that the same gradient functors can be applied for both reverse- and forward-mode.

In a single declaration, this looks like:

```cpp
template <typename T1, typename T2, require_all_not_eigen_t<T1, T2>* = nullptr,
          require_all_not_std_vector_t<T1, T2>* = nullptr,
          require_all_not_nonscalar_prim_or_rev_kernel_expression_t<
              T1, T2>* = nullptr>
inline auto hypot(const T1& a, const T2& b) {
  auto val_fun = [&](auto&& x, auto&& y) {
    using std::hypot;
    return hypot(x, y);
  };
  auto grad_fun_a
      = [&](auto&& val, auto&& adj, auto&& x, auto&& y) {
        return elt_multiply(adj, elt_divide(x, val));
      };
  auto grad_fun_b
      = [&](auto&& val, auto&& adj, auto&& x, auto&& y) {
        return elt_multiply(adj, elt_divide(y, val));
      };
  return function_gradients<true>(std::forward_as_tuple(a, b),
                            std::forward<decltype(val_fun)>(val_fun),
                            std::forward_as_tuple(grad_fun_a, grad_fun_b));
}
```

The `function_gradients` functor then handles the necessary boilerplate for calculating gradients only for non-constant inputs, as well as the management for `arena` types with the `reverse_pass_callback` approach.

## Matrix Functions (Adjoint-Jacobian Product)

To provide different gradient functions for forward- and reverse-mode, the developer simply needs to provide an additional tuple of gradient functors.

Take the `inverse()` function as an example. Defined as:

$$
C = A^{-1}
$$


The reverse-mode gradients are given by:

$$
\bar{A} = -C^T \bar{C} C^T
$$

The forward-mode gradients by:

$$
\dot{C} = -C\dot{A}C
$$

To specify this in C++, we again first start with the functor defining the calculation with primitive inputs:

```cpp
  decltype(auto) val_fun = [](auto&& x) {
    check_square("inverse", "m", x);
    if (x.size() == 0) {
      return plain_type_t<decltype(x)>();
    }
    return x.inverse().eval();
  };
```

Except now we specify a different functor for the reverse- and forward-modes. Again, the functors should take the value and gradient as the first two arguments, followed by all other inputs.

Reverse-mode:

```cpp
  auto rev_grad_fun = [](auto&& val, auto&& adj, auto&& x) {
    return -multiply(multiply(transpose(val), adj), transpose(val));
  };
```

Forward-mode:

```cpp
  auto fwd_grad_fun = [&](auto&& val, auto&& adj, auto&& x) {
    return -multiply(multiply(val, adj), val);
  };
```

Now the call to `function_gradients` includes two tuples of gradient functors - one for reverse-mode and one for forward-mode. If there are multiple input arguments, then each each tuple would contain multiple functors (as with the scalar specification):

```cpp
  return function_gradients(
      std::forward_as_tuple(m_ref),
      std::move(val_fun),
      std::forward_as_tuple(rev_grad_fun),
      std::forward_as_tuple(fwd_grad_fun));
```

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

For all input types, the return value is calculated by calling `math::apply()` with the values-functor on the tuple of input arguments (after calling `value_of` for `rev` or `fwd`).

## Reverse-Mode

For reverse-mode, the gradients are constructed using `reverse_pass_callback()`. The tuple of (`var` type) input arguments and gradient functors are iterated over, accumulating the adjoints for the respective input using the specified gradient functor:

```cpp
  reverse_pass_callback(
      [rev_grad_fun_tuple, arena_tuple, prim_tuple, rtn]() mutable {
        // Iterate over input arguments, applying the respective gradient
        // function with the tuple of extracted primitive values
        walk_tuples(
            [&](auto&& grad_funs, auto&& arg) {
              // Only calculate gradients if the input argument is not primitive
              if (!is_constant_all<decltype(arg)>::value) {
                // Need to wrap the argument in a forward_as<var>() so that it
                // will compile with both primitive and var inputs
                forward_as<promote_scalar_t<var, decltype(arg)>>(arg).adj() +=
                    // Use the relevant gradient function with the tuple of
                    // primitive arguments
                    math::apply(
                        [&](auto&&... args) {
                          return grad_funs(rtn.val_op(), rtn.adj_op(),
                                   internal::arena_val(
                                       std::forward<decltype(args)>(args))...);
                        },
                        prim_tuple);
              }
            },
            std::forward<RevGradFunT>(rev_grad_fun_tuple),
            std::forward<decltype(arena_tuple)>(arena_tuple));
      });
```

Where `walk_tuples` is a functor for the parallel iteration over multiple tuples (parallel as in `pmap`, rather than multi-threaded).

## Forward-Mode

A similar approach is used for forward-mode, but instead the gradients are accumulated into a single variable which is then used to construct the return `fvar`:

```cpp
  auto d_ = internal::initialize_grad(std::forward<rtn_t>(rtn));

  walk_tuples(
      [&](auto&& f, auto&& arg, auto&& dummy) {
        using arg_t = decltype(arg);
        if (!is_constant_all<arg_t>::value) {
          d_ += math::apply(
              [&](auto&&... args) {
                return f(rtn,
                         forward_as<promote_scalar_t<ReturnT, arg_t>>(arg).d(),
                         args...);
              },
              val_tuple);
        }
      },
      std::forward<FwdGradFunT>(fwd_grad_fun_tuple),
      std::forward<ArgsTupleT>(args_tuple),
      std::forward<decltype(dummy_tuple)>(dummy_tuple));

  return to_fvar(rtn, d_);
```

Where `internal::initialize_grad` is used to initialise a variable with the same type and dimension as the return value.

# Drawbacks
[drawbacks]: #drawbacks

This does appear to increase compilation time - given the increased complexity of templating and tuple manipulation

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The best alternative is the current approach, of separate specifications for `prim`, `fwd`, and `rev`. But this has the limitations mentioned in the Motivation section.

# Prior art
[prior-art]: #prior-art

None that I'm aware of

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Is an increase in compilation times likely to be a blocker for users?
