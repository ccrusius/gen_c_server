-module(call_counter_SUITE).
-behaviour(gen_c_server).
-include_lib("common_test/include/ct.hrl").
-export([all/0,init_per_suite/1,init_per_testcase/2,end_per_testcase/2]).

-export([start_then_stop/1,
         ping_me/1,
         count_calls/1,
         parallel_calls/1,
         count_casts/1,
         parallel_casts/1,
         count_infos/1,
         parallel_infos/1
        ]).

%%%============================================================================
%%%
%%% gen_c_server exports
%%%
%%%============================================================================
-export([ c_node/0, init/2, terminate/2, handle_info/2 ]).

%%%============================================================================
%%%
%%% Tests to run
%%%
%%%============================================================================
all() -> [ start_then_stop,
          ping_me,
          count_calls,
          parallel_calls,
          count_casts,
          parallel_casts,
          count_infos,
          parallel_infos
         ].

%%%============================================================================
%%%
%%% gen_c_server callbacks
%%%
%%%============================================================================
c_node() ->
    CNode = filename:join([os:getenv("ROOT_DIR"),
                           "build","install","call_counter","lib",
                           "call_counter"]).

init(Args, Opaque) ->
    gen_c_server:c_init(Args, Opaque).

terminate(Reason, ServerState) ->
    gen_c_server:c_terminate(Reason, ServerState).

handle_info(Info, ServerState) ->
    gen_c_server:c_handle_info(Info, ServerState).

%%==============================================================================
%%
%% SETUP AND TEARDOWN
%%
%%==============================================================================
init_per_suite(Config) ->
    net_kernel:start([ct,longnames]),
    Config.

init_per_testcase(_TestCase, Config) -> Config.

end_per_testcase(_TestCase, _Config) -> ok.

%%==============================================================================
%%
%% TESTS
%%
%%==============================================================================
start_then_stop(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    gen_c_server:stop(Pid).

ping_me(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    %
    % Yes, this is knowing too much about the internal state's structure, but
    % I rather do this, and fix it every time it breaks, than to expose the
    % internal state in an 'hrl' file other people could think they could use.
    %
    {_State, {state, _Mod, _Port, {_,Id}, _Buffer, _Trace}} = sys:get_state(Pid),
    pong = net_adm:ping(Id),
    gen_c_server:stop(Pid).

count_calls(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    {1,0,0} = gen_c_server:c_call(Pid,ok),
    {2,0,0} = gen_c_server:c_call(Pid,[]),
    {3,0,0} = gen_c_server:c_call(Pid,{ok}),
    gen_c_server:stop(Pid).

parallel_calls(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    Num     = 1000,
    Replies = pmap(fun(I)->gen_c_server:c_call(Pid,I) end,lists:duplicate(Num,0)),
    Desired = lists:map(fun(I) -> {I,0,0} end, lists:seq(1,Num)),
    Desired = lists:sort(Replies),
    gen_c_server:stop(Pid).

count_casts(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    {1,0,0} = gen_c_server:c_call(Pid,ok),
    ok = gen_c_server:c_cast(Pid, ok),
    ok = gen_c_server:c_cast(Pid, []),
    ok = gen_c_server:c_cast(Pid, [ok]),
    {2,3,0} = gen_c_server:c_call(Pid,ok),
    gen_c_server:stop(Pid).

parallel_casts(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    Num     = 1000,
    Replies = pmap(fun(I)->gen_c_server:c_cast(Pid,I) end,lists:duplicate(Num,0)),
    Desired = lists:duplicate(Num,ok),
    Desired = Replies,
    Self    = self(),
    WaitPid = spawn(fun() -> wait_for_num_casts(Self,Pid,Num) end),
    receive {WaitPid,ok} -> gen_c_server:stop(Pid)
    after   1000 -> exit(WaitPid,timeout),
                    {failed, "Timeout waiting for parallel casts"}
    end.

wait_for_num_casts(From,ServerPid,Num) ->
    case gen_c_server:c_call(ServerPid,ok) of
        {_,Num,_} -> From ! {self(), ok};
        {_,_N,_}  -> timer:sleep(50),
                     %io:fwrite("Want ~w, got ~w~n",[Num,_N]),
                     wait_for_num_casts(From,ServerPid,Num)
    end.

count_infos(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    {1,0,0} = gen_c_server:c_call(Pid,ok),
    Pid ! ok,
    Pid ! [],
    Pid ! [ok],
    {2,0,3} = gen_c_server:c_call(Pid,ok),
    gen_c_server:stop(Pid).

parallel_infos(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    Num     = 1000,
    Replies = pmap(fun(I)-> Pid ! I, ok end,lists:duplicate(Num,0)),
    Desired = lists:duplicate(Num,ok),
    Desired = Replies,
    Self    = self(),
    WaitPid = spawn(fun() -> wait_for_num_infos(Self,Pid,Num) end),
    receive {WaitPid,ok} -> gen_c_server:stop(Pid)
    after   1000 -> exit(WaitPid,timeout),
                    {failed, "Timeout waiting for parallel infos"}
    end.

wait_for_num_infos(From,ServerPid,Num) ->
    case gen_c_server:c_call(ServerPid,ok) of
        {_,_,Num} -> From ! {self(), ok};
        {_,_,_N}  -> timer:sleep(50),
                     %io:fwrite("Want ~w, got ~w~n",[Num,_N]),
                     wait_for_num_infos(From,ServerPid,Num)
    end.

%%==============================================================================
%%
%% PARALLEL MAP
%%
%%==============================================================================
pmap(Fun,List) ->
    Self = self(),
    %io:fwrite("pmap: self=~w~n",[Self]),
    Pids = lists:map(fun(Item) ->
                       spawn(fun() -> pmap_do(Self,Fun,Item) end)
                     end,
                     List),
    gather(Pids, []).

pmap_do(Client,Fun,Item) ->
    %io:fwrite("pmap_do(~w,~w,~w): self=~w",[Client,Fun,Item,self()]),
    V = Fun(Item),
    %io:fwrite("pmap_do(~w,~w): message will be {~w,~w}",[Client,Fun,self(),V]),
    Client ! {self(),V}.

gather([], Acc) -> lists:reverse(Acc);
gather([H|T], Acc) ->
    receive
        {H,Ret} ->
            %io:fwrite("gather(~w) received {~w,~w}",[[H|T],H,Ret]),
            gather(T, [Ret|Acc])
    end.
