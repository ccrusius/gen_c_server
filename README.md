[![Build Status](https://travis-ci.org/ccrusius/gen_c_server.svg?branch=master)](https://travis-ci.org/ccrusius/gen_c_server)

# Erlang Generic C Node Server

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-generate-toc again -->
**Table of Contents**

- [Erlang Generic C Node Server](#erlang-generic-c-node-server)
- [Summary](#summary)
- [Erlang: The Behaviour](#erlang-the-behaviour)
    - [The `c_node/0` Callback](#the-cnode0-callback)
    - [The Internal Server State](#the-internal-server-state)
    - [Starting the Server, and the `init/2` Callback](#starting-the-server-and-the-init2-callback)
    - [Stopping the Server, and the `terminate/2` Callback](#stopping-the-server-and-the-terminate2-callback)
    - [Synchronous Calls to Erlang and the C Node](#synchronous-calls-to-erlang-and-the-c-node)
    - [Asynchronous Calls to Erlang and the C Node](#asynchronous-calls-to-erlang-and-the-c-node)
    - [Out-of-Band Messages](#out-of-band-messages)
    - [Callback Summary](#callback-summary)
    - [Function Summary](#function-summary)
- [C: Writing a C Node](#c-writing-a-c-node)
    - [Limitations](#limitations)
    - [Compiling](#compiling)
    - [Compiling on Windows](#compiling-on-windows)

<!-- markdown-toc end -->

A behaviour that ties together Erlang's `gen_server` with Erlang's C
nodes.

[C nodes](http://erlang.org/doc/tutorial/cnode.html)
are a way of implementing native binaries, written in C, that behave
like Erlang nodes, capable of sending and receiving messages from Erlang
processes. Amongst the ways of interfacing Erlang with C, C nodes are the
most robust: since the nodes are independent OS processes, crashes do not
affect the Erlang VM. Compare this to a NIF, for example, where a problem in
the C code may cause the entire Erlang VM to crash. The price to pay is,
of course, performance.

Making C nodes work with Erlang, however, is not a simple task. Your
executable is started by hand, and has to set up communications with an
existing Erlang process. Since the executable does not know where to connect
to in advance, the necessary parameters have to be given to it in the
command line  when the C node is started.
Once all of that is done, the C node
enters a message loop, waiting for messages and replying to them. If the
computations it is performing take too long, the calling Erlang process may
infer that the C node is dead, and cut communications with it. This is
because Erlang will be sending `TICK` messages to the C node to keep the
connection alive. The only way around this is to make the C node have
separate threads to deal with user-generated messages and system-generated
messages. The list does go on.

This module, and its accompanying library, `libgen_c_server.a`, hide this
complexity and require the C node implementer to define only the equivalent
`gen_server` callbacks in C, and a `gen_c_server` callback module
in Erlang. Within the C callbacks, the developer uses
the `ei` library to manipulate Erlang terms.

Inspired by Robby Raschke's work on
[interfacing with Lua](https://github.com/rtraschke/erlang-lua).

# Summary

1. [Write a C node](#c-writing-a-c-node)
2. Write an Erlang callback module with `gen_c_server` behaviour.
   * Call `c_init` from `init`, and `c_terminate` from `terminate`.
   * Forward `handle_info` to `c_handle_info` if desired.

We will start with the Erlang callback module description, since this
part should be more familiar to Erlang users.

# Erlang: The Behaviour

If you are not familiar with the
standard [`gen_server`](http://erlang.org/doc/man/gen_server.html)
behaviour, please take some time to study it before tackling this
one. The description that follows relies heavily on describing
`gen_c_server` _in terms of `gen_server`_.

We will describe how to write the C node
in [another section](#c-writing-a-c-node). In this one, we'll describe
the behaviour functions and callbacks. In what follows, `Mod` will
refer to the Erlang module implementing this behaviour. That module's
definition will contain something like this at the beginning:
```erlang
-module(example_module).
-behaviour(gen_c_server).
```

## The `c_node/0` Callback

The callback module should define a `c_node` function, which returns a
string with the path to the C node executable.
```erlang
c_node() ->
  "/path/to/c/node/executable".
```

## The Internal Server State

In `gen_server`, the internals of the server implementation are
completely hidden. In `gen_c_server`, however, there is one bit of
internal server state that gets passed around in some functions. The
internal server state is a tuple `{State, Opaque}`, where `State` is
the equivalent to `gen_server`'s state, and `Opaque` is something
internal to the `gen_c_server`. This tuple is passed in to every
callback that normally takes in a state argument. Those callbacks
should also return a `{NewState, NewOpaque}` instead of the simple
state value.

The reason this has to be exposed is because, in callbacks such as
`init/2` and `terminate/2`, the callback has to ask the server to talk
to the C node, and the `Opaque` structure gives `gen_c_server` the
information needed to do so. This will become clearer when we document
the callbacks below, but now you know the reason why `Opaque` will pop
up here and there.

## Starting the Server, and the `init/2` Callback

In a `gen_server`, the callback module needs to implement a `init/1`
callback, which is called by the various server `start` functions. In
`gen_c_server`, this function takes an extra argument, `Opaque`,
representing the internal state of the server.

It is the job of this `init/2` callback to initialize the C node, and
it can do that by a call to `gen_c_server:c_init(Args, Opaque)`, where
`Args` is an arbitrary value (usually the same as the first input
argument), and `Opaque` is the second input value to `init/2`. The
function will start the C node and call its `gcs_init`
function. Depending on what it returns, `c_init` will return one of

* `{ok, {State, NewOpaque}}`
* `{ok, {State, NewOpaque}, hibernate | Timeout}`
* `{stop, Reason}`
* `ignore`

The meaning of those is similar to the usual `gen_server` expected
returns from `init/1`, except they need to include the `Opaque`
parameters in the state.

The `init/2` callback should return one of those values too, so its
simplest implementation, if the Erlang portion does not care about
state or massaging the `Args` parameters, is
```erlang
init(Args, Opaque) -> gen_c_server:c_init(Args, Opaque).
```
Of course, the function is free to modify the input `Args`, or the
`State` returned by `c_init`. What it should _not_ do is mess
around with the `Opaque` parameters.

## Stopping the Server, and the `terminate/2` Callback

The logic behind the `init/2` callback applies verbatim to the
`terminate/2` callback. In `gen_server`, the callback takes in the
`Reason` and the `State`, and does whatever it needs to do to clean
up. In `gen_c_server`, there are two differences:

* The `terminate` state argument is instead `{State, Opaque}`, for
  reasons described above.
* The callback should call the `gen_c_server:c_terminate` function,
  which will take care of calling the C node's `gcs_terminate`
  function, and shutting the C node down.

The `c_terminate` function accepts the same parameters as
`terminate/2`, so the simplest callback implementation is
```erlang
terminate(Reason, {State, Opaque} = ServerState) ->
  gen_c_server:c_terminate(Reason, ServerState).
```

## Synchronous Calls to Erlang and the C Node

Synchronous calls to the Erlang callback module are done by calling
`gen_c_server:call/2`. The Erlang callback `handle_call/3` is called,
and again it takes in a `{State, Opaque}` tuple instead of
`gen_server`'s single `State`. When it returns new state, it must
return it in the form `{NewState, Opaque}`.

The `Opaque` value would only be useful if the `handle_call/3`
callback could call the C node somehow. Currently that is not
possible, but by having the parameter there we can add the
functionality without breaking backwards compatibility.

Synchronous calls to the C node are made via the
`gen_c_server:c_call/2` function, which calls the `gcs_handle_call` C
node callback. This callback does not receive the `{State, Opaque}`
tuple, since it doesn't need `Opaque` for anything. Instead, it simply
receives the `State`.

## Asynchronous Calls to Erlang and the C Node

Asynchronous calls follow the same logic as synchronous ones, except
that `call` is replaced by `cast`: The `gen_c_server:cast/2` function
calls the `handle_cast` callback which gets `{State, Opaque}` and
needs to reply with `{NewState, Opaque}`. Asynchronous calls to the C
node are done with `gen_c_server:c_cast/2`, and call the C node's
`gcs_handle_call` callback with `State`.

## Out-of-Band Messages

Lastly, out-of-band messages are always passed on to the Erlang
module's `handle_info/2` callback, which, as usual, gets the
`{State, Opaque}` tuple as the state argument. The callback can pass
the message on to the C node by calling `gen_c_server:c_handle_info/2`
with the same arguments as its input, which will result in a call to
the C node's `gcs_handle_info`.

## Callback Summary

* `init/2`
* `terminate/2`
* `c_node/0`
* `handle_call/3`
* `handle_cast/2`
* `handle_info/2`

## Function Summary

* `start/3`, `start/4`, `start_link/3`, `start_link/4`: These are
  completely equivalent to `gen_server`'s functions of the same
  signature.
* `stop/1`: Terminates the server, including shutting down the C node.
* `call/2`, `call/3`
* `cast/2`
* `c_init/2`
* `c_call/2`, `c_call/3`
* `c_terminate/2`
* `c_cast/2`
* `c_handle_info/2`


# C: Writing a C Node

A C node is written by implementing the necessary callbacks, and linking
the executable against `libgen_c_server.a`, which defines `main()` for you.
When implementing callbacks, the rule of thumb is this: for each callback
you would implement in an Erlang `gen_server` callback module, implement a
`gcs_`_name_ function in C instead. This function takes in the same
arguments as the Erlang callback, plus a last `ei_x_buff*` argument where the
function should build its reply (when a reply is needed). The other
arguments are `const char*` pointing to `ei` buffers containing the
arguments themselves. C node callbacks that receive a state receive
`State`, not the `{State, Opaque}` tuple the Erlang callbacks
receive. (The `Opaque` argument is necessary in Erlang so the C node
can be called, so it is useless inside the C node itself.)

A full C node skeleton thus looks like this:
```c
#include "gen_c_server.h"

void gcs_init(const char *args_buff, ei_x_buff *reply) {
  /* IMPLEMENT ME */
}

void gcs_handle_call(const char *request_buff,
                     const char *from_buff,
                     const char *state_buff,
                     ei_x_buff *reply) {
  /* IMPLEMENT ME */
}

void gcs_handle_cast(const char *request_buff,
                     const char *state_buff,
                     ei_x_buff *reply) {
  /* IMPLEMENT ME */
}

void gcs_handle_info(const char *info_buff,
                     const char *state_buff,
                     ei_x_buff *reply) {
  /* IMPLEMENT ME */
}

void gcs_terminate(const char *reason_buff, const char *state_buff) {
  /* IMPLEMENT ME */
}
```
Let's see how this looks like in a C node that simply counts the number
of calls made to each function. (This C node is included in the source
distribution of `gen_c_server`, as one of the tests.) In this C node,
We make use of an utility `gcs_decode` function which is provided by the
`gen_c_server` library, that allows us to decode `ei` buffers in a
`sscanf`-like manner. Consult the header file for more details.
```c
#include "gen_c_server.h"

/*
 * Utility function that encodes a state tuple based on the arguments.
 * The state is a 3-tuple, { num_calls, num_casts, num_infos }
 */
static void encode_state(
        ei_x_buff *reply,
        long ncalls,
        long ncasts,
        long ninfos)
{
    ei_x_encode_tuple_header(reply,3);
    ei_x_encode_long(reply,ncalls);
    ei_x_encode_long(reply,ncasts);
    ei_x_encode_long(reply,ninfos);
}

/*
 * Initialize the C node, replying with a zeroed-out state.
 */
void gcs_init(const char* args_buff, ei_x_buff *reply)
{
    /* Reply: {ok,{0,0,0}} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"ok");
    encode_state(reply,0,0,0);
}

/*
 * When called, increment the number of calls, and reply with the new state.
 */
void gcs_handle_call(
        const char *request_buff,
        const char *from_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    long ncalls, ncasts, ninfos;
    gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);

    /* Reply: {reply,Reply=NewState,NewState={ncalls+1,ncasts,ninfos}} */
    ei_x_encode_tuple_header(reply,3);
    ei_x_encode_atom(reply,"reply");
    encode_state(reply,ncalls+1,ncasts,ninfos);
    encode_state(reply,ncalls+1,ncasts,ninfos);
}

/*
 * When casted, increment the number of casts, and reply with the new state.
 */
void gcs_handle_cast(
        const char *request_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    long ncalls, ncasts, ninfos;
    gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);

    /* Reply: {noreply,NewState={ncalls,ncasts+1,ninfos}} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"noreply");
    encode_state(reply,ncalls,ncasts+1,ninfos);
}

/*
 * When info-ed, increment the number of infos, and reply with the new state.
 */
void gcs_handle_info(
        const char *info_buff,
        const char *state_buff,
        ei_x_buff  *reply)
{
    long ncalls, ncasts, ninfos;
    gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);

    /* Reply: {noreply,NewState={ncalls,ncasts,ninfos+1}} */
    ei_x_encode_tuple_header(reply,2);
    ei_x_encode_atom(reply,"noreply");
    encode_state(reply,ncalls,ncasts,ninfos+1);
}

/*
 * We don't need to clean anything up when terminating.
 */
void gcs_terminate(const char *reason_buff, const char *state_buff) { }
```

Once you compile (with the appropriate flags so the compiler finds
`gen_c_server.h` and `ei.h`) and link (with the appropriate flags to the
linker links in `libgen_c_server`, `erl_interface`, and `ei` libraries) this
node, you can define a simple Erlang callback module as follows:
```erlang
-module(my_c_server).
-behaviour(gen_c_server).
-export([c_node/0, init/2, terminate/2, handle_info/2]).

c_node() -> "/path/to/my/c/node/executable".
init(Args, Opaque) -> gen_c_server:c_init(Args, Opaque).
terminate(Reason, ServerState) -> gen_c_server:c_terminate(Reason, ServerState).
handle_info(Info, ServerState) -> gen_c_server:c_handle_info(Info, ServerState).
```
With that, you can now:
```erlang
{ok,Pid} = gen_c_server:start(my_c_server,[],[]),
{1,0,0} = gen_c_server:c_call(Pid,"Any message"),
ok = gen_c_server:c_cast(Pid,"Any old message"),
{2,1,0} = gen_c_server:c_call(Pid,"Any message"),
Pid ! "Any message, really",
{3,1,1} = gen_c_server:c_call(Pid,[]),
gen_c_server:stop(Pid).
```
Note that the Erlang shell has to have a registered name, which means
you have to start it with either the `-name` or `-sname` options passed in.
This is because the C node needs a registered Erlang node to connect to.

## Limitations

Currently, not all replies from the callback functions are accepted.
In particular,

* `gcs_handle_call` can only reply `{reply,Reply,NewState}`,
     `{reply,Reply,NewState,hibernate}` or `{stop,Reason,Reply,NewState}`.
* `gcs_handle_cast` can only reply `{noreply,NewState}`,
     `{noreply,NewState,hibernate}` or `{stop,Reason,NewState}`.
* `gcs_handle_info` can only reply `{noreply,NewState}`,
     `{noreply,NewState,hibernate}` or `{stop,Reason,NewState}`.

## Compiling

In a Unix system, typing `./gradlew install` should do it. Type
`./gradlew tasks` to get a list of available build targets.

A makefile is provided with convenience targets used during
development. The `ct` target, for example, sets up and tears down
`epmd` automatically so that tests can be performed. `make shell` will
bring you into an Erlang shell with the correct paths set for
interactively testing things.

## Compiling on Windows

Download the latest
[pthreads-win32](https://sourceware.org/pthreads-win32/) pre-compiled
ZIP. Unzip it into a `pthreads-win32` directory at the root of your
checkout of this project. This should allow you to build with the
Gradle script.
