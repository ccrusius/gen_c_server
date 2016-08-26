[![Build Status](https://travis-ci.org/ccrusius/gen_c_server.svg?branch=master)](https://travis-ci.org/ccrusius/gen_c_server)

# Erlang Generic C Node Server

A library that ties together Erlang's `gen_server` with Erlang's C nodes.
For more details, consult the
[documentation](http://htmlpreview.github.io/?https://github.com/ccrusius/gen_c_server/blob/master/doc/index.html),
which is checked in for
convenience.

Inspired by Robby Raschke's work on
[interfacing with Lua](https://github.com/rtraschke/erlang-lua).

# Compiling

In a Unix system, typing `./gradlew install` should do it. Type
`./gradlew tasks` to get a list of available build targets.

A makefile is provided with convenience targets used during
development. The `ct` target, for example, sets up and tears down
`epmd` automatically so that tests can be performed. `make shell` will
bring you into an Erlang shell with the correct paths set for
interactively testing things.

# Compiling on Windows

Download the latest
[pthreads-win32](https://sourceware.org/pthreads-win32/) pre-compiled
ZIP. Unzip it into a `pthreads-win32` directory at the root of your
checkout of this project. This should allow you to build with the
Gradle script.
