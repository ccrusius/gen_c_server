# Generic C Node Server

A library that ties together Erlang's `gen_server` with Erlang's C nodes.
Based on Robby Raschke's [excellent work](https://github.com/rtraschke/erlang-lua)
getting a Lua C node to work properly.

# Introduction

Interfacing Erlang to C can be done in many different ways: via NIFs, port
drivers, and C nodes, to mention three ways. C nodes are the safest way, and
in some ways the most versatile: if you manage to get a C node working, you
can have many of them running in parallel, completely independent of each other,
and if they crash nobody else is affected.

The problem with C nodes is that it is pretty hard to get them working
transparently: you have to manually start the C node, manually establish
communications between it and the Erlang VM, take care of not blocking the
event loop, and the list goes on and on.

The outline of the proper solution was given by Robby Raschke's work on
a Lua C node (Erlang factory presentation
[here](http://www.erlang-factory.com/static/upload/media/1417718639497123robby_raschke_erlanglua_c_node.html#1)).
What I did here was to generalize his solution in terms of a new Erlang
behavior,
with a supporting C library that makes the implementation of C nodes much easier.
