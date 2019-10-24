- Feature Name: opencl_kernel_generator
- Start Date: 2019-10-21
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Define operators and functions on matrix_cl that will use 
[expresson templates](https://en.wikipedia.org/wiki/Expression_templates) 
to construct expressions. When assigned to a matrix_cl an expression will generate an 
OpenCL kernel an execute it to calculate the result of the expression.

# Motivation
[motivation]: #motivation

Using expression templates is much simpler than writing OpenCL kernels by hand and it does 
not require knowledge of OpenCL and parallel programming.

Using one kernel for multiple operations is faster than using one kernel per operation. Each 
kernel must load its arguments from global global GPU memory and store results back. Memory 
transfers are relatively slow compared to calculations. In case of simple kernels majority 
of kernel execution time is spent for memory transfers.  

While not any kernel can be rewritten with kernel generator, many, if not most of ones 
needed in Stan Math should qualify.  

# Explanation
[guide-level-explanation]: #explanation

A kernel generator expression consists of operations, for example addition. While not 
operations in mathematical sense, accesses to matrices and scalars are also operations 
in kernel generator.

Each operation is implemented as a templated class. When instantiated those templates are given
types of the subexpressions that are arguments to the particular operation. User-facing 
functions are used to simplify construction of operations, since class templates can not 
be deduced in C++14. 

Each operation object is responsible for generating kernel code for the operation it 
represents. Each operation selects a unique variable name and generates kernel code that 
declares a variable and assigns the result of the operation to it. If the operation has any
arguments that are operations themselves it can access variables they use for their results.
If the operation needs any other data it can specify kernel arguments. For example an operation 
that accesses a matrix might need a pointer to matrix data and size of the matrix.

Some operations can also be used in expressions that are assigned to. The most basic case 
is access to matrix - i.e. storing the result of a kernel. Such operations can also generate
kernel code for appearing on the left-hand-side of assignment. While the code is different the
process of generating it is similar to generating code for an operation on the right-hand side 
of an assignment.

Kernel generator expressions can consist of operations, matrices and scalars. Operations have
appropriate methods for constructing kernel source. Matrices and scalars on the other hand do 
not. So they need to be wrapped in appropriate wrapper that is an operation whenever they are
used in a kernel generator expression.

If an expression is used multiple times the kernel associated with it should be cached. So 
regeneration and recompilation of kernel is not necessary at every time an expression is 
evaluated. Instead kernel is generated only at first use. Cached kernel can also be reused
between instances of expressions consisting of same operands, but operating on different data, 
even if the matrices have different sizes.


#### Example

```c++
matrix_cl<double> a, b;
double c;
matrix_cl<double> d = c * (a + b);
```

In this example `a` and `b` are first wrapped in a matrix access operation. This happens within
the operator+. This operator returns an addition object that references its parameters. 
operator* Wraps scalar in scalar accessing operation and constructs multiplication object that 
references that and the addition as its arguments. When assigned to a matrix the expression 
generates opencl kernel. Matrix access operations load matrix elements. Addition adds them together.
Multiplication multiplies the result with the scalar. `d`'s wrapper generates code for storing the 
back to global memory. 

# Drawbacks
[drawbacks]: #drawbacks

Even with caching each kernel must be compiled the first time it is used. If many kernels are used and each only once, long compilations times could make this slower than one kernel per operation. This is not an issue in Stan, since many leapfrog steps are executed.

# Prior art
[prior-art]: #prior-art

Expression templates are widely used in Eigen.

Tensorflow XLA is experimental kernel fusion feature of Tensorflow.
