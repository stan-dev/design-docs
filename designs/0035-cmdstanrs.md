- Feature Name: cmdstanrs
- Start Date: 2023-11-22
- RFC PR:
- Stan Issue:

# Summary
[summary]: #summary

This is a proposal for a Rust interface for CmdStan through compiled
executables, that is, no direct interface with C++.

The goal is to provide an interface which enables users to:
- compile Stan programs (with arbitrary options)
- build and compose arguments/options (to be passed to C++
  executables) in idiomatic Rust
- call C++ executables, then memoize input and collect output (thereby
  making these available for programmatic use)
- call `diagnose` and `stansummary` tools and collect output

The objective is to keep the interface as simple as possible.

# Motivation
[motivation]: #motivation

Suppose that you write Rust code. Suppose that you use `Stan` for
probabilistic programming. You have three choices for creating an
application which utilizes both: shell scripts, introduce a scripting
language (e.g. Python) dependency, or a Rust interface for `CmdStan`.

Orchestration using the shell suffers from portability issues and
often leads unnecessary fragmentation of control flow. Introducing a
scripting language may confer portability, but control flow and error
handling are now divided between two languages; furthermore, this
necessitates code be written to serialize/deserialize intermediates.

A Rust interface, in similar spirit to the CmdStan interfaces from
other languages, would provide the necessary abstraction to eliminate
the aforementioned problems.

# Functional Specification

Given a Stan program, a user of the library will compile the model (if
desired), call the executable with arguments (translated from
strongly-typed argument tree), and obtain a self-contained context
which encapsulates the pertinent information from the call.

### Assumptions

We assume (at our peril) that Rust programmers that will be able to
figure out how to satisfy the following requirement:
- a working CmdStan installation exists at some user-accessible path

### Processes, IO

