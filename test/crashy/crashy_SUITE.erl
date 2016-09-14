-module(crashy_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0,init_per_suite/1,init_per_testcase/2,end_per_testcase/2]).

-export([
         start_then_stop/1,
         crash_in_call/1,
         segfault_in_call/1,
         abort_in_call/1,
         crash_in_cast/1,
         segfault_in_cast/1,
         abort_in_cast/1,
         crash_in_info/1,
         segfault_in_info/1,
         abort_in_info/1
        ]).

-export([ c_node/0, init/2, terminate/2, handle_info/2 ]).

all() -> [
          start_then_stop,
          crash_in_call,
          segfault_in_call,
          abort_in_call,
          crash_in_cast,
          segfault_in_cast,
          abort_in_cast,
          crash_in_info,
          segfault_in_info,
          abort_in_info
         ].

%%%============================================================================
%%%
%%% gen_c_server callbacks
%%%
%%%============================================================================
c_node() ->
    filename:join([os:getenv("ROOT_DIR"),
                   "build","install","crashy","lib",
                   "crashy"]).

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

crash_in_call(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    {'EXIT',{{port_status,10},_}} = (catch gen_c_server:c_call(Pid,{stop,10})),
    {'EXIT',{noproc,_}} = (catch gen_c_server:stop(Pid)),
    ok.

segfault_in_call(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    {'EXIT',{{port_status,_},_}} = (catch gen_c_server:c_call(Pid,segfault)),
    {'EXIT',{noproc,_}} = (catch gen_c_server:stop(Pid)),
    ok.

abort_in_call(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    {'EXIT',{{port_status,_},_}} = (catch gen_c_server:c_call(Pid,abort)),
    {'EXIT',{noproc,_}} = (catch gen_c_server:stop(Pid)),
    ok.

crash_in_cast(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    ok = gen_c_server:c_cast(Pid,{stop,10}),
    {'EXIT',{{port_status,10},_}} = (catch gen_c_server:stop(Pid)),
    ok.

segfault_in_cast(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    ok = gen_c_server:c_cast(Pid,segfault),
    {'EXIT',{{port_status,_},_}} = (catch gen_c_server:stop(Pid)),
    ok.

abort_in_cast(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    ok = gen_c_server:c_cast(Pid,abort),
    {'EXIT',{{port_status,_},_}} = (catch gen_c_server:stop(Pid)),
    ok.

crash_in_info(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    Pid ! {stop,10},
    {'EXIT',{{port_status,10},_}} = (catch gen_c_server:stop(Pid)),
    ok.

segfault_in_info(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    Pid ! segfault,
    {'EXIT',{{port_status,_},_}} = (catch gen_c_server:stop(Pid)),
    ok.

abort_in_info(_Config) ->
    {ok, Pid} = gen_c_server:start(?MODULE,[],[{tracelevel,0}]),
    Pid ! abort,
    {'EXIT',{{port_status,_},_}} = (catch gen_c_server:stop(Pid)),
    ok.
