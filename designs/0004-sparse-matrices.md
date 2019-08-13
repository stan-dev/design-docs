- Feature Name: sparse_matrices
- Start Date: August 1st, 2019
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Add a sparse matrix type to the Stan language and sparse matrix operations to Stan-math to utilize operations that can take advantage of the sparsity structure.

# Motivation
[motivation]: #motivation

Data for models such as [ICAR](https://mc-stan.org/users/documentation/case-studies/icar_stan.html) come in as sparse matrix. (i.e. a large number of elements in the matrix are zero). There are often methods for storing and computing these matrices which utilize the sparsity structure to give better performance and use less memory. Currently we have some Compressed Sparse Row (CSR) [methods](https://mc-stan.org/docs/2_19/functions-reference/sparse-matrices.html) for going from dense matrices to simpler representations that ignore zeros and vice versa. Though the only exposed operation is [`csr_matrix_times_vector`](https://mc-stan.org/docs/2_19/functions-reference/sparse-matrix-arithmetic.html). The CSR methods currently supported are limited and require a good deal of fan-dangling from the user.

A `sparse_matrix` type directly in the stan language would support all existing methods available for `matrix` types. From Dan and Aki's previous [proposal](https://aws1.discourse-cdn.com/standard14/uploads/mc_stan/original/2X/1/13fda4102c8f48e5aadbf0fbe75d3641a187d0a3.pdf) this would include full auto-diff and algebra support for:

- Addition (returns sparse matrix, possibly with different sparsity structure)
- Sparse matrix transpose (returns sparse matrix, different sparsity structure)
- Sparse matrix-vector multiplication (returns dense vector)
- Sparse matrix-constant multiplication (returns sparse matrix, same sparsity)
- Sparse matrix-matrix multiplication (returns a sparse matrix that likely has a different sparsity structure)
- Sparse matrix-dense matrix multiplication (should return a dense matrix)
- Sparse matrix-diagonal matrix multiplication on the left and right (returns sparse matrix, same sparsity)
- Sparse inner product and quadratic form (returns scalars)
- Operations to move from sparse to dense matrices and vice versa.
- Fill-reducing reorderings
- A sparse Cholesky for a matrix of doubles.
- The computation of the log-determinant as the product of Cholesky diagonals
- Sparse linear solves and sparse triangular solves (for sampling from the marginalized out parameters in the generated quantities block)
- Sparse algorithms to compute the required elements of the inverse.
- An implementation of the reverse mode derivative of the log determinant
- Reverse-mode derivative of a Cholesky decomposition of a sparse matrix.
  - This is the same algorithm that was initially used in the dense case before Rob implemented Iain Murray’s blocked version. But it will need to be implemented in a “data structure” aware way
- Specialization for Poisson, binomial and maybe gamma likelihoods.

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Most of the below comes from the [functional-spec](https://github.com/stan-dev/stan/wiki/Functional-Spec:-Sparse-Matrix-Data-Types) for sparse matrices.

A sparse matrix/vector differs from a standard matrix/vector only in the underlying representation of the data.

Below we go over how sparse matrices can be constructed and operated on within each stan block.


## Data

Sparse matrix types in the Stan language can be constructed in the data block via [Coordinate List](https://en.wikipedia.org/wiki/Sparse_matrix#Coordinate_list_(COO)) notation using the row and column sizes, non-empty row/column indices, and values for those index positions.

```stan
data {
int N; // Rows
int M; // Cols
int K; // number non-empty
int nonzero_row_index[K]; // Non-empty row positions
int nonzero_col_index[K]; // Non-empty col positions
vector[N] vals; // Values in each position
// Direct way
sparse_matrix[N, M, nonzero_row_index, nonzero_col_index, vals] A
// Can we do this?
sparse_matrix[N, M, nonzero_row_index, nonzero_col_index] B;
}
```

Sparse vectors are the same only with a single size on a single index array.

```stan
int N; // Rows
int K; // number non-empty
int nonzero_row_index[K]; // Non-empty row positions
vector[N] vals; // Values in each position
// Direct way
sparse_matrix[N, nonzero_row_index, val] A
// Can we do this?
sparse_vector[N, nonzero_row_index] B;
```

The above sparse matrix example with values

```stan
N = 5
M = 5
K = 7
// Column major order
nonzero_row_index[K] = [2, 3, 1, 3, 5, 3, 2, 5]
nonzero_col_index[K] = [1, 1, 2, 2, 3, 4, 5, 5]
val[K] = [22, 7, 3, 5, 14, 1, 17, 8]
```

Would have the dense form of

| col/row | 1  | 2 | 3  | 4 | 5  |
|---------|----|---|----|---|----|
| 1       | 0  | 3 | 0  | 0 | 0  |
| 2       | 22 | 0 | 0  | 0 | 17 |
| 3       | 7  | 5 | 0  | 1 | 0  |
| 4       | 0  | 0 | 0  | 0 | 0  |
| 5       | 0  | 0 | 14 | 0 | 8  |

## Transformed Data

Sparse matrices in this block can be defined dynamically and declared such as

```stan
transformed data {
// Could construct here as well
sparse_matrix[N, M, nonzero_row_index, nonzero_col_index] A =
   to_sparse_matrix(N, M, nonzero_row_index, nonzero_col_index, vals);

// Linear Algebra is cool
sparse_matrix[N, N] C = A * A';
// For data this is fine
C[10, 10] = 100.0;
}
```

The assignment operation `C[10, 10] = 100.0;` works fine with Eigen as the implementation leaves room in the arrays for quick insertions.

## Parameters, Transformed Parameters, and Generated Quantities

Parameters be defined as above for data or deduced from the output of other functions.

```stan
data {
  int<lower=1> N; // Rows
  int<lower=1> M; // Cols
  int<lower=1, upper=N> K; // # of nonzero elements
  int<lower=1> non_zero_x_index[K]; // Indices for nonzero elements
  int<lower=1> nz_foo_row_index[K]; // Indices for nonzero elements
  int<lower=1> nz_foo_col_index[K]; // Indices for nonzero elements

  sparse_vector[N, non_zero_index] x;
}
parameters {
  real<lower=0> rho;
  real<lower=0> alpha;
  real<lower=0> sigma;
  // Defining sparse matrices in parameters needs the non-zero elements
  sparse_matrix[N, M, nz_foo_row_index, nz_foo_col_index] foo;
}
transformed parameters {
  // Non-zero elements are deduced by the operation on x
  sparse_matrix[N, N] K = cov_exp_quad(x, alpha, rho);
}

```

The size and non-zero indices for sparse matrices in the parameter block must be from either the data block or transformed data block. This is because Stan's I/O and posterior analysis infrastructure assumes the same full specification in each iteration of the model.

## Full Example Model

Below is a full example model that uses sparse vectors and matrices for data and parameters for a gaussian process.

```stan
data {
  int<lower=1> N; // Vec size
  int<lower=1, upper=N> K; // # of nonzero elements
  int<lower=1> non_zero_index[K]; // Indices for nonzero elements
  sparse_vector[N, non_zero_index] x;
  vector[N] y;
}
transformed data {
  sparse_vector[N] mu = rep_sparse_vector(0, N, non_zero_index); // [1]
}
parameters {
  real<lower=0> rho;
  real<lower=0> alpha;
  real<lower=0> sigma;
}
model {
  sparse_cholesky_matrix[N] L_K; // [2]
  sparse_matrix[N, N] K = cov_exp_quad(x, alpha, rho);
  real sq_sigma = square(sigma);

  // Assign to pre-existing diagonal
  for (n in 1:N)
    K[n, n] = K[n, n] + sq_sigma;

  L_K = cholesky_decompose(K);

  rho ~ inv_gamma(5, 5);
  alpha ~ std_normal();
  sigma ~ std_normal();

  y ~ multi_normal_cholesky(mu, L_K);
}
```

- [1] Because Stan is told what values are true zeros vs. sparse zeros we can set this up fine.

- [2] The `sparse_cholesky_matrix` is optional and holds the permutation of the sparse matrix after decomposition using the `EIGEN_SPARSEMATRIX_BASE_PLUGIN`. Permuting the rows of the sparse matrix before decomposition can often increase performance. Instead of having to recompute the permutation on each call to `cholesky_decompose`, after the first iteration we can keep the [`PermutationMatrix`](https://eigen.tuxfamily.org/dox/classEigen_1_1SimplicialCholeskyBase.html#aff1480e595a21726beaec9a586a94d5a) inside of the `sparse_cholesky_matrix` and reuse it on subsequent operations.


# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

## I/O

Data input formats should not need to change, less R and Python want a particular method that does not exist at this time.

At the C++ level input data can be constructed to the sparse matrix through soemthing like what Ben did [here](https://github.com/stan-dev/rstanarm/blob/master/inst/include/csr_matrix_times_vector2.hpp#L18) for a revised `csr_matrix_times_vector`.

```cpp
int outerIndex[cols+1];
int innerIndices[nnz];
double values[nnz];
// read-write (parameters)
Map<SparseMatrix<double>> sm1(rows, cols, nnz, outerIndex, innerIndices, values);
// read only (data)
Map<const SparseMatrix<double>> sm2(rows, cols, nnz, outerIndex, innerIndices, values);   
```

## Stan Math

### Templating

There are two approaches to have Stan support Eigen's Sparse Matrix format.

#### The Hard way

Sparse matrices can be supported in Stan-math by either moving to `EigenBase` as the default in the metaprogramming or by having separate methods for Sparse Matrices.

Let's look at primitive add for an example. One implementation of `add` in Stan math is

```cpp
template <typename T1, typename T2, int R, int C>
inline Eigen::Matrix<return_type_t<T1, T2>, R, C> add(
    const Eigen::Matrix<T1, R, C>& m1, const Eigen::Matrix<T2, R, C>& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return m1 + m2;
}
```

Would change to

```cpp
template <typename Derived1, typename Derived2>
inline Eigen::PlainObjectBase<return_derived_obj<Derived1, Derived2>> add(
    const Eigen::EigenBase<Derived1>& m1, const Eigen::EigenBase<Derived2>& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return m1 + m2;
}
```

Where `return_derived_obj` would deduce the correct derived return type based on the `Scalar` value of the `Derived*` types. This is nice because for places where Eigen supports both dense and sparse operations we do not have to duplicate code. For places where the sparse and dense operations differ we can have sparse matrix template specializations. There has been a lot of discussion on this refactor in the past (see [this](https://groups.google.com/forum/#!topic/stan-dev/ZKYCQ3Y7eY0) Google groups post and [this](https://github.com/stan-dev/math/issues/62) issue). Though looking at the two forms it seems like using `A.coeff()` for access instead of `operator()` would be sufficient to handle the coefficient access error Dan saw.

### The Simple Way

If we would rather not refactor the math library we can keep our current templates and have specializations for Sparse matrices.

```cpp
template <typename T1, typename T2>
inline Eigen::SparseMatrixBase<return_type_t<T1, T2>> add(
    const Eigen::SparseMatrixBase<T1>& m1, const Eigen::SparseMatrixBase<T2>& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return m1 + m2;
}
```

### Keeping Permutation Matrix from Cholesky

`SimplicalCholeskybase` keeps the permutation matrix, when the user uses a `sparse_cholesky_matrix` we can pull out this permutation matrix and keep it to use in the next iteration. We do this through `EIGEN_SPARSEMATRIX_BASE_PLUGIN`, adding the permutation matrix to the input matrix. This adds a bito of state, but assuming the sparse matrices are fixed in size and sparsity this should be fine.

# Drawbacks
[drawbacks]: #drawbacks

Doing this improperly could lead to serious amounts of "code smell" aka duplicated code, confusing templates, etc.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?

This is the most full-feature design I can think of that makes sparse matrices simple for stan users while giving the stan-math library a lot of flexibility.

- What other designs have been considered and what is the rationale for not choosing them?

Instead of the full feature spec like the above we could have sparse_matrix only be a result type

```stan
parameters {
  real theta_raw[K];
...
model {
  sparse_matrix[M, N] theta = to_sparse_matrix(M, N, mm, nn, theta_raw);
  ...
```

Or alternativly we can extend the `csr_*` functions, though this requires a lot of recomputation.

- What is the impact of not doing this?

Kind of a bummer, it will be awkward for users to fit models whose data or parameters are sparsely defined.

# Prior art
[prior-art]: #prior-art

There has been a _lot_ of previous discussion about sparse matrices in Stan which are listed below in no particular order.

- [Sparse Matrix Roadmap](https://discourse.mc-stan.org/t/sparse-matrix-roadmap/5493/24)
- [Sparse Matrix Functionality without the Sparse Matrix](https://discourse.mc-stan.org/t/sparse-model-matrix-functionality-without-the-sparse-matrix/5759)
- [Spline Fitting Demo in Comparison of Sparse Vs. Non-Sparse](https://discourse.mc-stan.org/t/spline-fitting-demo-inc-comparison-of-sparse-vs-non-sparse/3287)
- [Should Sparse Matrices in Stan be Row Major or Column Major](https://discourse.mc-stan.org/t/should-sparse-matrices-in-stan-be-row-major-or-column-major/1563)
- [A Proposal for Sparse Matrices and GPs in Stan](https://discourse.mc-stan.org/t/a-proposal-for-sparse-matrices-and-gps-in-stan/2183)
- [Sparse Matrix Use Cases (Resolving Declaration Issues)](https://discourse.mc-stan.org/t/a-proposal-for-sparse-matrices-and-gps-in-stan/2183)
- [Sparse Matrices in Eigen with Autodiff](https://discourse.mc-stan.org/t/sparse-matrices-in-eigen-with-autodiff/3324/6)
- [Sparse Matrix Functional Spec](https://discourse.mc-stan.org/t/sparse-matrix-functional-spec/109)
- [Sparse Matrices in Stan](https://discourse.mc-stan.org/t/sparse-matrices-in-stan/3129)

### Tensorflow

Tensorflow uses the same data storage schema inside of [`tf.sparse.SparseTensor`](https://www.tensorflow.org/versions/r2.0/api_docs/python/tf/sparse/SparseTensor) with a limited amount of specific [methods](https://www.tensorflow.org/api_docs/python/tf/sparse). It does not seem that they have [Sparse Cholesky support](https://github.com/tensorflow/tensorflow/issues/15910).

It seems like OpenAI has methods like matrix multiplication for block sparse matrices (Sparse matrices with dense sub-blocks) in tensorflow available on [github](https://github.com/openai/blocksparse).

### Keras

Both Keras and Tensorflow Sparse support is very [low level](https://stackoverflow.com/a/43188970). Though it seems like work is going on for RaggedTensors and SparseTensors in [Keras](https://github.com/tensorflow/tensorflow/issues/27170#issuecomment-509296615).

### MxNet

MxNets [`portri`](https://mxnet.incubator.apache.org/api/python/symbol/linalg.html#mxnet.symbol.linalg.potrf) (Cholesky) function can handle sparse arrays, but there is not a lot of documentation saying that explicitly. Besides that they also store things in the compressed storage schema.

### PyTorch

Pytorch has an experimental section for limited sparse tensor operations in [`torch.sparse`](https://pytorch.org/docs/stable/sparse.html).


It looks like sparse matrices has been difficult for a lot of groups!

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?

- Language Design
- How this will work with the new Stan compiler?
  - Can we deduce the sparse matrix non-zero indices for some functions like I have in the above?
- Will the cost of the refactor of Stan math to EigenBase worth it?.
- Any prior art that I've missed?


# Appendix: (Eigen Sparse Matrix formats)

From the Eigen [Sparse Matrix Docs](https://eigen.tuxfamily.org/dox/group__TutorialSparse.html), Eigen matrices use a Compressed Column Scheme (CCS) to represent sparse matrices.

Sparse matrices in Eigen are stored using four compact arrays.

> Values: stores the coefficient values of the non-zeros.

> InnerIndices: stores the row (resp. column) indices of the non-zeros.

> OuterStarts: stores for each column (resp. row) the index of the first non-zero in the previous two arrays.

> InnerNNZs: stores the number of non-zeros of each column (resp. row). The word inner refers to an inner vector that is a column for a column-major matrix, or a row for a row-major matrix. The word outer refers to the other direction.

| row/col | 0  | 1 | 2  | 3 | 4  |
|---------|----|---|----|---|----|
| 0       | 0  | 3 | 0  | 0 | 0  |
| 1       | 22 | 0 | 0  | 0 | 17 |
| 2       | 7  | 5 | 0  | 1 | 0  |
| 3       | 0  | 0 | 0  | 0 | 0  |
| 4       | 0  | 0 | 14 | 0 | 8  |

| Inner Values:  |----|---|---|---|---|----|---|---|---|---|----|---|
|----------------|----|---|---|---|---|----|---|---|---|---|----|---|
| Values:        | 22 | 7 | _ | 3 | 5 | 14 | _ | _ | 1 | _ | 17 | 8 |
| InnerIndices:  | 1  | 2 | _ | 0 | 2 | 4  | _ | _ | 2 | _ | 1  | 4 |

| Meta Info:   |---|---|---|---|----|----|
|--------------|---|---|---|---|----|----|
| OuterStarts  | 0	| 3	| 5	| 8	| 10 | 12 |
| InnerNNZs    | 2	| 2	| 1	| 1	| 2  |    |

The `_` indicates available free space to insert new elements. In the above example, 14 sits in the 4th column index (`InnerIndices`) while the 4th column index has 10 (`OuterStarts`) non-zero elements before it (there are 10 including the free space `_` for new elements) The 1st column in the above above has 2 (`InnerNNZs`) elements that are nonzero. The above allows for elements to be inserted inside of the sparse matrix, but can be compressed further with `makeCompressed()`

|Compressed Vals:|----|---|---|---|----|---|----|---|
|----------------|----|---|---|---|----|---|----|---|
| Values:        | 22 | 7 | 3 | 5 | 14 | 1 | 17 | 8 |
| InnerIndices:  | 1  | 2 | 0 | 2 | 4  | 2 | 1  | 4 |

|Meta Info:    |---|---|---|---|---|---|
|--------------|---|---|---|---|---|---|
| OuterStarts: | 0 | 2 | 4 | 5 | 6 | 8 |

This is now in the Compressed Row Format (CRF) where value 14 sits in the 4th row index where the 4th row index has six non-zero elements before it.