The proposal is to use the Rust `std` library, in particular the
[process](https://doc.rust-lang.org/std/process/index.html),
[path](https://doc.rust-lang.org/std/path/index.html),
[fs](https://doc.rust-lang.org/std/fs/index.html), and
[ffi](https://doc.rust-lang.org/std/ffi/index.html) modules, to
orchestrate processes, interact with file system and handle
cross-platform concerns. This will yield a library which is portable,
provided that it is (cross-)compiled for the intended target.

## Control: compilation and calling the resultant executable

A `CmdStanModel` type will serve as an abstraction for a Stan program,
which may need to be compiled. Rather than compile on construction, a
compilation method must be explicitly called in user code (assuming
that a satisfactory executable does not exist yet).

Two arguments will be necessary to create a `CmdStanModel`:
1. a path to a CmdStan installation
2. a path to a Stan program

Methods (receiver: `CmdStanModel` instance) exposed to the user will
include:
- `validate_cmdstan` : determine whether the CmdStan installation works
- `executable_works` : is there a working executable at the path
  implied by the Stan file?
- `compile_with_args` : attempt to compile a Stan program with
  optional `make` arguments
- `call_executable` : call executable with the given argument tree; on
  success, return a `CmdStanOutput` instance.

## Output

Output of a successful `call_executable` call on a `CmdStanModel` will
produce a `CmdStanOuput` instance, which encapsulates the context of
the call. This includes:
- the console output (exit status, stdout and stderr),
- the argument tree provided to `call_executable`
- the current working directory of the process at the time the call was made
- the CmdStan installation from the parent `CmdStanModel`

The objective is for `CmdStanOutput` to be a self-contained record
which includes all pertinent information from a successful executable
call. This structure can then be used to direct calls of
`diagnose`/`stansummary`. Naturally, methods on said type will be
present to expose the context to the user and perform utility
functions (e.g. return a list of output file paths).

## Arguments and options

Stan provides several inference engines, each with a large number of
options. CmdStan in turn handles this heterogeneity.

To encapsulate the arguments passed at the command line (to a compiled
executable), the proposal is a strongly-typed representation of this
heterogeneity using a combination of sum types (Rust `enum`) and
product types (Rust `struct`). By construction, this representation
prevents the formation of inconsistent argument combinations -- the
code simply won't compile. The resultant tree is an abstraction which
enables the use of a single type (`CmdStanOutput`) to encapsulate a
call to an executable.

Unsurprisingly, the argument tree is a syntax tree for CmdStan
command arguments. We translate to the very simple command line
language, but leave open the possibility of translation to other
languages.

### Translation

The (sloppy) productions for the command line language are:
```text
tree    -> terms
terms   -> terms " " term | term
term    -> pair | product | sum
pair    -> key "=" value
product -> type " " pairs
sum     -> type "=" variant " " terms | type "=" variant
pairs   -> pairs " " pair | pair

key     -> A
A       -> A alpha | beta
alpha   -> letter | digit | "_"
beta    -> letter
letter  -> "A" | ... | "z"
digit   -> "0" | ... | "9"

value   -> number | path
```
Where the productions for `number` and `path` are left out for
brevity.  The start symbol is `tree`. Generate the command line
statement by folding the tree from left to right by generating the
appropriate term from each node, building up a linear argument list.
I sketched
[this](https://github.com/andrewjradcliffe/cmdstan-translator/blob/main/translate.scm)
out in Scheme, why I am not sure.

### Ergonomics

Philosophy:
- pay (in LOC) for only what you need.
- minimize differences between naming of the types and fields (see
  below) in the Rust implementation and CmdStan.

The builder pattern will be implemented for each `struct`, and for
each `enum` variant (excluding unit variants). This enables the user
to supply only the arguments for which they desire non-default
values. This leads to succinct code when one needs only the defaults
([example](https://github.com/andrewjradcliffe/cmdstan-rs/blob/main/examples/bernoulli-many/main.rs)).

#### A side effect of strong typing

With [company-mode](https://github.com/company-mode/company-mode) and
[eglot-mode](https://github.com/joaotavora/eglot)
([lsp-mode](https://github.com/emacs-lsp/lsp-mode/) also works) in
Emacs 28.2, one can view options at each node in the argument tree by
code that looks something like the following:

```rust
ArgumentTree::builder(). // hover on the `.`
```

If one has a Rust language server and completion support in their
editor, this is a free side effect. Whether it will help anyone
is uncertain.

### Coverage

The objective is for the interface to cover all options which can be
passed to a compiled Stan program, that is, all methods and all
options for said methods.

## Separation of concerns

Other than the argument tree support, the interface proposed is very
simple: the user can compile a Stan program, call it with arguments,
get basic information from the output, and call
`diagnose`/`stansummary`.

Below, I provide the rationale for exclusion of two aspects. My
judgment is that they are useful, but are best developed separately.

### Serialization

It is trivial to provide a function such as 
```rust
fn write_json<T: Serialize>(data: &T, file: &Path) {}
```
but it serves no purpose -- it does not enforce the conventions
adopted for representing Stan data types in JSON (e.g. matrices
represented as a vector of *row* vectors, not a vector of *column*
vectors), hence, would likely lead to unexpected (and potentially
silent!) errors.

In order to develop a serializer which respects the conventions for
Stan data types, one would need to declare conventions for the mapping
of Rust data types to Stan data
types. [serde_json](https://github.com/serde-rs/json) would be nice to
use, but has some incompatibilities (Rust tuple is represented as an
array, rather than an object).

Moreover, to represent matrices, complex numbers, etc., one would need
to support types from the crate ecosystem since the standard library
lacks these -- [nalgebra](https://github.com/dimforge/nalgebra) and
[num-complex](https://github.com/rust-num/num-complex) are reasonable
choices, but nonetheless represent decisions to be made!

From a design perspective, this is a great place to defer to the user,
at least for the moment. A principled approach would involve writing a
data format for [serde](https://serde.rs/).

### Deserialization

Parsing Stan CSVs to a strongly-typed representation is simple if one
wishes to simply obtain a matrix of values (or `Vec<Vec<f64>>` if we
limit ourselves to `std` library types). However, one needs to extract
the variables from each line, thus, one needs to know the types (and
their dimensions). A recursive definition of types using `enum`s and
`struct`s could probably work to represent such a thing in Rust, but
may not necessarily be particularly ergonomic (i.e. much unavoidable
boilerplate would be needed to use the resultant type).

Procedural macros, applied to a Stan program stored in a string
literal in a Rust program, could be used to generate types and a
parser for Stan CSVs produced said program. However, in order to
implement such an idea, one would first need to adopt conventions for
representing Stan data types using Rust data types. This requires
careful thought and and is something best left for the future, if
ever.

The current proposal is for `CmdStanOutput` to be capable of returning
paths to the files and the user parses them however they desire.
This leaves open the possibility of multiple parsing strategies.

# Drawbacks
[drawbacks]: #drawbacks

Representing CmdStan arguments/options as a concrete syntax tree is
potentially brittle. If the CmdStan grammar undergoes radical change,
this interface will need to change accordingly. However, the CmdStan
grammar is intended to be quite stable. Moreover, it is not
necessarily the case that radical changes to the CmdStan grammar could
be hidden behind something other abstraction.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

Other than the direct representation of the CmdStan syntax tree, the
proposal contains nothing new. Utilizing a concrete representation of
the syntax tree does have benefits:
- all outputs handled via single type `CmdStanOutput`
- elimination of individual structures and methods for each of Stan's
inference algorithms

The question remains: is this is a good idea?

## Argument tree considerations

As described above, the grammar for CmdStan arguments passed at the
command line can be represented as a syntax tree through the use of
sum and product types.
- This enables compile-time validation of argument consistency -- the
  worst that can happen is you provide a value that CmdStan does not
  like (e.g. `num_threads=-20`).
- At minimum, this will move a variety of run-time errors to compile
  time; it might even help users to understand the methods and options
  CmdStan provides.
- This enables re-use of a parameterized argument tree -- one could
  replace the inference method while leaving the other options
  (e.g. data files) constant. As shown in [this
  example](https://github.com/andrewjradcliffe/cmdstan-rs/blob/main/examples/bernoulli-many/main.rs),
  such an approach can be quite expressive.

Furthermore, representation as a concrete syntax tree enables the
possibility of interesting features. One could parse the syntax tree
from:
- a string written to a log file
- a string which is consistent with the grammar that CmdStan accepts

The latter is interesting in that a user's extant command line input
is all that is required to use the Rust interface. For example,
this leads to the following syntax:

```rust
// Assuming we implemented this through the `FromStr` trait
let tree: ArgumentTree = "method=sample data file=bernoulli.data.json".parse().unwrap();
```

This would substantially lower the barrier to adoption of the Rust
interface as the user need only know what they are already doing.

Due to Rust's orphan rules, such features would need to be implemented
within this crate; they could be placed behind a feature gate to
minimize compile time. It stands to reason that if we can translate to
a string, we should be able to perform the inverse operation.

The design philosophy here would be: a valid parse is whatever CmdStan
is willing to accept. However, CmdStan accepts some weird statements.
For example:
```bash
./bernoulli method=sample adapt engaged engaged=0 engaged engaged=1 gamma engaged gamma \
    data file=bernoulli.data.json
```

The proposal is to use [pest](https://github.com/pest-parser/pest),
rather than write a custom parser.

# Prior art
[prior-art]: #prior-art

I have used both the with CmdStanPy and the StanJulia suite of
packages.  Years ago, I found them convenient.

## Flat structure

Both CmdStanPy and StanJulia pursue a flat structure. This works
largely due to the provision of optional positional/keyword arguments
in a dynamic language.

This is not possible in Rust -- default values require the builder
pattern in order to be ergonomic.

## Naming

The difference between naming of arguments/options in CmdStan and
(CmdStanPy | StanJulia) can be a source of confusion. I suppose that
one would not have this problem if one never used CmdStan.

## Serialization/deserialization of inputs/outputs

Undoubtedly, both CmdStanPy and the Julia suite are targeted at the
dynamic language audience, which expects features such as
serialization/deserialization to be built in.  In general, I would
expect that Rust programmers would probably want to select their own
I/O options, thus, I do not see it as a downside to exclude such
features.
