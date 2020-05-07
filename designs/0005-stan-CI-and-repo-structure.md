- Feature Name: Stan Continous Integration and Repository Structure
- Start Date: 2020-05-05
- RFC PR: 
- Stan Issue: 

# Summary
[summary]: #summary

This design doc is aimed at upgrading and reorganizing the Stan Continous Integration (Stan CI) and Github repository structure. I propose a list of changes on how to upgrade Stan CI to improve the test coverage, speedup testing and simplify the structure of the repositories and the CI.

There were a lot of changes in recent times in the Stan ecosystem (most importantly stanc3) and in the ecosystems that are closely related to it (most importantly R 4.0 and RTools 4.0) that should be accounted for in our CI and Github repositories. This document is aimed at improving that.

I took the liberty to deviate from the typical structure of the rest of the design docs as this topic is not a typical thing we usually discuss in design docs. I first describe the current status and its defficiencies and then propose a list of changes that could be done to improve the current status. Each change can be treated as separate and the final document will only include the proposals that will be approved.

# Current status
[current-status]: #current-status

First a summary of all the tests run on Math/Stan/Cmdstan/Stanc3 repositories. Times in square brackets lists the typical run time of the listed test. If not specifically mentioned the tests are run on any operating system.

In Math the following tests are run on Jenkins:

+ `test/unit` on Linux with STAN_MPI on [20 minutes or 1 hour on the Linux box]
+ `test/prob` (distribution tests) with `O=0`, `N_TESTS=300` [1.5-2 hours]. 
On merge to develop, `test/prob` also runs `ROW_VECTOR` tests which run for 3-3.5+ hours or 6 hours on the Linux box.
+ `test/unit` with `STAN_OPENCL` that run on Linux or Mac [~1.5 hours]
+ tests with `thread` or `map_rect` in their names with `STAN_THREADS` [~2 minutes]
+ `test/unit` on Windows [~2 hours]
+ tests with `thread` or `map_rect` in their names with `STAN_THREADS` on Windows [~2 minutes]
+ upstream Jenkins tests (see Stan tests)

On merge to develop we also run
- `test/unit` on Linux with `STAN_THREADS` on [~20 minutes or 1 hour on the Linux box]
- `test/unit` on Mac with `STAN_THREADS` on [~1 hour]

In Stan the following tests are run on Jenkins:
- `src/test/unit` [~0.5 hour]
- `src/test/unit` on Windows [~40 minutes]
- `src/test/integration` [~45 minutes]
- upstream Cmdstan tests (see below)
- `src/test/performance` on Mac [~5 minutes]

Stan repo also runs Travis Linux tests for src/test/unit with clang and g++.

In Cmdstan the following tests are run on Jenkins:
- `src/test/interface` on Linux with `STAN_MPI` on [~5 minutes]
- `src/test/interface` on Mac [~5 minutes]
- `src/test/interface` on Windows [~5 minutes]
- performance tests which are run on changes in Stan/Math [~10 minutes]

