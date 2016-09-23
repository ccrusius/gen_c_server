%%==============================================================================
%%
%% %CopyrightBegin%
%%
%% Copyright Cesar Crusius 2016. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
%%==============================================================================
%%
%% == Internals ==
%%
%% The `gen_c_server' Erlang module acts as a proxy between a `gen_server' and
%% a C node. In other words, it works by using OTP's `gen_server' to start a
%% `gen_c_server' instance, and this instance will in turn start the C node and
%% forward everything `gen_server' sends its way to the C node.
%%
%% The C node executable is started and connected to an Erlang Port, which
%% then receives as messages whatever the C node prints to `stdout'. The C
%% node itself then uses a convention to send some messages to the Erlang
%% `gen_c_server' process by printing them to `stdout'. In order to
%% differentiate between these messages and whatever else the executable prints
%% out, messages meant to `gen_c_server' are enclosed between special markers.
%% Anything the Erlang side of `gen_c_server' receives outside of these markers
%% is immediately printed to Erlang's `stdout'.
%%
%% === The Initialization Flow ===
%%
%% If we omit the execution loop that is running on a separate thread (for
%% simplicity of explanation), the internals of starting a C server are
%% as follows:
%% ```
%%                                                     C node           C node
%% # gen_c_server module       gen_server module  libgen_c_server.a  user-defined
%% - -------------------       -----------------  -----------------  ------------
%% 1 gen_c_server:start -----> gen_server:start
%% 2 gen_c_server:init  <-----
%% 3                    ------------------------> main()
%% 4                    <------------------------
%% 5                    ------------------------> msg_loop --------> gcs_init() {
%% 6                    <------------------------          <--------   return;
%% 7                    ----->}
%% '''
%% <ol>
%% <li>`gen_c_server:start' calls `gen_server:start', starting the regular OTP
%% server setup.</li>
%% <li>
%%   `gen_server:start' calls `gen_c_server:init'.
%% </li>
%% <li>
%%   Now the fun begins. `gen_c_server:init' determines the parameters to pass
%%   to the C node executable, and starts it via an Erlang Port. It then enters
%%   a loop, waiting for the C node to print a "ready" message to `stdout'.
%% </li>
%% <li>
%%   The C node prints the "ready" message to `stdout' and starts its message
%%   loop. Now messages can be sent via normal Erlang methods to the C node.
%% </li>
%% <li>
%%   `gen_c_server:init' receives the "ready" message via `stdout', and sends
%%   an `init' message to the C node. `gen_c_server:init' now waits for a reply
%%   to come back. The C node's message loop receives the message, and calls
%%   the user-defined `gcs_init' function.
%% </li>
%% <li>
%%   The user-defined `gcs_init' does what it needs to do, fills in a reply
%%   structure, and returns. The message loop wraps that reply and sends it
%%   back to `gen_c_server:init'.
%% </li>
%% <li>
%%   `gen_c_server:init' unwraps the reply, and finally returns the result
%%   of `gcs_init' to `gen_server'.
%% </li>
%% </ol>
%% If everything went fine, we now have a `gen_server' that is running a C
%% node via the `gen_c_server' proxy.
%%
%% @end
%%
%%==============================================================================
-module(gen_c_server).
-behaviour(gen_server).

%%% ---------------------------------------------------------------------------
%%%
%%% Public API
%%%
%%% ---------------------------------------------------------------------------
-export([start/3, start/4,
         start_link/3, start_link/4,
         stop/1,
         call/2, call/3,
         c_call/2, c_call/3,
         cast/2,
         c_cast/2,
         c_handle_info/2,
         c_init/2, c_init/3, c_terminate/2]).


%%% ---------------------------------------------------------------------------
%%%
%%% gen_server callbacks
%%%
%%% ---------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%%% ---------------------------------------------------------------------------
%%%
%%% Behaviour callbacks
%%%
%%% ---------------------------------------------------------------------------
-type server_state() :: {State :: term(), Opaque :: term()}.

-callback c_node() -> Path :: term().

-callback init(Args :: term(), Opaque :: term()) ->
    {ok, ServerState :: server_state()} |
    {ok, ServerState :: server_state(), timeout() | hibernate} |
    {stop, Reason :: term()} | ignore.

