- Feature Name: vector_unary_functions
- Start Date: 2019-12-15
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

The proposed changes introduce a framework for extending unary vector functions to work with column vectors, row vectors, and std vectors, as well as std vectors of these. The proposed framework also works with ```Eigen``` expression templates as inputs.

# Motivation
[motivation]: #motivation

Currently, for a function to work with these different vector types (and containers of these vectors types), a different specialisation is required for each. This results in a large amount of code duplication and additional maintenance burden. By implementing a general framework, rather than individual specialisations, the function only needs to be defined once for it to work with all vector types (as well as containers of these vector types).

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

There are three primary types of unary vector functions used in the Math library:

- ```f(vector) -> vector``` (e.g. ```log_softmax```)
- ```f(vector) -> scalar``` (e.g. ```log_sum_exp```)
- ```f(vector, scalar) -> vector``` (e.g. ```head```)

Most of these functions operate solely on ```Eigen``` column vectors. While some of these also operate on ```std::vector```s, this requires the re-specification of the function using only standard library functions. This introduces two unwanted side effects. Firstly, this requires an increasing amount of code to maintain as these functions are extended to work with different types as inputs. Secondly, as different coding approaches are required for different inputs (i.e. ```Eigen``` vs standard library), functions will perform differently depending on the vector type that is passed to them.

By introducing a vectorisation framework for unary vector functions, a developer need only define their function once using ```Eigen```'s matrix/array functions, and it will automatically be able to take all vector types as inputs.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The proposed ```apply_vector_unary``` framework is derived from the existing ```apply_scalar_unary``` framework (and possibly supercedes it). There are three functions within the vectorisation framework, to handle the three types of unary vector functions mentioned above. 

The first, ```apply_vector_unary<T>::apply(x, f)```, is used for the ```f(vector) -> vector``` function type. Here, the template type ```T``` refers to the type of vector input (e.g. ```VectorXd``` or ```std::vector<std::vector<double>>```), ```x``` is the input vector, and ```f``` is the functor defining how the input vector should be manipulated. Using ```log_softmax``` as an example, this is how its use would look:
```
template <typename T>
inline auto log_softmax(const T& x) {
  return apply_vector_unary<T>::apply(x, [](auto& v){
    check_nonzero_size("log_softmax", "v", v);
    return v.array() - log_sum_exp(v);
  });
}
```
As you can see, very little code is added to the existing function, since the current implementation is simply wrapped inside a lambda expression at the call to ```apply_vector_unary<T>::apply()```.

The second function, ```apply_vector_unary<T>::reduce(x, f)```, is used for the ```f(vector) -> scalar``` function type. The use of this itself looks identical to that of ```apply_vector_unary<T>::apply()```, but the return type at the end is either a scalar or an ```std::vector``` of scalars (when a nested container is passed as an input). Using ```log_sum_exp``` as an example:
```
template <typename T>
inline auto log_sum_exp(const T& x) {
  return apply_vector_unary<T>::reduce(x, [](auto& v){
    if (v.size() == 0) {
      return -std::numeric_limits<double>::infinity();
    }

    const double max = v.maxCoeff();
    if (!std::isfinite(max)) {
      return max;
    }
    return max + std::log((v.array() - max).exp().sum());
  });
}
```

The third function, ```apply_vector_unary<T>::apply_scalar(x, y, f)```, is used for the ```f(vector, scalar) -> vector``` function type. This implementation allows for both an input vector ```x``` and additional scalar ```y``` to be used with the defined function ```f```. Additionally, when a nested container (e.g. ```std::vector<Eigen::VectorXd>```) is passed as the input vector, the additional scalar ```y``` can be either a single scalar, or a vector of scalars. Using ```head``` as an example:
```
template <typename T, typename T2>
inline auto head(const T& x, const T2& n) {
  return apply_vector_unary<T>::apply_scalar(x, n, [](auto& v, auto& m){
    if (m != 0){
      if (v.rows() == 1){
        check_column_index("head", "n", v, m);
      } else {
        check_row_index("head", "n", v, m);
      }
    }
    return v.head(m);
  });
}
```
# Drawbacks
[drawbacks]: #drawbacks

