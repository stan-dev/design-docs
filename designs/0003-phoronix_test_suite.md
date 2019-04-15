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

How replicable are code-based performance improvements (or regressions) across a variety of hardware configurations? What code quality issues may be observed on certain computer configurations which may go undetected on other systems? Which unintuitive scenarios can we test for which information may not be avaiable through other sources?

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

Users on Linux, Windows, Apple OS X, GNU Hurd, Solaris, or BSD Operating Systems download and install the Phoronix Test Suite and use several (two) console commands to install and benchmark their systems. These commands are generally `phoronix-test-suite install [*]` and `phoronix-test-suite benchmark [*]` with `[*]` denoting an arbitrary test-suite specification. Under certain workflows an internet connected test-suite user only needs to be able to install phoronix and obtain the Openbenchmarking ID of the test-suite being considered. 

For test suite developers the process involves writing the test, specifying the system requirements for building it, and uploading to a team maintained Openbenchmarking repository. ALthough benchmarking in principally a hardware focused activity these test cases should be thought of as part of the debugging process for performance orientated end-user code. The results produced from benchmarking can be related to all manner of physical specifics about the state of the computer as it runs various tasks specified by the developer. These specifics include: compiler used, GPUs, Operating Systems, CPUs, disk drives, etc. Captured results from these subsytems are stored online and can be visually depicted using standardized, intuitive layouts. 

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

From the Phoronix Test Suite Guide:

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

The Git repository `seantalts/perf-math` and other scripts have been posted to various pull requests and issues on `stan-dev/math`. In most cases these are related to micro-benchmarks (relatively small code snippets). In other cases these tests may not be conveniently replicable or the reporting may lack comprehensive details which would be valuable for drawing qualitative comparisons. 

In order to build on the capacity of the stan-dev team to draw conclusions regarding performance improvements and make better informed decisions for future code revisions a more convenient and extensible system could be introduced. 

# Prior art
[prior-art]: #prior-art

The `phoronix-test-suite` package is licensed under the "GNU General Public License v3.0" only which is SPDX terms is both FSF Free/Libre and OSI Approved for use in other collaborative software or documentation. 

Currently Openbenchmarking.org boasts hosting over 27,900,000 unique benchmark comparions and views.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

Will this be useful to the stan-dev team?
