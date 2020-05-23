- Feature Name: Gold Master Testing
- Start Date: 2017-11-02
- RFC PR: ??
- Stan Issue:

## Gold Master Testing

Stan is pretty complex. We try our best to unit test our code, but even with these tests, there are things the unit tests don't catch.

### Goals

- Across two git hashes, typically `develop` and a proposed pull request:
	- Verify that the code runs identically across the two hashes

	      If we're running on the same machine with the same compiler, compiler options, and seeds, then the code should run identically. If it doesn't, we should know about it. Changes are ok, we just need to know about it. The two common changes that can affect the runs are a more stable numeric computation or a change to the random number generator.

	- Check performance across two hashes

		  There are two cases we need to think about:

		  - Code runs identically across the two hashes. In this case, we can compare wall time directly since both hashes are doing exactly the same operations.

		  - Behavior is different across two hashes. We need to compare N_eff / time in order to have an estimate of performance.

- For developers, we want:
	- an easy way to generate output to store
	- easy comparison of the output
	- ability to programmatically ignore parts of the output; things like printouts of elapsed time can be ignored
	- notification when changes cause different behavior or different performance

- Ideally, we'd want to be able to run this locally or on different machines.

### Non-Goals

- We are not trying to trap every single error using this test; we should still be unit testing.
- We are not trying to make this instantaneous. It may take a while to run.


### Awesome things to consider

- It would be great if this could drive testing of the interfaces. If we're using full models (Stan programs), it would be great to have this drive a common set of tests to verify interfaces behave correctly. (Or when they don't.)
- It would be great to tie this into our continuous integration