Stanc3 tests (these are not part of the Math/Stan/Cmdstan structure currently):
- `dune tests` [~10 minutes]
Tests that the pushed .expected files match the actual state.
- model end-to-end tests [~10 minutes]
Compiles a list of models with the develop cmdstan. See the list in the beginning of a log file [here](https://jenkins.mc-stan.org/blue/rest/organizations/jenkins/pipelines/stanc3/branches/PR-517/runs/5/nodes/46/steps/77/log/?start=0).
- TFP test [1 minute]
Tests for the TFP backend.
- On request we can also run a test to compile all "good/integration" tests with stanc3 + develop cmdstan. [NA]

# Proposals
[proposals]: #proposals

The order of proposals is not in order of importance, though the first few ones are those where I expect the least amount of controversy. If anyone has any additional proposals please comment with them and we can include them here.

##### Proposal 1: Replace stanc2 tests in stan-dev/stan repository with stanc3
  
\
We are currently still using stanc2 in the upstream Math tests and in the Stan repository tests. This should be removed and replaced with equivalent tests that use stanc3. This would also mean we need to somehow "connect" the Stan and stanc3 repositories. I dont think we need to add stanc3 as a submodule of Stan. We should instead somehow mark the latest stanc3 master git commit hash in a separate file or in one of the makefiles. Each merge to master in stanc3 should then update it. This would trigger Stan tests on each merge in Stanc3, which would be another benefit of this.

##### Proposal 2: Move stanc2 to a separate (new) repository and add it as a Cmdstan submodule
\
Stanc2 will be phased-out in the near future and its source files will not be used in the next Rstan release (They will probably still be in the StanHeaders package if I am not mistaken). We will still support stanc2 optionally in cmdstan for a few releases to debug stanc3 bugs. Together with the move we should also close or transfer all language issues in stan-dev/stan.

##### Proposal 3: Use "jumbo" tests on Jenkins in Stan Math
\
Jumbo tests are multiple smaller tests merged in one file. We could merge test files in subfolders, for example test/unit/math/prim/fun, in a single file or a few files per subfolder. We would keep existing small files for local testing but Jenkins would run `./runTests.py --jumbo test/unit` which would create and use these "jumbo" test files. 

Preliminary tests have shown that by doing jumbo files (in chunks of 15 files) in most but not all `test/unit` subfolders has cut the test time on Jenkins in half. Even 50% faster tests would be great. But we can potentially get even more. For some more details see [here](https://github.com/stan-dev/math/pull/1863#issuecomment-625178238). We could use this on Linux and Mac tests and if Proposal 5 is accepted, could also use this on Windows.

##### Proposal 4: Refactor `make generate-tests` to reduce the number of generated files in `test/prob`
\
Tests files in `test/prob` are generated using the [generate_tests.cpp](https://github.com/stan-dev/math/blob/develop/test/prob/generate_tests.cpp) file. This creates roughly 2700 test files. Compiling these files represents 90%+ of the distribution tests execution time in Stan Math. And the distribution tests are one of the bottlenecks. 

We could improve this by grouping existing test files as in Proposall 3, but in this case this would be done in the generation phase, not after.

##### Proposal 5: Move Windows testing to the RTools 4.0 toolchain
\
RTools 4.0 was released in April 2020 and we have already seen Stan users moving to it. This means that we should be testing with the toolchains available in RTools 4.0 to make sure everything works there. Testing both 4.0 and 3.5 is obviously not feasible, if for nothing else, due to the lack of Windows testing worker machines. But we should also not leave 3.5 users in the dark as we know many will not upgrade if not forced to.

I propose moving all Windows Jenkins tests to run with RTools 4.0 and adding a separate worker for Windows with RTools 3.5 (WinRT35). For Jenkins tests this means speedup in compile times for the Math and Stan tests. The WinRT35 worker would be used to make sure that everything still works at the Cmdstan level by compiling/running a set of models. WinRT35 could be run in Cmdstan with free instances on Appveyor/Azure or Github Actions.

This means that Windows users of Math and Stan on the C++ level would be forced to switch to using RTools 4.0 if they want to work in a supported (tested) environment. It is very likely, everything will keep working for them for the forseable future (until the move to `C++17`), it will just not be as severely tested. I do believe that the number of Windows users of Cmdstan with RTools 4.0 in the near future is far larger then those of Stan Math or Stan in `C++`.

##### Proposal 6: Reorganize Stan Math tests
\
The current structure of tests have the following defficiencies (in my opinion):
- the default test should be full unit test with no flags (MPI, OpenCL, threads). The only tests that currently run with no flags are on Windows. The default and most common use of Stan is without these flags so that should also be the default and first test.
- regular threading tests (not merge to develop) do not run reduce_sum tests
- tests with OpenCL and MPI should only run tests files that are affected by these flags. STAN_OPENCL and STAN_MPI have zero effect in tests where they are not used. Where they are used, things will not compile if the flag is not set.
- there is no need to explicitly single-out Windows so much at the Math level. Threading is done via TBB the same way as on other OSes. In the last year or two, the only Windows-specific issue was the size of test files that caused issues on the 4.9.3 on Jenkins workers only. Locally there were no issues.
 
My current idea to reorganize tests is:

###### Stan Math:
\
Stage 1:
+ `test/unit` with no flags on any OS

Stage 2:
+ `test/prob` as is
+ `STAN_OPENCL` tests only
+ `STAN_MPI` tests only
+ `test/unit` with `STAN_THREADS` on any OS

I think we dont need additional tests on merge to develop. On request (build with parameters) we could also run the Stage 1 test on all OS (3 tests) in parallel.

###### Stan

- services/algorithms and compile tests on Linux
- services/algorithms and compile tests on Mac
- services/algorithms and compile tests on Windows

I would remove the Travis tests. The main objective of tests in Stan should be to check the services/algorithms and that everything still compiles from .stan to executables on all OSes.

The performance test in Stan currently runs a simple logistic model 100 times with a fixed seed. The test records to a csv file information about the current build, whether the values match the expected known values and whether values are identical between runs, and the runtime in seconds for each of the 100 individual runs. I don't think this simple test serves any significant real purpose as it is right now. It covers a single example that uses a tiny part of the Stan Math library. A revamped performance and precision tests are needed and will be proposed in a separate design-doc. Those will be done on the interface level, rather than on a Stan C++ level. While there is nothing wrong with the test, it would need to be expanded to have some actual coverage.

###### Cmdstan and Stanc3

Can stay as is, but Cmdstan performance and precision tests should be expanded. That is a topic for a separate design doc. Changes in stanc3 will trigger stan and cmdstan tests.

###### Rstan

I would also like to add tests for Rstan. On all merges to Math/Stan develop we would merge develop to the StanHeaders(or StanHeaders_dev) branch and run Rstan package tests and potentially other stuff. Errors here would not stop or abort anything but would be a proper warning in time for when things break Rstan.

##### Proposal 7: Merge Stan Math with the Stan repository
\
This one will be controversial and I will not force it. I do feel it would simplify development for the Math/Stan/Cmdstan repository stack and probably also Rstan with the StanHeaders branch.

There was 1 non-CI or tests related PR in the Stan repository in the last release period and a few but not much more in the previous release period. There are however more than occasionally Math PRs that require mirroring Stan PRs that have to then be merged in sync. The question is would we lose Stan Math users if they would be forced to use Math as part of a slightly larger repository.
