- Feature Name: sparse_matrices
- Start Date: August 1st, 2019
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Add a sparse matrix type to the Stan language and sparse matrix operations to Stan math to utilize operations that can take advantage of the matrices sparsity structure.

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

Sparse matrix types in the Stan language can be constructed in the data block via [Coordinate List](https://en.wikipedia.org/wiki/Sparse_matrix#Coordinate_list_(COO)) notation using the row and column sizes, non-empty row/column indices, and values for those index positions. The non-zero (NZ) row and column indices are brought in as bounds in the `<>`. Setting these as bounds expands the definition of what can go into `<>` and should be discussed more.

```stan
data {
int N; // Rows
int M; // Cols
int K; // number non-empty
int nz_row_ind[K]; // Non-empty row positions
int nz_col_ind[K]; // Non-empty col positions

sparse_matrix<nz_rows=nz_row_ind nz_cols=nz_col_ind>[N, M] A
}
```

With proper IO the data sparsity pattern can be brought in automatically via a json or rdump list of lists.
```stan
data {
int N; // Rows
int M; // Cols
sparse_matrix[N, M] A
}
```

Though not necessary, we can also add sparse vectors.

```stan
int N; // Rows
int K; // number non-empty
int nz_row_ind[K]; // Non-empty row positions
// Can we do this?
sparse_vector<nz_rows=nz_row_ind>[N] B;
```

The above sparse matrix example with values

```stan
N = 5
M = 5
K = 7
// Column major order
nonzero_row_index[K] = [ 2, 3, 1, 3,  5, 3,  2, 5]
nonzero_col_index[K] = [ 1, 1, 2, 2,  3, 4,  5, 5]
val[K] =               [22, 7, 3, 5, 14, 1, 17, 8]
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
sparse_matrix<nz_rows=nz_row_ind, nz_cols=nz_col_ind>[N, M] A =
   to_sparse_matrix(N, M, nz_col_ind, nz_col_ind, vals);

// Linear Algebra is cool
sparse_matrix[N, N] C = A * A';
// For data this is fine
C[10, 10] = 100.0;
}
```

The assignment operation `C[10, 10] = 100.0;` works fine with Eigen as the implementation leaves room in the arrays for quick insertions. Though because the rest of Stan assumes the amount of coefficients are fixed this should be the only block where sparse matrix access to elements defined as zero valued in the bounds should be allowed.

Because the sparsity pattern is given in the bounds `<>` the above multiplication result `C` will have it's own sparsity pattern deduced from the result of `A * A'`. This is a concern of Eigen and Stan-math and I'm pretty sure would not need anything particular in the stan compiler.

## Parameters, Transformed Parameters, and Generated Quantities

Parameters can be defined as above for data or deduced from the output of other functions.

```stan
parameters {
  // Defining sparse matrices in parameters needs the non-zero elements
  sparse_matrix<nz_rows=nz_row_ind, nz_cols=nz_col_ind>[N, M] foo;
}
transformed parameters {
  // Non-zero elements are deduced by the operation on x
  sparse_matrix[N, N] K = cov_exp_quad(x, alpha, rho);
}

```

The size and non-zero indices for sparse matrices in the parameter block must be from either the data block or transformed data block. This is because Stan's I/O and posterior analysis infrastructure assumes the same sparsity pattern in each iteration of the model.

## Helper Functions

We can also include helper functions to extract the sparsity pattern's row and column information.

```stan
int K = num_nz_elements(x);
// Extract effectively a tuple representation of the sparse matrix.
matrix[K, 3] = get_nz_elements(x);
```

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

## I/O

Data can be read in from json via a list of lists and the Rdump from the equivalent.

```js
{
  ...
  {'col': 1, 'row': 20, 'val': 1.85},
  {'col': 11, 'row': 3, 'val': 2.71},
  ...
}
```

```R
X <- list(..., list(1, 20, 1.85), list(11, 3, 2.71),...)
```

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

Sparse matrices can be supported in Stan-math by either moving to more thorough templating along with pseudo-concepts in the metaprogramming or by having separate methods for Sparse Matrices.

#### The Hard way


Let's look at primitive add for an example. One implementation of `add` in Stan math is

```cpp
template <typename T1, typename T2, int R, int C>
inline Eigen::Matrix<return_type_t<T1, T2>, R, C> add(
    const Eigen::Matrix<T1, R, C>& m1, const Eigen::Matrix<T2, R, C>& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return m1 + m2;
}
```

We can use a form of pseudo-concepts to write something like the following for functions which share the same Eigen dense and sparse methods.

```cpp
template <typename Mat1, typename Mat2, all_eigen_type<Mat1, Mat2>>
inline auto add(Mat1&& m1, Mat2&& m2) {
  check_matching_dims("add", "m1", m1, "m2", m2);
  return (m1 + m2).eval();
}
```

In the above, the return type without the `.eval()` will be something of the form `Eigen::CwiseBinaryOp<...>` which all of the other math functions would have to also take in. Adding a `.eval()` at the end will force the matrix to evaluate to either a sparse or dense matrix. Once more of Stan math can take in the Eigen expression types we can remove the `.eval()` at the end.

For places where the sparse and dense operations differ we can have dense/sparse matrix template specializations. There has been a lot of discussion on this refactor in the past (see [this](https://groups.google.com/forum/#!topic/stan-dev/ZKYCQ3Y7eY0) Google groups post and [this](https://github.com/stan-dev/math/issues/62) issue). Though looking at the two forms it seems like using `A.coeff()` for access instead of `operator()` would be sufficient to handle the coefficient access error Dan saw.


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

`SimplicalCholeskybase` keeps the permutation matrix, when the user does a cholesky decomposition we can pull out this permutation matrix and keep it to use in the next iteration. We do this through `EIGEN_SPARSEMATRIX_BASE_PLUGIN`, adding the permutation matrix to the input matrix. This adds a bit of state, but assuming the sparse matrices are fixed in size and sparsity this should be fine.

# Drawbacks
[drawbacks]: #drawbacks

Doing this improperly could lead to serious amounts of "code smell" aka duplicated code, confusing templates, etc.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?

This is the most full fledged design that seems to have a reasonable consensus so far.

- What other designs have been considered and what is the rationale for not choosing them?

There are two other designs possible for the stan language. within the `[]` operator or as a new concept called an attribute.

```stan
// with operator[]
sparse_matrix[N, M, nz_rows_ind, nz_cols_ind, vals] A;

// With attribute
@sparse(nz_rows=nz_rows_ind, nz_cols=nz_cols_ind) Matrix[N, M] A;
```

The attribute method would require it's own design document, though it would allow a separation between computational and statistical concerns. Multiple attributes could also be placed into a tuple such as

```stan
(@sparse(nz_rows=nz_rows_ind, nz_cols=nz_cols_ind), @opencl) Matrix[N, M] A;
```

Another alternative would be to extend the `csr_*` functions, though this requires a lot of recomputation.

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
- [Sparse Matrices discussion that took over anothe thread](https://discourse.mc-stan.org/t/stancon-cambridge-developer-meeting-opportunities/9743/46?u=stevo15025)

### Tensorflow

Tensorflow uses the same data storage schema inside of [`tf.sparse.SparseTensor`](https://www.tensorflow.org/versions/r2.0/api_docs/python/tf/sparse/SparseTensor) with a limited amount of specific [methods](https://www.tensorflow.org/api_docs/python/tf/sparse). It does not seem that they have [Sparse Cholesky support](https://github.com/tensorflow/tensorflow/issues/15910).

It seems like OpenAI has methods like matrix multiplication for block sparse matrices (Sparse matrices with dense sub-blocks) in tensorflow available on [github](https://github.com/openai/blocksparse).

### Keras

Both Keras and Tensorflow Sparse support is very [low level](https://stackoverflow.com/a/43188970). Though it seems like work is going on for RaggedTensors and SparseTensors in [Keras](https://github.com/tensorflow/tensorflow/issues/27170#issuecomment-509296615).

### MxNet

MxNets [`portri`](https://mxnet.incubator.apache.org/api/python/symbol/linalg.html#mxnet.symbol.linalg.potrf) (Cholesky) function can handle sparse arrays, but there is not a lot of documentation saying that explicitly. Besides that they also store things in the compressed storage schema.

### PyTorch

Pytorch has an experimental section for limited sparse tensor operations in [`torch.sparse`](https://pytorch.org/docs/stable/sparse.html).


### Template Model Builder (TMB)

TMB uses a forked version of ADcpp for auto-diff and from their arvix paper seems to include sparse matrix types as well. Arvix [here](https://arxiv.org/pdf/1509.00660.pdf).

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?

- Language Design
- How this will work with the new Stan compiler?
- Right now it appears the need for the same number of coefficients in each iteration is because of historically how we have done our analysis stuff. Are there also statistical concerns?
- Will the cost of the refactor of Stan math to a more generic form be worth it?.
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
