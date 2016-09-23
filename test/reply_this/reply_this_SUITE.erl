-module(reply_this_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0,init_per_suite/1,init_per_testcase/2,end_per_testcase/2]).

-export([
         normal_replies/1,
         timeout_replies/1,
         call_stop/1,
         cast_stop/1,
         info_stop/1
        ]).

-export([ c_node/0, init/2, terminate/2, handle_info/2 ]).

all() -> [
          normal_replies,
          timeout_replies,
          call_stop,
          cast_stop,
          info_stop
         ].

%%% ---------------------------------------------------------------------------
%%%
%%% custom_gen_c_server callbacks
%%%
%%% This test suite uses a "custom" `gen_c_server' that was produced
%%% by the build system by renaming the module.
%%%
%%% ---------------------------------------------------------------------------
c_node() ->
    filename:join([os:getenv("ROOT_DIR"),
                   "build","install","reply_this","lib",
                   "reply_this"]).

init(Args, Opaque) ->
    custom_gen_c_server:c_init(Args, Opaque, spawn).

terminate(Reason, ServerState) ->
    custom_gen_c_server:c_terminate(Reason, ServerState).

handle_info(Info, ServerState) ->
    custom_gen_c_server:c_handle_info(Info, ServerState).


%%==============================================================================
%%
%% SETUP AND TEARDOWN
%%
%%==============================================================================
init_per_suite(Config) ->
    net_kernel:start([ct,longnames]),
    Config.

init_per_testcase(_TestCase, Config) -> Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%==============================================================================
%%
%% TESTS
%%
%%==============================================================================
normal_replies(_Config) ->
    {ok, Pid} = custom_gen_c_server:start(?MODULE,[],[{tracelevel,10}]),
    10 = custom_gen_c_server:c_call(Pid,{reply_this,{reply,10,undefined}}),
    ok = custom_gen_c_server:c_call(Pid,{reply_this,{reply,ok,[ok]}}),
    [] = custom_gen_c_server:c_call(Pid,{reply_this,{reply,[],10}}),
    ok = custom_gen_c_server:c_cast(Pid,{reply_this,{noreply,undefined}}),
    Pid ! {reply_this,{noreply,undefined}},
    custom_gen_c_server:stop(Pid).

timeout_replies(_Config) ->
    {ok, Pid} = custom_gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    ok = custom_gen_c_server:c_cast(Pid,{reply_this,{noreply,undefined,hibernate}}),
    10 = custom_gen_c_server:c_call(Pid,{reply_this,{reply,10,undefined,hibernate}}),
    Pid ! {reply_this,{noreply,undefined,hibernate}},
    custom_gen_c_server:stop(Pid).

call_stop(_Config) ->
    {ok, Pid} = custom_gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    10 = custom_gen_c_server:c_call(Pid,{reply_this,{stop,"I was asked to",10,undefined}}),
    case (catch custom_gen_c_server:stop(Pid)) of
        {'EXIT',{noproc,_}} -> ok;
        {'EXIT',{"I was asked to",_}} -> ok
    end.

cast_stop(_Config) ->
    {ok, Pid} = custom_gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    ok = custom_gen_c_server:c_cast(Pid,{reply_this,{stop,"I was asked to",undefined}}),
    case (catch custom_gen_c_server:stop(Pid)) of
        {'EXIT',{noproc,_}} -> ok;
        {'EXIT',{"I was asked to",_}} -> ok
    end.

info_stop(_Config) ->
    {ok, Pid} = custom_gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    Pid ! {reply_this,{stop,"I was asked to",undefined}},
    case (catch custom_gen_c_server:stop(Pid)) of
        {'EXIT',{noproc,_}} -> ok;
        {'EXIT',{"I was asked to",_}} -> ok
    end.

