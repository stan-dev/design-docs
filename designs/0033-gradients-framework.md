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

This is the technical portion of the RFC. Explain the design in sufficient detail that:

- Its interaction with other features is clear.
- It is reasonably clear how the feature would be implemented.
- Corner cases are dissected by example.

The section should return to the examples given in the previous section, and explain more fully how the detailed proposal makes those examples work.

# Drawbacks
[drawbacks]: #drawbacks

Why should we *not* do this?

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?
- What other designs have been considered and what is the rationale for not choosing them?
- What is the impact of not doing this?

# Prior art
[prior-art]: #prior-art

Discuss prior art, both the good and the bad, in relation to this proposal.
A few examples of what this can include are:

- For language, library, tools, and compiler proposals: Does this feature exist in other programming languages and what experience have their community had?
- For community proposals: Is this done by some other community and what were their experiences with it?
- For other teams: What lessons can we learn from what other communities have done here?
- Papers: Are there any published papers or great posts that discuss this? If you have some relevant papers to refer to, this can serve as a more detailed theoretical background.

This section is intended to encourage you as an author to think about the lessons from other languages, provide readers of your RFC with a fuller picture.
If there is no prior art, that is fine - your ideas are interesting to us whether they are brand new or if it is an adaptation from other languages.

Note that while precedent set by other languages is some motivation, it does not on its own motivate an RFC.
Please also take into consideration that rust sometimes intentionally diverges from common language features.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?
- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?
