- Feature Name: eigen_expressions
- Start Date: 2020-05-22
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Allow all functions in Stan Math to accept and return Eigen expressions. 

# Motivation
[motivation]: #motivation

If all functions only accept and return matrices, every function must evaluate all operations it uses within the function. Evaluation of an operation means loading all matrices involved from memory to CPU, computing the opration and storing the result back in memory. For simple operations loading and storing take more time than computations.

If we instead allow functions to accept and return expressions, the expresssions are only evaluated when strictly necessary. So more operations can be combined into a single expression, before it is evaluated. This results in less memory transfers and faster execution.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Eigen, the library we are using for matrix computations supports lazy evaluation. That means operations are not imediately evaluated. Instead each operation returns an object that represents this operation and references the arguments to the operation. If those arguments are operations themselves we can build arbitrarily complex expressions. These expressions are evaluated when assigned to a matrix (or `.eval()` is called on it). For example:

```
Eigen MatrixXd a, b;
auto expr = a + 3 * b; //not evaluated yet
MatrixXd c = expr; //now it evaluates
```

General functions must accept their arguments as templates. Which types are accepted and which are not can be restricted with requires, such as `require_eigen_t<T>`. Now these arguments can be either matrices as before or more general expressions. All functions must be updated to handle this.

This is intended to require no changes in Stan lang and compiler. Here is an example:
```
matrix[5,5] A, B;
matrix[5,5] C = 3 * A - 5 * B;
```
Variables `A`, `B` and `C` will remain of same type both in Stan Language and in compiled C++ model. The Expression `3 * A - 5 * B` will, however, be calculated more efficiently.

## Example of generalizing a simple function
Old implementation:
```
template <typename T1, typename T2, int R, int C>
inline Eigen::Matrix<return_type_t<T1, T2>, R, C> add(
    const Eigen::Matrix<T1, R, C>& m1, const Eigen::Matrix<T2, R, C>& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return m1 + m2;
 }
```
Function accepting expressions, but it still returning a matrix:
```
template <typename Mat1, typename Mat2,
          typename = require_all_eigen_t<Mat1, Mat2>>
inline auto add(const Mat1& m1, const Mat2& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return (m1 + m2).eval();
}
```
Function accepting and returning expressions:
```
template <typename Mat1, typename Mat2,
          typename = require_all_eigen_t<Mat1, Mat2>>
inline auto add(const Mat1& m1, const Mat2& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return m1 + m2;
}
```

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

Some expressions can be very expensive to compute (for example matrix multiplication), so they should never be evaluated more than once. So if an expression argument is used more than once in a function, it should be evaluated first and than the computed value should be used. On the other hand some expressions are trivial to compute (for example block). For these it would be better if they are not evaluated, as that would make a copy of underlying data. Eigen solved this dilemma by introducing `Eigen::Ref` class. If a trivial expression is assigned to `Ref` it is just referenced by it. If the expression involves actual computations assigning it to `Ref` evaluates it and stores the result in the `Ref`. In either case `Ref` than can be used more or less the same as a matrix.

However, `Ref`, behaves weirdly in some situations. Namely its copy constructor does nothing. Instead of using `Ref` we can make a trait metaprogram `to_ref_t<T>` that determines appropriate type to assign an expression to that will behave the same as `Ref`, while also handle copying, moving etc. We can also make a helper function `to_ref` for converting expressions to that type.

So whenever an input argument, which might be an expression is more than once in a function it should be assigned to a variable of type `to_ref_t<T>`, where `T` is a the type of input argument (or alternatively call `to_ref` on the argument). That variable should be used everywhere in the function instead of directly using the input argument.

Steps to implement:
- Generalize all functions to accept general Eigen expressions (already halfway complete at the time of writing this)
- Test that all functions work with general expressions (this can probably be automated with a script).
- Make functions return Eigen expressions wherever it makes sense to do so. (This is for the functions that are exposed to Stan language. Other function can return expresions earlier.)

# Drawbacks
[drawbacks]: #drawbacks

Code complexity increases. Performance affecting bugs are more likely due to some input expression being evaluated multiple times.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The alternative is to stay with non-expression types. The downside to this is the extra time spend loading/storing matrices in simple operations.

An alternative implementation would make functions accept Eigen base classes, such as `Eigen::MatrixBase<Derived>`. Functionally this makes no changes to code. However `.derived()` must be called on all arguments accepted this way when they are used. It is simlper to use requires to restrict which types are accepted by a function.

# Prior art
[prior-art]: #prior-art

Eigen does it. We also do the same with kernel generator expressions.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

We might need some more trait metaprograms or helper functions to make working with generalized functions simpler.