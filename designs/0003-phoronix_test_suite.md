- Feature Name: stan-dev_phoronix_test_suite
- Start Date: 2019-04-15
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

Phoronix is an open-source tool for conducting software-based performance testing over a wide variety of hardware and OS-level configurations. Phoronix integrates natively with Openbenchmarking.org for composing results. Custom test-suites are added to the online repository and called locally using console commands like phoronix-test-suite install *[Test | Suite | OpenBenchmarking ID]*.

# Motivation
[motivation]: #motivation

Benchmarking is crucial to the deployment of performant software. Properly testing algorithms and their implementations is non-trivial. Collecting results aids developer productivity and ultimately helps improve the optimization of the code base for all users. Enabling distributed testing ensures that the largest number of contributors can conveniently and accurately report how well their systems perform when executing reference code.

The Phoronix test suite as it exists currently is not a result of individual effort it has been developed collaboratively with the input of users from a variety of scopes and use cases. In practice this has resulted in a simple and effective tool that scales from timing code execution to actively controlling applications and taking detalied measurements of the specifications and system involved. 

How replicable are code-based performance improvements (or regressions) across a variety of hardware configurations? What code quality issues may be observed on certain computer configurations which may go undetected on other systems? Which unintuitive scenarios can we test for which information may not be avaiable through other sources?

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Users on Linux, Windows, or Apple OS X download and install the Phoronix Test Suite and use several (two) console commands to install and benchmark their systems. These commands are generally `phoronix-test-suite install [*]` and `phoronix-test-suite benchmark [*]` with `[*]` denoting an arbitrary test-suite specification. Under certain workflows an internet connected test-suite user only needs to be able to install phoronix and obtain the Openbenchmarking ID of the test-suite being considered. 

For test suite developers the process involves writing the test, specifying the system requirements for building it, and uploading to a team maintained Openbenchmarking repository. Although benchmarking is principally a hardware focused activity these test cases should be thought of as part of the debugging process for performance orientated end-user code. The results produced from benchmarking can be related to all manner of physical specifics about the state of the computer as it runs various tasks specified by the developer. These specifics include: compiler used, GPUs, Operating Systems, CPUs, disk drives, etc. Captured results from these subsytems are stored online and can be visually depicted using standardized, intuitive layouts. 

It is difficult to imagine all of the different ways the Phoronix test suite and Stan could possibly integrate. Candidate scenarios include: running example models in CmdStan particularly on test cases for a developement branch of math for a new function where decision making may require additional cost/benefit information or prior to a versioned release as part of the debugging process. In this case the unreleased branch would be specified in the build file and the test suite user would have the repository downloaded and compiled locally within ~/.phoronix-test-suite (on Linux). Testing becomes a background activity. 

The benefits of doing this seem to be highest for larger code bases. It might be impractical to have even just the math library cloned simply to profile a single test case. It should be possible to instruct the benchmark to use an existing install though it's easy to imagine that there would be conflicts due to code versioning. A standard implementation will always default to installing and compiling code from source or unpacking included code bundles which are downloaded from Openbenchmarking.org.

A quick example test was written by a student with no background in benchmarking or the Phoronix test suite in approximately 30 minutes: https://github.com/ode33/standev-phoronix/tree/master/test-profiles/local/build-standev-cmdstan-2.19. This test-profile takes about 10 minutes to compile and 16 seconds to execute on a mid-range system. There is a lot more that can be done with batch testing, targeting measures other than execution time, and the aggregation and presentation of results. 

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

From the Phoronix Test Suite Guide: https://www.phoronix-test-suite.com/documentation/phoronix-test-suite.pdf (pp 59-62):

"Writing a test profile for the Phoronix Test Suite is a relatively quick and easy process for anyone familiar with common Linux commands and the basics of XML. To help you understand the design of the Phoronix Test Suite, this guide covers the steps needed to write a testing profile for a very simple application.

The first step in the profile writing process is to, well, have a piece of software you’d like to use with the Phoronix Test Suite. This software can be closed-source or open-source and be virtually anything as long as it is compatible with an operating system that is supported by the Phoronix Test Suite.

For this guide, the piece of software being used for demonstration is just a simple C++ program that calculates Pi to 8,765,4321 digits using the Leibniz formula. Below is this sample piece of software intended just for demonstration purposes."

[C++ code omitted here]

“The first step in the actual profile writing process is to name it. If you’re looking to ultimately push this profile to be included in the Phoronix Test Suite, its name must be all lower case and consist of just alpha-numeric characters, but can contain dashes (-). A more advanced test profile capability is operating system prefixes, and if using those there is an underscore separating the prefix from the normal profile name. For this sample profile, we’re calling it sample-program and the file-name would be sample-program/test-definition.xml . Our (very basic) profile is showcased below.”

