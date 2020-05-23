- Feature Name: Protocol buffers for serialization of input data, output samples, initial values, input parameters, and output messages
- Start Date: 2017-06-02
- RFC PR: ??
- Stan Issue:

## Proposal

Create a small library with Stan/Math as submodules that allows an interface to use Protocol Buffers for data input files to Stan, output of samples, input of initial values, input of control parameters, and output of messages.  The best use case is that it reduces the complexity of a client-server version of Stan dramatically. The prototype/illustration for this wrapper is being developed in a separate [repo](github.com/sakrejda/protostan).

## Accomplished so far:
 - A wrapper around stan::compile, with tests.
 - A length-delimited serialization format
 - An complete writer callback using the format, with round-trip tests.

##  Protocol Buffers overview with example
Protocol Buffers is intended for [cross-platform](https://developers.google.com/protocol-buffers/docs/overview#what-are-protocol-buffers) sharing of [small messages](https://developers.google.com/protocol-buffers/docs/techniques#large-data).  The format is binary and described externally in .proto files.  An example .proto file is:

~~~
syntax = "proto3";

package stan.proto;

/**
 * Input for stan::lang::compile wrapper.
 */
message StanCompileRequest {
  string model_name = 1;      /// Name of the Stan model.
  string model_code = 2;      /// Stan-language code for the model.
}

/**
 * Output from stan::lang::compile wrapper.
 */
message StanCompileResponse {
  enum State {
    UNKNOWN = 0;     /// Default value in case of bad set value.
    INCOMPLETE = 1;  /// Indicates compilation is not finished, resend StanCompileRequest
    SUCCESS = 2;     /// Indicates compilation succeeded, check messages for warnings.
    ERROR = 3;       /// Indicates compilation failed, check messages for errors.
  }
  State state = 1;     /// Return code for compilation request.
  string cpp_code = 2; /// C++ code for the model provided in StanCompileRequest.
  string messages = 3; /// Check for Stan compiler warnings or errors.
}
```

The protoc compiler takes this .proto file and uses plugins to generate code for any [supported](https://developers.google.com/protocol-buffers/docs/reference/overview) languages.  The result is native code which can construct/read well defined messages.  The Protocol Buffers language definition specifies data types, with [mapping](https://developers.google.com/protocol-buffers/docs/proto3#scalar) to data types in supported languages.

A thin wrapper that takes code from the above .proto interface file and provides a C++ API for calling Stan's compile function:

```
#include <stan/proto/compile.pb.h>
#include <stan/lang/compiler.hpp>
#include <iostream>
#include <sstream>
#include <string>

namespace stan {
  namespace proto {
    stan::proto::StanCompileResponse compile(
      const stan::proto::StanCompileRequest& request) {
      stan::proto::StanCompileResponse response;
      std::ostringstream err_stream;
      std::istringstream stan_stream(request.model_code());
      std::ostringstream cpp_stream;

      response.set_state(stan::proto::StanCompileResponse::ERROR);
      try {
        bool valid_model = stan::lang::compile(&err_stream,
                                               stan_stream,
                                               cpp_stream,
                                               request.model_name());
        response.set_messages(err_stream.str());
        if (valid_model) {
          response.set_state(stan::proto::StanCompileResponse::SUCCESS);
          response.set_cpp_code(cpp_stream.str());
        }
      } catch(const std::exception& e) {
        response.set_messages(e.what());
      }
      return response;
    }
  }
}
```

It only takes a [little more code](https://github.com/sakrejda/servestan/blob/master/src/servestan/servestan.cpp) to get a server version that listens to Protocol Buffer messages on a socket and responds with protocol buffer messages.  The "servestan" code is currently not in sync so don't bother trying it...

## Benefits

* Binary floating point numbers so round-trip possible.
* Library takes care of message versioning, binary storage format.
* protoc compiler generates most of the code for interfaces to use the format.
* Google-size commitment to inter-operability among languages---that's what we (should) want.
* usable for data format as well as for control parameters (so could be used to pass options/control parameters in a CloudStan-like setting).
* There is now a multi-message file format in the utility library: https://github.com/google/protobuf/pull/2861/files

## Pitfalls

* Potentially more complicated than a bespoke Stan serialization format.
 - Our data types are simple and relatively standard (Eigen types, or basic C/C++ types).
 - I (Krzysztof) don't want to think about versioning and other serialization issues that have already been solved by boost::serialize/protobuf/BSON/etc...
* Messages should be small, with a suggested "reconsider your strategy" limit of [1MB](https://developers.google.com/protocol-buffers/docs/techniques#large-data).  Larger messages are possible (it's a parameter that can be controlled), not clear how that plays with optimization, we would be relying on a corner case.
 - Message size limits suggest that larger vectors/arrays/matrices need to be chunked for storage/transmission
   if this is used as a generic format.
 - If chunking is complicated, we loose the benefit of handing message serialization/construction off to a
   library.  An interface should be able to call one function and serialize a vector, not worry about chunking
   it so the serialization format is satisfied.
* ~~The library (except for the Java plugin/version...) does not deal with writing multiple delimited messages to a stream/file. There is a [standard](http://stackoverflow.com/questions/2340730/are-there-c-equivalents-for-the-protocol-buffers-delimited-i-o-functions-in-ja) (outside of Google) way of doing this suggested by one of the original Protocol Buffers devs~~.
 - ~~There is an outstanding Protocol Buffers [pull request](https://github.com/google/protobuf/pull/710) by the same dev that would add a standard format for serializing multiple messages for streaming to a file/elsewhere.  This would solve part of the problem as interfaces would auto-generate the code for dealing with sending multiple messages in a single stream.~~
 - Otherwise a few well-tested C/C++ functions could take care of the issue for all the interfaces.

## Alternatives:

* A serialization-only library, examples:
 - [boost::serialization](http://www.boost.org/doc/libs/1_60_0/libs/serialization/doc/index.html),
 - [cereal](http://uscilab.github.io/cereal/serialization_archives.html)
* A serialization-only library, issues:
 - Interfaces would still need to deal with reading the format
 - Wrong fit for passing parameters to something like CmdStan, so "only" a data serialization solution,
* Protocol Buffers alternatives, examples:
 - [Cap'n Proto](https://capnproto.org)
  - same key developer as Protocol Buffers (team product, disclaimer, just interesting point).
  - mmap-able
  - no encoding step
  - sandstorm.io server integration
 - [Flat Buffers](http://google-opensource.blogspot.com/2014/06/flatbuffers-memory-efficient.html)
  - Similar goals as Cap'n Proto, [comparison](https://capnproto.org/news/2014-06-17-capnproto-flatbuffers-sbe.html)
 - [Simple Binary Encoding](http://mechanical-sympathy.blogspot.com/2014/05/simple-binary-encoding.html)
  - Similar goals as Cap'n Proto, same [comparison](https://capnproto.org/news/2014-06-17-capnproto-flatbuffers-sbe.html)
* Protocol Buffers alternatives, issues:
 - Not as well demonstrated
 - Not as broad language support (yet anyway)
 - All have message size issue as it is a security issue (arbitrary message size limits to prevent DOS attach on server).
