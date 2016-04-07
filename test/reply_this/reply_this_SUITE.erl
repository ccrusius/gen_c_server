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

all() -> [
          normal_replies,
          timeout_replies,
          call_stop,
          cast_stop,
          info_stop
         ].

%%==============================================================================
%%
%% SETUP AND TEARDOWN
%%
%%==============================================================================
init_per_suite(Config) ->
    net_kernel:start([ct,longnames]),
    Config.

init_per_testcase(_TestCase, Config) ->
    CNode = filename:join([os:getenv("ROOT_DIR"),"build","cnodes","reply_this"]),
    [ {cnode, CNode} | Config ].

end_per_testcase(_TestCase, _Config) ->
    ok.

%%==============================================================================
%%
%% TESTS
%%
%%==============================================================================
normal_replies(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    10 = gen_c_server:call(Pid,{reply_this,{reply,10,undefined}}),
    ok = gen_c_server:call(Pid,{reply_this,{reply,ok,[ok]}}),
    [] = gen_c_server:call(Pid,{reply_this,{reply,[],10}}),
    ok = gen_c_server:cast(Pid,{reply_this,{noreply,undefined}}),
    Pid ! {reply_this,{noreply,undefined}},
    gen_c_server:stop(Pid).

timeout_replies(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    ok = gen_c_server:cast(Pid,{reply_this,{noreply,undefined,hibernate}}),
    10 = gen_c_server:call(Pid,{reply_this,{reply,10,undefined,hibernate}}),
    Pid ! {reply_this,{noreply,undefined,hibernate}},
    gen_c_server:stop(Pid).

call_stop(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    10 = gen_c_server:call(Pid,{reply_this,{stop,"I was asked to",10,undefined}}),
    case (catch gen_c_server:stop(Pid)) of
        {'EXIT',{noproc,_}} -> ok;
        {'EXIT',{"I was asked to",_}} -> ok
    end.

cast_stop(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    ok = gen_c_server:cast(Pid,{reply_this,{stop,"I was asked to",undefined}}),
    case (catch gen_c_server:stop(Pid)) of
        {'EXIT',{noproc,_}} -> ok;
        {'EXIT',{"I was asked to",_}} -> ok
    end.

info_stop(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    Pid ! {reply_this,{stop,"I was asked to",undefined}},
    case (catch gen_c_server:stop(Pid)) of
        {'EXIT',{noproc,_}} -> ok;
        {'EXIT',{"I was asked to",_}} -> ok
    end.

