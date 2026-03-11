- Feature Name: stanbin-binary-output
- Start Date: 2026-02-03
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

[Related Forum Thread](https://discourse.mc-stan.org/t/proof-of-concept-binary-output-format-for-cmdstan/40846/31)

This design proposes *stanbin*, a minimal, single-file binary output format for Stan MCMC draws. The base format stores draws in row-major order, matching the order in which Stan sampling callbacks produce them, so writers can stream each draw directly with no buffering or transposition. It is designed for handling large posterior samples with minimal dependencies and broad portability.

In v1, each `.stanbin` also stores the same run metadata that appears in the sample CSV comments (configuration, adaptation, timing) as a trailing metadata section, so downstream tools can recover `iter_sampling`, `thin`, etc. without needing a sidecar file.

This proposal intentionally separates the base row-major format from a possible chunked extension. The base format focuses on binary size, precision, and straightforward streaming writes. An extension can add chunked layouts for more efficient selective column reads without changing the overall container structure.

# Motivation
[motivation]: #motivation

## The Problem: Large Draw Files

Users working with high-dimensional models or long MCMC runs face challenges with the current CSV output format:

1. File size: CSV files can take large file sizes for large models. [Current](https://scholz.quarto.pub/cmdstan-binary-output-format/) [benchmarks](https://scholz.quarto.pub/cmdstan-binary-output-formats/) for the prototype formats suggest stanbin is typically about 25-30% smaller than CSV for tested workloads.

2. Parsing overhead: Reading large CSV files requires parsing text to numbers, which is CPU-intensive and memory-hungry.

3. Precision loss: CSV output uses configurable significant figures (default 8), truncating the full 64-bit double precision.

4. Limited evolution path: CSV forces Stan to keep all draws and most run metadata in one text stream. That makes it hard to improve binary performance incrementally without a new container format.

## Why Split the Proposal?

The original version of this proposal coupled two ideas:

1. A minimal binary container for Stan draws.
2. A chunked data layout for more efficient selective column reads.

Those are related, but they do not need to land together.

The base row-major format already provides value:

- Smaller files than CSV,
- no text parsing,
- full 64-bit precision,
- direct streaming writes,
- a simple reader/writer implementation.

Chunking is still valuable, but it is an optimization on top of the base container. Splitting the design lets Stan adopt the simple format first and evaluate the specifics of adding a chunked layout later with a narrower review surface.

## Why Not Arrow/Parquet/Beve?

These formats tend to come with rather heavy dependencies that would need to be added to cmdstan and there is no clear benefit of their more general scoped schemas compared to a custom format.

## Design Goals

### Base format goals

1. Minimal dependencies: Header-only C++ implementation with no external libraries
2. Streaming writes: Write draws incrementally as sampling proceeds in the order they arrive
3. Full precision: Preserve complete 64-bit double precision
4. Self-describing: Column names embedded in file, no external metadata required
5. Simple: Readers implementable in any language with standard binary I/O

### Extension goals

1. Efficient partial reads: Support reading specific columns without loading the entire file
2. Layout evolution: Add chunked storage without redefining the rest of the file container

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

## Basic Usage (CmdStan)

To output draws in stanbin format instead of CSV:

```bash
./my_model sample output format=stanbin file=output.stanbin
```

The resulting `.stanbin` file contains the same draw table as the CSV file, but in binary form. In the base version, draws are stored row-by-row in the same order they are produced by Stan. This keeps the writer simple and allows immediate streaming output.

It can be read with the provided R reader:

```r
source("read_stanbin.R")
draws <- read_stanbin("output.stanbin")
# draws is a matrix with named columns
```

## How to Think About the Base Format

The initial stanbin format is deliberately conservative:

- it changes the container format from text to binary,
- it keeps the draw table shape the same as CSV,
- it writes rows in the same order Stan already generates them,
- it leaves more advanced physical layouts, such as chunking, for a later extension.

So the main user-visible benefits of the base format are:

- smaller files,
- full precision,
- faster reads (1-2 orders of magnitude faster in [Current](https://scholz.quarto.pub/cmdstan-binary-output-format/) [benchmarks](https://scholz.quarto.pub/cmdstan-binary-output-formats/)) because no text parsing is needed.

The base format does not try to optimize selective single-column reads. Readers that want one column can still scan rows and extract that column, or read the full matrix and transpose in memory.

## File Size Comparison

[Current](https://scholz.quarto.pub/cmdstan-binary-output-format/) prototype [benchmarks](https://scholz.quarto.pub/cmdstan-binary-output-formats/) suggest that stanbin is usually about 25–30% smaller than CSV for the tested CmdStan workloads. The exact ratio depends on the model, number of columns, metadata overhead, and CSV formatting choices.

## When to Use Stanbin

**Use stanbin when:**

- Working with models that have many parameters
- Running long MCMC chains
- Disk space, memory or I/O bandwidth is a constraint
- You need full double precision
- You want faster file loading

**Use CSV when:**

- Human readability is important
- Interoperating with tools that only read CSV

## Future Chunked Extension

A future chunked extension could store draws in row groups, while keeping each group's values arranged to make selective column reads cheaper. That extension would target downstream analysis workloads that repeatedly access subsets of columns from large files or files that become too large to load into memory.

Stan does not need chunking to get the base binary format benefits.

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

## Base File Format (Version 1)

The v1 stanbin format consists of four sections:

1. Fixed-size header
2. Names section
3. Row-major data section
4. Trailing metadata section

### 1. Header (64 bytes, fixed)

| Offset | Size | Type | Description |
|--------|------|------|-------------|
| 0 | 8 | char[8] | Magic: `"STANBIN\0"` |
| 8 | 4 | uint32 | Version (`1`) |
| 12 | 4 | uint32 | Flags (`0` in v1; reserved for extensions) |
| 16 | 8 | uint64 | Number of rows (draws) |
| 24 | 8 | uint64 | Number of columns (parameters) |
| 32 | 4 | uint32 | Data section offset in bytes (8-byte aligned; `64 + ((names_size + 7) / 8) * 8` in v1) |
| 36 | 4 | uint32 | Names section size in bytes |
| 40 | 4 | uint32 | Layout parameter (`0` = row-major in v1; non-zero values reserved for extensions such as chunking) |
| 44 | 8 | uint64 | Metadata section offset (`0` if file not yet finalized) |
| 52 | 4 | uint32 | Metadata section size in bytes |
| 56 | 8 | reserved | Reserved for future use |

All integers are little-endian.
The field at offset `32` is intentionally the byte offset of the data section, so the file remains self-describing even though the names section is variable length.
In v1, writers must choose `data_offset` so that the data section begins on an 8-byte boundary.

The `cols` field is kept explicitly even though a reader could derive the number of columns by counting null-terminated names.
Storing it in the header makes validation and allocation simpler, and `uint64` is already large enough that it does not impose a meaningful practical limit on the number of columns.

### 2. Names Section (variable size)

Null-terminated UTF-8 strings, one per column:

```
lp__\0accept_stat__\0stepsize__\0...theta.1\0theta.2\0...
```

If needed, the names section is followed by zero padding bytes so that `data_offset` is 8-byte aligned.
These padding bytes are not counted in `names_size`.

### 3. Data Section (variable size, row-major)

The data section stores the draw table in row-major order. Each row corresponds to one draw, and values within a row follow the same column ordering as Stan CSV output.

```
Row 1: [col1, col2, col3, ..., colM]
Row 2: [col1, col2, col3, ..., colM]
...
Row N: [col1, col2, col3, ..., colM]
```

All values are 64-bit IEEE 754 doubles in little-endian byte order.

If `data_offset` is the start of the data section, then the byte offset of row `r`, column `c` (0-based) is:

```
data_offset + ((r * num_cols) + c) * 8
```

This is the same logical table as the Stan CSV output, but serialized as raw doubles rather than decimal text.

### 4. Metadata Section (variable size, required)

This section contains UTF-8 text which mirrors the non-draw lines from CmdStan's sample CSV output:

- Comment lines beginning with `# ` (configuration, adaptation messages, timing)
- Exactly one CSV header line (comma-separated column names) with no leading `#`

The section is written after the data section so writers can stream draws without interleaving text.
Readers use `metadata_offset` and `metadata_size` from the header to locate and parse the metadata.

## Finalization Semantics

A writer creates the file in this order:

1. Write a provisional header with `rows = 0` and `metadata_offset = 0`.
2. Write the names section and any zero padding needed to make `data_offset` 8-byte aligned.
3. Stream each draw row directly into the data section.
4. Write the trailing metadata section.
5. Seek back and rewrite the header with the final row count and metadata location.

If a run terminates before step 5, the file is incomplete.
Readers can detect this by checking whether `metadata_offset == 0`: a finalized file always has a non-zero metadata offset because the metadata section is required in v1.
A reader that wants to attempt partial recovery from an incomplete file can compute the number of usable rows from the file size:

```
recoverable_rows = floor((file_size - data_offset) / (num_cols * 8))
```

Because the data section is row-major, every complete row is independently usable.

## Base Layout Rationale

The base version chooses row-major layout because Stan sampling already produces one draw row at a time. This gives the simplest writer behavior:

- no transposition,
- no row buffering,
- no chunk-size tuning,
- direct streaming writes.

Row-major also makes partial recovery from interrupted runs straightforward: every complete row in the data section is usable regardless of whether the file was finalized.

The tradeoff is that selective single-column reads remain a scan-heavy operation in v1. Reading a single column requires scanning each row and extracting the value at the target offset, or reading the full matrix and subsetting in memory.

## Chunked Extension (Future)

This RFC leaves room for a follow-on chunked extension, but does not make it part of the base format.

A chunked extension could reuse the same overall container structure while changing only the physical layout of the data section. For example:

- `flags != 0` could indicate an extended layout,
- the field at offset `40` could store a chunk-size parameter,
- the data section could be partitioned into row groups with values arranged to make selective column reads cheaper.

That extension would improve some analysis workloads, but it also introduces questions about buffer sizing, partial-file semantics, and read/write complexity. Those questions are easier to evaluate once the base binary container is established.

## Implementation

The current prototype implementations in `cmdstan` and `cmdstanr` already exercise much of the proposed container shape: the magic/versioned 64-byte header, null-terminated names section, and trailing metadata block are all present.
However, the prototype code still uses the earlier **chunked** data layout.

If this RFC lands with a row-major base format, the existing prototype can be viewed as implementation prior art for a future chunked extension, while the base v1 reader/writer become simpler because they can stream rows directly.

The code snippets below are illustrative.
Concrete implementations can expose richer error reporting than the simple boolean examples shown here.

### Target writer shape for the row-major base format

The base-format writer can remain small:

```cpp
class stanbin_writer : public stan::callbacks::writer {
 public:
  void operator()(const std::vector<double>& state) override {
    if (write_row(state)) {
      ++num_rows_;
    }
  }

  bool finalize() {
    if (!write_metadata()) {
      return false;
    }
    return rewrite_header(num_rows_);
  }
};
```

### Target writer excerpt (`cmdstan`)

<details>
<summary>V1 row-major writer excerpt</summary>

```cpp
bool write_row(const std::vector<double>& state) {
  stream_.write(reinterpret_cast<const char*>(state.data()),
                state.size() * sizeof(double));
  return static_cast<bool>(stream_);
}

void operator()(const std::vector<double>& state) override {
  // Row-major: write each draw directly, no buffering or transposition
  if (write_row(state)) {
    ++num_rows_written_;
  }
}

void update_header_fields(uint64_t rows, uint64_t cols, uint32_t data_offset,
                          uint32_t names_size, uint32_t layout,
                          uint64_t metadata_offset, uint32_t metadata_size) {
  stream_.seekp(12);
  uint32_t flags = 0;
  stream_.write(reinterpret_cast<const char*>(&flags), 4);
  stream_.write(reinterpret_cast<const char*>(&rows), 8);
  stream_.write(reinterpret_cast<const char*>(&cols), 8);
  stream_.write(reinterpret_cast<const char*>(&data_offset), 4);
  stream_.write(reinterpret_cast<const char*>(&names_size), 4);
  stream_.write(reinterpret_cast<const char*>(&layout), 4);
  stream_.write(reinterpret_cast<const char*>(&metadata_offset), 8);
  stream_.write(reinterpret_cast<const char*>(&metadata_size), 4);
}
```

</details>

The field at offset `32` is the data section byte offset (`64 + ((names_size + 7) / 8) * 8`), keeping the file self-describing.
The `layout` field at offset `40` is `0` for row-major v1.

### Target reader shape for the row-major base format

<details>
<summary>V1 reader header parsing (R)</summary>

```r
read_stanbin_header_ <- function(con) {
  magic <- readBin(con, what = "raw", n = 8)
  version <- readBin(con, what = integer(), n = 1, size = 4, endian = "little")
  flags <- readBin(con, what = integer(), n = 1, size = 4, endian = "little")
  # uint64 fields: read as integer size=8, R returns as double (exact up to 2^53)
  rows <- readBin(con, what = integer(), n = 1, size = 8, endian = "little")
  cols <- readBin(con, what = integer(), n = 1, size = 8, endian = "little")
  data_offset <- readBin(con, what = integer(), n = 1, size = 4, endian = "little")
  names_size <- readBin(con, what = integer(), n = 1, size = 4, endian = "little")
  layout <- readBin(con, what = integer(), n = 1, size = 4, endian = "little")
  metadata_offset <- readBin(con, what = integer(), n = 1, size = 8, endian = "little")
  metadata_size <- readBin(con, what = integer(), n = 1, size = 4, endian = "little")
}
```

</details>

This excerpt shows what downstream readers already expect: explicit `rows`, `cols`, `names_size`, a data offset, and trailing metadata offsets.
The field names here (`data_offset`, `layout`) match the proposed v1 header table.
Note that the `uint64` fields (`rows`, `cols`, `metadata_offset`) are read with `what = integer(), size = 8`: R has no native 64-bit integer type, so `readBin` returns the value as a double, which is exact for values up to 2^53.

## Integration with CmdStan

A new argument `format` is added to the `output` argument group:

```
output
  file = <string>
  format = csv|stanbin    # NEW - default: csv
  ...
```

The format argument is implemented in `src/cmdstan/arguments/arg_format.hpp`.

When `format=stanbin`:

- Output file uses `.stanbin` extension
- Draws are written in row-major order using `stanbin_writer` instead of the CSV stream writer
- v1 targets full writer-backed coverage rather than partial algorithm support
- All sampling algorithms (NUTS, static HMC, fixed_param) are supported
- Diagnostic output should follow the same format selection instead of leaving a mixed CSV/stanbin path

If a chunked extension is adopted later, it can introduce additional layout-specific configuration at that time.

## Column Ordering

Columns appear in the same order as CSV output:

1. `lp__` (log probability)
2. Algorithm state (`accept_stat__`, `stepsize__`, `treedepth__`, etc.)
3. Model parameters in declaration order
4. Transformed parameters in declaration order
5. Generated quantities in declaration order

# Drawbacks
[drawbacks]: #drawbacks

1. Not readily human-readable with ordinary text tools: Unlike CSV, stanbin files cannot simply be inspected with a text editor. Users typically need reader functions or binary inspection tools.

2. Tool ecosystem: Existing tools (stansummary, arviz, etc.) expect CSV format. These would need updates to support stanbin, though a companion `cmdstan/bin/stanbin2csv` utility can provide an interoperability bridge.

3. Endianness: The format assumes little-endian byte order. While this covers most modern systems, big-endian systems would need byte-swapping.

4. Row-major v1 does not optimize selective column access: Readers that want a small subset of parameters still need to scan the row-major draw table.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

## Why This Design?

1. Minimal complexity: The base format can be implemented with no external dependencies and no buffering. Readers can be implemented in any language with standard binary I/O.

2. Matches the write path: Stan sampling already emits one draw row at a time. Row-major layout lets the file format follow that natural production order.

3. Separates core format from optimization: The base format solves binary size, precision, and parse cost. Chunking is left as a separate extension because it optimizes a narrower set of downstream access patterns.

4. Self-describing: The embedded header and column names make files standalone with no external schema files needed.

## Alternatives Considered

### Arrow IPC

- Pros: Industry standard, mature tooling
- Cons: Large dependency, complex build, community rejected it
- Why not chosen: Dependency concerns outweighed benefits

### Protocol Buffers

- Pros: Efficient encoding, schema evolution
- Cons: Requires schema compilation, not naturally tabular
- Why not chosen: Schema compilation adds complexity and does not map cleanly to draw matrices

### Base Row-Major Plus Chunked Layout in the Same Initial RFC

- Pros: Could address both binary output and selective column reads at once
- Cons: Larger review scope and more design questions around chunk sizing and incomplete files
- Why not chosen: Splitting the base format from the chunked extension reduces the scope for the initial move to a binary format

### Pure Column-Major Binary

- Pros: Optimal for column reads
- Cons: Requires buffering the entire chain or complex write staging before emitting output
- Why not chosen: Memory requirements and implementation complexity are too high for the base proposal

### HDF5

- Pros: Mature, supports partial reads and compression
- Cons: Heavy dependency, complex API
- Why not chosen: Dependency is too large for the narrow problem being solved here

## Impact of Not Doing This

Users with large models will continue to face slow CSV parsing, precision loss from text representation, increased disk usage, and unnecessarily high CPU and memory usage when loading draws.

# Prior art
[prior-art]: #prior-art

## Related Stan Work

- Design Doc 0032 (stan-output-formats): Proposes a broader overhaul of Stan outputs using Arrow and multiple files. Stanbin is intentionally narrower. It focuses only on a minimal single-file binary format for the sample draw table plus trailing metadata.

- Design Doc 0001 (logger-io): Established the callback writer pattern that stanbin builds on.

## External Prior Art

- NumPy `.npy` format: Simple binary format with a small self-describing header. Stanbin follows the same spirit of using a minimal container implementable with standard library I/O.

- Apache Arrow: Record batches and chunked columnar storage are relevant prior art for a possible future stanbin chunked extension.

- Parquet: Column-oriented row-group layouts show the value of separating logical schema from physical layout.

- MATLAB `.mat` files: Self-describing binary formats widely used in scientific computing.

## Lessons Learned

From NumPy: Simple, self-describing headers keep the barrier to writing readers low.

From Arrow/Parquet: More sophisticated physical layouts are useful, but they can be layered on after the basic container exists.

From Stan community feedback: Minimal dependencies are a requirement for adoption in CmdStan's build environment.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

## To resolve before merging this RFC

1. Should stanbin become the default output format in a future CmdStan release, or remain opt-in indefinitely?

2. Is the trailing metadata section (raw CSV comment text) the right long-term metadata representation, or should v1 adopt a structured format (e.g., key-value pairs) from the start?

## To resolve during implementation

1. Multi-chain file handling: CmdStan writes one file per chain (same as CSV). The exact filename template behavior (suffix replacement, chain ID insertion) needs to be confirmed against current CmdStan conventions.

2. Finalization edge cases: The writer leaves `rows = 0` and `metadata_offset = 0` until successful close. The behavior when sampling is interrupted (e.g., SIGINT during warmup) should be tested to confirm that readers can detect and recover from incomplete files via `metadata_offset == 0`.

3. Full coverage validation: `format=stanbin` should be wired through all supported writer-backed sample and diagnostic output paths and validated across NUTS, static HMC, and fixed_param.

## Out of scope for this RFC

1. Chunked extension: A chunked physical layout for more efficient selective column reads. This can reuse the v1 container structure with a non-zero `layout` field.

2. Compression: Optional compression (LZ4, ZSTD) as a future version flag or extension.

3. Memory mapping: Reader-side optimization for large files. The row-major layout is already compatible with memory-mapped access.

4. Streaming reads: Reading draws as they are written, possibly in conjunction with a future chunked layout.

5. Tool updates: Updates to stansummary, cmdstanr, cmdstanpy, and arviz to read stanbin natively.
