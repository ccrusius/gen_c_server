-module(call_counter_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0,init_per_suite/1,init_per_testcase/2,end_per_testcase/2]).

-export([command_not_found/1,
         start_then_stop/1,
         ping_me/1,
         count_calls/1,
         parallel_calls/1,
         count_casts/1,
         parallel_casts/1,
         count_infos/1,
         parallel_infos/1
        ]).

all() -> [command_not_found,
          start_then_stop,
          ping_me,
          count_calls,
          parallel_calls,
          count_casts,
          parallel_casts,
          count_infos,
          parallel_infos
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
    CNode = filename:join([os:getenv("ROOT_DIR"),"build","cnodes","call_counter"]),
    [ {cnode, CNode} | Config ].

end_per_testcase(_TestCase, _Config) ->
    ok.

%%==============================================================================
%%
%% TESTS
%%
%%==============================================================================
command_not_found(_Config) ->
    {error, {command_not_found,_}} = gen_c_server:start("~#$@*#&$",[],[]).

start_then_stop(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    gen_c_server:stop(Pid).

ping_me(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    %
    % Yes, this is knowing too much about the internal state's structure, but
    % I rather do this, and fix it every time it breaks, than to expose the
    % internal state in an 'hrl' file other people could think they could use.
    %
    {state,_Port,{_,Id},_Buffer,_CNodeState} = sys:get_state(Pid),
    pong = net_adm:ping(Id),
    gen_c_server:stop(Pid).

count_calls(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    {1,0,0} = gen_c_server:call(Pid,ok),
    {2,0,0} = gen_c_server:call(Pid,[]),
    {3,0,0} = gen_c_server:call(Pid,{ok}),
    gen_c_server:stop(Pid).

parallel_calls(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    Num     = 1000,
    Replies = pmap(fun(I)->gen_c_server:call(Pid,I) end,lists:duplicate(Num,0)),
    Desired = lists:map(fun(I) -> {I,0,0} end, lists:seq(1,Num)),
    Desired = lists:sort(Replies),
    gen_c_server:stop(Pid).

count_casts(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    {1,0,0} = gen_c_server:call(Pid,ok),
    ok = gen_c_server:cast(Pid, ok),
    ok = gen_c_server:cast(Pid, []),
    ok = gen_c_server:cast(Pid, [ok]),
    {2,3,0} = gen_c_server:call(Pid,ok),
    gen_c_server:stop(Pid).

parallel_casts(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    Num     = 1000,
    Replies = pmap(fun(I)->gen_c_server:cast(Pid,I) end,lists:duplicate(Num,0)),
    Desired = lists:duplicate(Num,ok),
    Desired = Replies,
    Self    = self(),
    WaitPid = spawn(fun() -> wait_for_num_casts(Self,Pid,Num) end),
    receive {WaitPid,ok} -> gen_c_server:stop(Pid)
    after   1000 -> exit(WaitPid,timeout),
                    {failed, "Timeout waiting for parallel casts"}
    end.

wait_for_num_casts(From,ServerPid,Num) ->
    case gen_c_server:call(ServerPid,ok) of
        {_,Num,_} -> From ! {self(), ok};
        {_,_N,_}  -> timer:sleep(50),
                     %io:fwrite("Want ~w, got ~w~n",[Num,_N]),
                     wait_for_num_casts(From,ServerPid,Num)
    end.

count_infos(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
    {1,0,0} = gen_c_server:call(Pid,ok),
    Pid ! ok,
    Pid ! [],
    Pid ! [ok],
    {2,0,3} = gen_c_server:call(Pid,ok),
    gen_c_server:stop(Pid).

parallel_infos(Config) ->
    {ok, Pid} = gen_c_server:start(?config(cnode,Config),[],[{tracelevel,0}]),
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
    case gen_c_server:call(ServerPid,ok) of
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
    gather(Pids).

pmap_do(Client,Fun,Item) ->
    %io:fwrite("pmap_do(~w,~w,~w): self=~w",[Client,Fun,Item,self()]),
    V = Fun(Item),
    %io:fwrite("pmap_do(~w,~w): message will be {~w,~w}",[Client,Fun,self(),V]),
    Client ! {self(),V}.

gather([]) -> [];
gather([H|T]) ->
    receive
        {H,Ret} ->
            %io:fwrite("gather(~w) received {~w,~w}",[[H|T],H,Ret]),
            [Ret|gather(T)]
    end.