[XML header omitted here]

"This XML profile is what interfaces with the Phoronix Test Suite and provides all the needed information about the test as well as other attributes. For a complete listing of all the supported profile options, look at the specification files in the documentation folder. In the case of sample-program, it lets the Phoronix Test Suite know that it’s composed of free software, is designed to test the processor, is intended for private use only, and this profile is maintained by Phoronix Media. In addition, it tells the Phoronix Test Suite to execute this program three times and as no result quantifier is set, the average of the three runs will be taken. This profile also tells the Phoronix Test Suite that the generic build-utilities package is needed, which will attempt to ensure that default system C/C++ compiler and the standard development utilities/libraries are installed on your Linux distribution. This is needed as the C++ source-code will need to be built from source.

The next step is to write the install.sh file, which once called by the Phoronix Test Suite is intended to install the test locally for benchmarking purposes. The install.sh file is technically optional, but is generally used by all tests. Note: The first argument supplied to the install script is the directory that the test needs to be installed to. The install.sh file (in our instance) is to be placed inside test-profiles/sample-program. Below is the install.sh for the sample-program."

[Shell script omitted here]

“This install file builds the code with GCC, and then creates a small script that is run by the Phoronix Test Suite. Where does the source-code come into play? Well, it needs to be downloaded now from a web server. The Phoronix Test Suite has built-in support for managing downloads from multiple servers in a random over, fall-back support if one mirror is done, and verification of MD5 check-sums. Below is the downloads.xml file for sample-program that covers all of this.”

[XML omitted here]

“The final step in the profile writing process is to write a parser to strip all information but the reported result from the standard output or $LOG_FILE. In the case of a test profile just measuring how long it takes to run, it is as simple as a results-definition.xml looking like:”

[XML omitted here]

“After that, with all the files in their correct locations, just run: phoronix-test-suite benchmark sample-program. The Phoronix Test Suite should now handle the rest by installing the test, running the test, and recording the results (if you so choose). There is no additional work that needs to be done for the results to be recorded in the results viewer or even reporting the results to OpenBenchmarking.org. An up-to-date version of this test profile can be run via phoronix-test-suite benchmark sample-program and then by looking at the test profile source via ~/.phoronix-test-suite/test-profiles/pts/sample-program* or within /var/lib/phoronix-test-suite/test-profiles/pts/ if running as root.”

# Drawbacks
[drawbacks]: #drawbacks

Benchmarking is generally a *hardware* focused activity and typically it is the *software* which is the standard reference. Drawing relevant distinctions for code improvement between hardware and software level factors may be complicated if the sample sizes are small or if there is a large separation between the specifications of the setups.

The process of continuous integration may require frequent updates to the test-cases which then need to be rerun by the test-suite users. Obtaining relevant test results in a timely manner may be challenging.

Phoronix downloads, compiles, and executes the test-suite automatically. A standard phoronix test run is 3 repetitions with more added if the standard deviation of these exceed a threshold. Tests which attempt to profile large portions of the compiled code base will require extended compute times. 

Reliance on benchmarking and performance hardware reports may distract from other important project-level goals.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The Git repository `seantalts/perf-math` and other scripts have been posted to various pull requests and issues on `stan-dev/math`. In most cases these are related to micro-benchmarks (relatively small code snippets). In other cases these tests may not be conveniently replicable or the reporting may lack comprehensive details which would be valuable for drawing qualitative (build-level) comparisons. 

In order to add to the capacity of the stan-dev team to draw conclusions regarding performance improvements and make better informed decisions for future code revisions a more convenient and extensible system could be introduced. 

Some alternatives can be found here: https://alternativeto.net/software/phoronix-test-suite/. From the users perspective these comparable systems appear as high-level interfaces or comprehensive (install and execute) applications. For the test-suite developer it's hard to comment generally on how the experience might differ. Collaborative systems of which Phoronix is the leader seem preferable since they generally are developed with low-level customization at their core. On the other hand proprietary services are often optimized for convenience so there may be alternitives which provide otherwise unobtainable productivity enhancements.

Microbenchmarking programs such as the toolkit provided by Google seem preferable for routine developer testing scenarios. This is a scenario where only a handful of test results based on relative performance on one or two systems are needed to make a decision and comparisons across different system build and hardware specification is not so important.

# Prior art
[prior-art]: #prior-art

The `phoronix-test-suite` package is licensed under the "GNU General Public License v3.0" only which in SPDX terms is both FSF Free/Libre and OSI Approved for use in other collaborative software or documentation. 

Currently Openbenchmarking.org boasts hosting over 27,900,000 unique benchmark comparions and views.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

Will this be useful to the stan-dev team?