-callback terminate(
            Reason :: (normal | shutdown | {shutdown, term()} | term ()),
            ServerState :: server_state()) ->
    term().

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                      ServerState :: server_state()) ->
    {reply, Reply :: term(), NewServerState :: server_state()} |
    {reply, Reply :: term(), NewServerState :: server_state(), timeout() | hibernate} |
    {noreply, NewServerState :: server_state()} |
    {noreply, NewServerState :: server_state(), timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewServerState :: server_state()} |
    {stop, Reason :: term(), NewServerState :: server_state()}.

-callback handle_cast(Request :: term(), ServerState :: server_state()) ->
    {noreply, NewServerState :: server_state()} |
    {noreply, NewServerState :: server_state(), timeout() | hibernate} |
    {stop, Reason :: term(), NewServerState :: server_state()}.

-callback handle_info(Info :: timeout | term(), ServerState :: server_state()) ->
    {noreply, NewServerState :: server_state()} |
    {noreply, NewServerState :: server_state(), timeout() | hibernate} |
    {stop, Reason :: term(), NewServerState :: server_state()}.


%%%----------------------------------------------------------------------------
%%%
%%% Internal state
%%%
%%% The internal state is represented by the `state' record. The
%%% `gen_server' state itself is a pair `{State, InternalState}',
%%% where `State' is the user-defined state.
%%%
%%%----------------------------------------------------------------------------
-record(state, {
          mod, % .......... The Erlang module implementing the behaviour
          port, % ......... The Erlang port used to communicate with the C node
          mbox, % ......... Messages to the C node will be sent here
          buffer, % ....... Buffer for stdout capturing
          tracelevel % .... The desired trace level
}).

state_new() -> #state{
                  mod    = undefined,
                  port   = undefined,
                  mbox   = undefined,
                  buffer = undefined,
                  tracelevel = undefined
}.

state_disconnect({State, InternalState}) ->
    {State, InternalState#state{port = undefined, mbox = undefined}}.
state_clearbuffer(State) -> State#state{buffer = undefined}.

%%%----------------------------------------------------------------------------
%%%
%%% Starting
%%%
%%%----------------------------------------------------------------------------
start(Mod, Args, Options) ->
    TraceLevel = proplists:get_value(tracelevel, Options, 1),
    gen_server:start(?MODULE
                    , [Mod, TraceLevel, Args]
                    , proplists:delete(tracelevel, Options)).

start(Name, Mod, Args, Options) ->
    TraceLevel = proplists:get_value(tracelevel, Options, 1),
    gen_server:start(Name
                    ,?MODULE
                    , [Mod, TraceLevel, Args]
                    , proplists:delete(tracelevel, Options)).

start_link(Mod, Args, Options) ->
    TraceLevel = proplists:get_value(tracelevel, Options, 1),
    gen_server:start_link(?MODULE
                    , [Mod, TraceLevel, Args]
                    , proplists:delete(tracelevel, Options)).

start_link(Name, Mod, Args, Options) ->
    TraceLevel = proplists:get_value(tracelevel, Options,1),
    gen_server:start_link(Name
                    ,?MODULE
                    , [Mod, TraceLevel, Args]
                    , proplists:delete(tracelevel, Options)).

init([Mod, TraceLevel, Args]) ->
    case node_id(Mod) of
        {command_not_found, _} = Reply -> {stop, Reply};
        {_Cmd, NodeName, HostName} ->
            %% Initialize internal state
            MboxAtom = list_to_atom(lists:flatten([NodeName,"@", HostName])),
            Mbox = {c_node, MboxAtom},
            InternalState = (state_new())#state{mod = Mod,
                                                tracelevel = TraceLevel,
                                                mbox = Mbox},
            %% Call Mod:init
            Mod:init(Args, InternalState)
    end.

c_init(Args, InternalState) ->
    c_init(Args, InternalState, spawn_executable).

c_init(Args, InternalState, SpawnType) ->
    process_flag(trap_exit, true),
    #state{mod = Mod, mbox = Mbox, tracelevel = TraceLevel} = InternalState,
    {Exe, NodeName, HostName} = node_id(Mod),
    Argv = [NodeName, HostName, atom_to_list(node()),
            atom_to_list(erlang:get_cookie()),
            integer_to_list(TraceLevel)],
    CommonPortSettings = [stream, {line, 100}, stderr_to_stdout, exit_status],
    {Cmd, PortSettings} =
        case SpawnType of
            spawn -> {string:join([Exe | Argv], " "), CommonPortSettings};
            spawn_executable -> {Exe, [{args, Argv} | CommonPortSettings]}
        end,
    Port = open_port({SpawnType, Cmd}, PortSettings),
    NewInternalState = InternalState#state{port = Port},
    case wait_for_startup(NewInternalState) of
        {stop, Error} -> {stop, Error};
        {ok, State} ->
            Mbox ! {init, self(), Args, undefined, undefined},
            case wait_for_init(state_clearbuffer(State)) of
                {ok, UserState} -> {ok, {UserState, NewInternalState}};
                {ok, UserState, Flag} -> {ok, {UserState, NewInternalState}, Flag};
                Other -> Other
            end
    end.

node_id(Mod) ->
    CNode = Mod:c_node(),
    case os:find_executable(CNode) of
        false ->
            {command_not_found, CNode};
        Cmd ->
            NodeName = bin_to_hex(crypto:hash(md5, Cmd)),
            HostName = string:sub_word(atom_to_list(node()), 2, $@),
            {Cmd, NodeName, HostName}
    end.

bin_to_hex(<<H, T/binary>>) -> io_lib:format("~.16B", [H]) ++ bin_to_hex(T);
bin_to_hex(<<>>) -> [].

-define(C_NODE_READY_MSG,".-. . .- -.. -.--"). % Morse code for "ready"
%
% This stdout-based hack is too hacky, but I could not make it work by
% waiting for the node to come up using net_adm:ping plus waiting. An example
% on how that should work is in Erlang's source lib/stdlib/test/dets_SUITE.erl,
% in the ensure_node/2 function. It does not work here for some obscure reason.
% Until I can figure that out, the stdout hack stays.
%
wait_for_startup(#state{port = Port, buffer = Buffer}= State) ->
    receive
        {Port, {data, {eol, ?C_NODE_READY_MSG}}} ->
            {ok, state_clearbuffer(State)};
        {Port, {exit_status, N}}   -> {stop, {exit_status, N}};
        {Port, {data, Chunk}} ->
            wait_for_startup(State#state{
                               buffer = update_message_buffer(Buffer, Chunk)})
    end.

wait_for_init(#state{port = Port, mbox ={_, Id}, buffer = Buffer}= State) ->
    receive
        {Port, {exit_status, N}}   -> {stop, {exit_status, N}};
        {Port, {data, Chunk}} ->
            wait_for_init(State#state{
                               buffer = update_message_buffer(Buffer, Chunk)});
        {Id, Reply} -> Reply;
        Other -> {stop, {invalid_init_reply, Other}}
    end.

%%%----------------------------------------------------------------------------
%%%
%%% Stopping
%%%
%%% R16's gen_server does not have the stop() function. We go with a
%%% call here. This will be intercepted later on in `handle_call',
%%% which will reply `stop' and trigger the `gen_server' termination
%%% process, which will finally call `terminate' for us.
%%%
%%%----------------------------------------------------------------------------
stop(ServerRef) -> gen_server:call(ServerRef,'$gcs_stop').

terminate(Reason, {_, #state{mod = Mod}} = ServerState) ->
    Mod:terminate(Reason, ServerState).

c_terminate(_Reason, {_State, #state{mbox = undefined}}) ->
    ok;
c_terminate(Reason, {State, #state{mbox = Mbox} = InternalState}) ->
    Mbox ! {terminate, self(), Reason, State, undefined},
    wait_for_exit(InternalState).

wait_for_exit(#state{port = Port, buffer = Buffer} = State) ->
    receive
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, _N}} -> ok;
        {'EXIT', Port, _Reason}   -> ok;
        {Port, {data, Chunk}} ->
            wait_for_exit(State#state{
                               buffer = update_message_buffer(Buffer, Chunk)});
        _Other ->
            wait_for_exit(State)
    end.

%%% ---------------------------------------------------------------------------
%%%
%%% Calls
%%%
%%% Both C and Erlang calls are handled by our own handle_call. The
%%% difference is in the parameters it gets in each case.
%%%
%%% ---------------------------------------------------------------------------

call(ServerRef, Request) ->
    %io:fwrite("gen_c_server:call(~w,~w)", [ServerRef, Request]),
    gen_server:call(ServerRef, {'$gcs_ecall', Request}).

call(ServerRef, Request, Timeout) ->
    %io:fwrite("gen_c_server:call(~w,~w,~w)", [ServerRef, Request, Timeout]),
    gen_server:call(ServerRef, {'$gcs_ecall', Request}, Timeout).

c_call(ServerRef, Request) ->
    gen_server:call(ServerRef, {'$gcs_ccall', Request}).

c_call(ServerRef, Request, Timeout) ->
    %io:fwrite("gen_c_server:c_call(~w,~w,~w)", [ServerRef, Request, Timeout]),
    gen_server:call(ServerRef, {'$gcs_ccall', Request}, Timeout).

%%%
%%% The 'stop' call is generated from our own stop/1. It replies to gen_server
%%% telling it to, well, stop, which will cause a call to terminate, which will
%%% then take care of the C node stopping activities.
%%%
%%% @private
%%%
handle_call('$gcs_stop', _From, State) ->
    {stop, normal, ok, State};
%%%
%%% Call to Erlang callback module
%%%
handle_call({'$gcs_ecall', Request}, From,
            {_, #state{mod = Mod}} = ServerState) ->
    Mod:handle_call(Request, From, ServerState);
%%%
%%% This is a normal call, which is forwarded to the C node. The expected reply
%%% from the C node is
%%%
%%%      {'$gcs_call_reply', From, Reply}
%%%
%%% where 'Reply' is a gen_server-style reply. We have to wait for the reply
%%% here, and block while waiting only for messages we understand.
%%%
handle_call({'$gcs_ccall', Request}, From,
            {State, #state{mbox = Mbox} = InternalState} = ServerState) ->
    %io:fwrite("handle_call(~w,~w,~w)", [Request, From, State]),
    {_, Id} = Mbox,
    Mbox ! {call, self(), Request, State, From},
    receive
        %
        % The C node is gone
        %
        {_Port, {exit_status, N}} when N =/= 0 ->
            {stop, {port_status, N}, ServerState};
        %
        % 'reply'
        %
        {Id,{'$gcs_call_reply', From,{reply, Reply, NewState}}} ->
            {reply, Reply,{NewState, InternalState}};
        {Id,{'$gcs_call_reply', From,{reply, Reply, NewState, hibernate}}} ->
            {reply, Reply, {NewState, InternalState}, hibernate};
        %
        % 'stop'
        %
        {Id, {'$gcs_call_reply', From, {stop, Reason, Reply, NewState}}} ->
            {stop, Reason, Reply, {NewState, InternalState}}
    end;
%%%
%%% What the hell is going on here?
%%%
handle_call(_Request, _From, ServerState) ->
    %io:fwrite("rogue handle_call(~w,~w,~w)", [Request, From, State]),
    {reply, ok, ServerState}.

%%% ---------------------------------------------------------------------------
%%%
%%% Casts
%%%
%%% ---------------------------------------------------------------------------

cast(ServerRef, Request) ->
    gen_server:cast(ServerRef, {'$gcs_ecast', Request}).

c_cast(ServerRef, Request) ->
    gen_server:cast(ServerRef, {'$gcs_ccast', Request}).

%%%
%%% Erlang casts
%%%
handle_cast({'$gcs_ecast', Request},
            {_State, #state{mod = Mod}} = ServerState) ->
    Mod:handle_cast(Request, ServerState);
%%%
%%% C node casts
%%%
handle_cast({'$gcs_ccast', Request},
            {State, #state{mbox = Mbox} = InternalState} = ServerState) ->
    {_, Id} = Mbox,
    Mbox ! {cast, self(), Request, State, undefined},
    receive
        %
        % The C node is gone
        %
        {_Port, {exit_status, N}} when N =/= 0 ->
            {stop, {port_status, N}, ServerState};
        %
        % 'noreply'
        %
        {Id, {'$gcs_cast_reply', {noreply, NewState}}} ->
            {noreply, {NewState, InternalState}};
        {Id, {'$gcs_cast_reply', {noreply, NewState, hibernate}}} ->
            {noreply, {NewState, InternalState}, hibernate};
        %
        % 'stop'
        %
        {Id, {'$gcs_cast_reply', {stop, Reason, NewState}}} ->
            {stop, Reason, {NewState, InternalState}}
    end;
%%%
%%% A cast we don't understand.
%%%
handle_cast(_Request, ServerState) ->
    %io:fwrite("rogue handle_cast(~w,~w)", [_Request, State]),
    {noreply, ServerState}.

%%% ---------------------------------------------------------------------------
%%%
%%% handle_info
%%%
%%% ---------------------------------------------------------------------------
%%%
%%% handle_info for termination messages
%%%
%%% ---------------------------------------------------------------------------
handle_info({Port, {exit_status, 0}}, {_, #state{port = Port}} = ServerState) ->
    error_logger:info_report("C node exiting"),
    {stop, normal, state_disconnect(ServerState)};
handle_info({Port, {exit_status, N}}, {_, #state{port = Port}} = ServerState) ->
    error_logger:error_report("C node exiting"),
    {stop, {port_status, N}, state_disconnect(ServerState)};
handle_info({'EXIT', Port, Reason}, {_, #state{port = Port}} = ServerState) ->
    error_logger:error_report("C node exiting"),
    {stop, {port_exit, Reason}, state_disconnect(ServerState)};
%%% ---------------------------------------------------------------------------
%%%
%%% handle_info for stdout messages from C node
%%%
%%% ---------------------------------------------------------------------------
handle_info({Port, {data, Chunk}},
            {State, #state{port = Port, buffer = Buffer} = InternalState}) ->
    {noreply, {State,
               InternalState#state{buffer = update_message_buffer(Buffer, Chunk)}}};
%%% ---------------------------------------------------------------------------
%%%
%%% Other info: pass it on to the Erlang module callback.
%%%
%%% ---------------------------------------------------------------------------
handle_info(Info, {_, #state{mod = Mod}} = ServerState) ->
    Mod:handle_info(Info, ServerState).

c_handle_info(Info,
              {State, #state{mbox = Mbox} = InternalState} = ServerState) ->
    {_, Id} = Mbox,
    Mbox ! {info, self(), Info, State, undefined},
    receive
        %
        % The C node is gone
        %
        {_Port, {exit_status, N}} when N =/= 0 ->
            {stop, {port_status, N}, ServerState};
        %
        % 'noreply'
        %
        {Id, {'$gcs_info_reply', {noreply, NewState}}} ->
            {noreply, {NewState, InternalState}};
        {Id, {'$gcs_info_reply', {noreply, NewState, hibernate}}} ->
            {noreply, {NewState, InternalState}, hibernate};
        %
        % 'stop'
        %
        {Id, {'$gcs_info_reply', {stop, Reason, NewState}}} ->
            {stop, Reason, {NewState, InternalState}}
    end.


%%==============================================================================
%%
%% Message buffer handling
%%
%%==============================================================================
-define(C_NODE_START_MSG,"... - .- .-. -"). % ...... Morse code for "start"
-define(C_NODE_END_MSG,  ". -. -.."). % ............ Morse code for "end"

%
% Buffer not initialized: waiting for C_NODE_START_MSG
% Anything that arrives while the buffer is not initialized just goes
% directly to stdout.
%
update_message_buffer(undefined, {eol, ?C_NODE_START_MSG}) -> [];
update_message_buffer(undefined, {eol, S}) -> io:fwrite("~s~n", [S]), undefined;
update_message_buffer(undefined, {noeol, S}) -> io:fwrite("~s", [S]), undefined;
%
% End of message marker. Process message as it was intended to.
%
update_message_buffer([],    {eol, ?C_NODE_END_MSG}) -> undefined;
update_message_buffer(Buffer,{eol, ?C_NODE_END_MSG}) ->
    case lists:reverse(Buffer) of
        [ "<INFO>" ++ S | Rest ] ->
            error_logger:info_msg(lists:flatten([S|Rest]));
        [ "<WARN>" ++ S | Rest ] ->
            error_logger:warning_report(lists:flatten([S|Rest]));
        [ "<ERROR>" ++ S | Rest ] ->
            error_logger:error_report(lists:flatten([S|Rest]));
        Other ->
            error_logger:info_report(lists:flatten(Other))
    end,
    undefined;
%
% Otherwise: accumulate message in reverse order.
%
update_message_buffer(Buffer,{eol, S})   -> [$\n, S|Buffer];
update_message_buffer(Buffer,{noeol, S}) -> [S|Buffer].