The only possible drawback (that's immediately apparent to me), is that these implementations all rely on the use of ```Eigen::Map``` to work with ```std::vector```s. This approach assumes that the combination of ```Eigen::Map``` + ```Eigen``` functions is faster than using standard library functions. Given ```Eigen```'s SIMD vectorisation and lazy evaluation, this feels like a safe bet, but there may be currently-unknown edge cases where this is not true.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

This approach was chosen as it requires minimal changes to existing vector functions (as seen above) and results in greatly-expanded functionality. If this approach is not used, the same functionality would require an additional specialisation for each vector type for each function, which would result in a not-insignificant maintenance burden.


# Prior art
[prior-art]: #prior-art

As mentioned earlier, this approach was largely inspired by the existing ```apply_scalar_unary``` vectorisation framework.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

The naming of these functions (```apply```, ```reduce```, ```apply_scalar```) might not be very intuitive, and so may need to be changed. There may also be other vector function types that I'm missing, and other vector input types that I'm not considering and should be added.

# Appendix

```apply_vector_unary``` code:
```
template <typename T, typename Enable = void>
struct apply_vector_unary {};

// Eigen types: Matrix, Array, Expression, other
template <typename T>
struct apply_vector_unary<T, require_eigen_t<T>> {
  template <typename F>
  static inline auto apply(const T& x, const F& f) {
    return f(x);
  }

  template <typename F, typename T2>
  static inline auto apply_scalar(const T& x, const T2& y, const F& f) {
    return f(x, y);
  }

  template <typename F>
  static inline auto reduce(const T& x, const F& f) {
    return f(x);
  }
};

// std::vector<T> types, where T is a scalar
template <typename T>
struct apply_vector_unary<T, require_std_vector_vt<is_stan_scalar, T>> {
  using scalar_t = scalar_type_t<T>;
  using map_t =
    typename Eigen::Map<const Eigen::Matrix<scalar_t,Eigen::Dynamic,1>>;

  template <typename F>
  static inline std::vector<scalar_t> apply(const T& x, const F& f) {
    Eigen::Matrix<scalar_t,Eigen::Dynamic,1> result
              = apply_vector_unary<map_t>::apply(as_column_vector_or_scalar(x), f);
    return std::vector<scalar_t>(result.data(), 
                                 result.data() + result.size());
  }

  template <typename F, typename T2>
  static inline std::vector<scalar_t> apply_scalar(const T& x, const T2& y, const F& f) {
    Eigen::Matrix<scalar_t,Eigen::Dynamic,1> result
              = apply_vector_unary<map_t>::apply_scalar(as_column_vector_or_scalar(x), y, f);
    return std::vector<scalar_t>(result.data(), 
                                 result.data() + result.size());
  }

  template <typename F>
  static inline scalar_t reduce(const T& x, const F& f) {
    return apply_vector_unary<map_t>::reduce(as_column_vector_or_scalar(x), f);
  }
};

// std::vector<T> types, where T is an Eigen type
template <typename T>
struct apply_vector_unary<T, require_std_vector_vt<is_eigen, T>> {
  using eigen_t = typename T::value_type;
  using scalar_t = typename eigen_t::Scalar;
  using return_t = std::vector<Eigen::Matrix<scalar_t,
                                              eigen_t::RowsAtCompileTime,
                                              eigen_t::ColsAtCompileTime>>;

  template <typename F>
  static inline return_t apply(const T& x, const F& f) {
    size_t x_size = x.size();
    return_t result(x_size);
    for(size_t i = 0; i < x_size; ++i)
      result[i] = apply_vector_unary<eigen_t>::apply(x[i], f);
    return result;
  }

  template <typename F, typename T2>
  static inline return_t apply_scalar(const T& x, const T2& y, const F& f) {
    scalar_seq_view<T2> y_vec(y);
    size_t x_size = x.size();
    return_t result(x_size);
    for(size_t i = 0; i < x_size; ++i)
      result[i] = apply_vector_unary<eigen_t>::apply_scalar(x[i], y_vec[i], f);
    return result;
  }

  template <typename F>
  static inline std::vector<scalar_t> reduce(const T& x, const F& f) {
    size_t x_size = x.size();
    std::vector<scalar_t> result(x_size);
    for(size_t i = 0; i < x_size; ++i)
      result[i] = apply_vector_unary<eigen_t>::reduce(x[i], f);
    return result;
  }
};

// std::vector<T> types, where T is an std::vector
template <typename T>
struct apply_vector_unary<T, require_std_vector_vt<is_std_vector, T>> {
  using scalar_t = scalar_type_t<T>;
  using return_t = typename std::vector<std::vector<scalar_t>>;
  using map_t =
    typename Eigen::Map<const Eigen::Matrix<scalar_t,Eigen::Dynamic,1>>;

  template <typename F>
  static inline return_t apply(const T& x, const F& f) {
    size_t x_size = x.size();
    return_t result(x_size);
    Eigen::Matrix<scalar_t,Eigen::Dynamic,1> inter;
    for(size_t i = 0; i < x_size; ++i){
      inter = apply_vector_unary<map_t>::apply(as_column_vector_or_scalar(x[i]), f);
      result[i] = std::vector<scalar_t>(inter.data(), 
                                        inter.data() + inter.size());
    }
    return result;
  }

  template <typename F, typename T2>
  static inline return_t apply_scalar(const T& x, const T2& y, const F& f) {
    scalar_seq_view<T2> y_vec(y);
    size_t x_size = x.size();
    return_t result(x_size);
    Eigen::Matrix<scalar_t,Eigen::Dynamic,1> inter;
    for(size_t i = 0; i < x_size; ++i){
      inter = apply_vector_unary<map_t>::apply_scalar(as_column_vector_or_scalar(x[i]), y_vec[i], f);
      result[i] = std::vector<scalar_t>(inter.data(), 
                                        inter.data() + inter.size());
    }
    return result;
  }

  template <typename F>
  static inline std::vector<scalar_t> reduce(const T& x, const F& f) {
    size_t x_size = x.size();
    std::vector<scalar_t> result(x_size);
    for(size_t i = 0; i < x_size; ++i)
      result[i] = apply_vector_unary<map_t>::reduce(as_column_vector_or_scalar(x[i]), f);

    return result;
  }
};

```
