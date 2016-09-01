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
%% @doc A `gen_server' for C nodes.
%%
%% <a href="http://erlang.org/doc/tutorial/cnode.html">C nodes</a>
%% are a way of implementing native binaries, written in C, that behave
%% like Erlang nodes, capable of sending and receiving messages from Erlang
%% processes. Amongst the ways of interfacing Erlang with C, C nodes are the
%% most robust: since the nodes are independent OS processes, crashes do not
%% affect the Erlang VM. Compare this to a NIF, for example, where a problem in
%% the C code may cause the entire Erlang VM to crash.
%%
%% Making C nodes work with Erlang, however, is not a simple task. Your
%% executable is started by hand, and has to set up communications with an
%% existing Erlang process. Since the executable does not know where to connect
%% to in advance, the necessary parameters have to be given to it in the
%% command line  when the C node is started.
%% Once all of that is done, the C node
%% enters a message loop, waiting for messages and replying to them. If the
%% computations it is performing take too long, the calling Erlang process may
%% infer that the C node is dead, and cut communications with it. This is
%% because Erlang will be sending `TICK' messages to the C node to keep the
%% connection alive. The only way around this is to make the C node have
%% separate threads to deal with user-generated messages and system-generated
%% messages. The list does go on.
%%
%% This module, and its accompanying library, `libgen_c_server.a', hide this
%% complexity and require the C node implementer to define only the equivalent
%% `gen_server' callbacks in C. Within these callbacks, the developer uses
%% the `ei' library to manipulate Erlang terms.
%%
%% == Writing a C Node ==
%%
%% A C node is written by implementing the necessary callbacks, and linking
%% the executable against `libgen_c_server.a', which defines `main()' for you.
%% When implementing callbacks, the rule of thumb is this: for each callback
%% you would implement in an Erlang `gen_server' callback module, implement a
%% `gcs_'<em>name</em> function in C instead. This function takes in the same
%% arguments as the Erlang callback, plus a last `ei_x_buff*' argument where the
%% function should build its reply (when a reply is needed). The other
%% arguments are `const char*' pointing to `ei' buffers containing the
%% arguments themselves.
%%
%% A full C node skeleton thus looks like this:
%% ```
%% #include "gen_c_server.h"
%%
%% void gcs_init(const char *args_buff, ei_x_buff *reply) {
%%   /* IMPLEMENT ME */
%% }
%%
%% void gcs_handle_call(const char *request_buff,
%%                      const char *from_buff,
%%                      const char *state_buff,
%%                      ei_x_buff *reply) {
%%   /* IMPLEMENT ME */
%% }
%%
%% void gcs_handle_cast(const char *request_buff,
%%                      const char *state_buff,
%%                      ei_x_buff *reply) {
%%   /* IMPLEMENT ME */
%% }
%%
%% void gcs_handle_info(const char *info_buff,
%%                      const char *state_buff,
%%                      ei_x_buff *reply) {
%%   /* IMPLEMENT ME */
%% }
%%
%% void gcs_terminate(const char *reason_buff, const char *state_buff) {
%%   /* IMPLEMENT ME */
%% }
%% '''
%% Let's see how this looks like in a C node that simply counts the number
%% of calls made to each function. (This C node is included in the source
%% distribution of `gen_c_server', as one of the tests.) In this C node,
%% We make use of an utility `gcs_decode' function which is provided by the
%% `gen_c_server' library, that allows us to decode `ei' buffers in a
%% `sscanf'-like manner. Consult the header file for more details.
%% ```
%% #include "gen_c_server.h"
%%
%% /*
%%  * Utility function that encodes a state tuple based on the arguments.
%%  * The state is a 3-tuple, { num_calls, num_casts, num_infos }
%%  */
%% static void encode_state(
%%         ei_x_buff *reply,
%%         long ncalls,
%%         long ncasts,
%%         long ninfos)
%% {
%%     ei_x_encode_tuple_header(reply,3);
%%     ei_x_encode_long(reply,ncalls);
%%     ei_x_encode_long(reply,ncasts);
%%     ei_x_encode_long(reply,ninfos);
%% }
%%
%% /*
%%  * Initialize the C node, replying with a zeroed-out state.
%%  */
%% void gcs_init(const char* args_buff, ei_x_buff *reply)
%% {
%%     /* Reply: {ok,{0,0,0}} */
%%     ei_x_encode_tuple_header(reply,2);
%%     ei_x_encode_atom(reply,"ok");
%%     encode_state(reply,0,0,0);
%% }
%%
%% /*
%%  * When called, increment the number of calls, and reply with the new state.
%%  */
%% void gcs_handle_call(
%%         const char *request_buff,
%%         const char *from_buff,
%%         const char *state_buff,
%%         ei_x_buff  *reply)
%% {
%%     long ncalls, ncasts, ninfos;
%%     gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);
%%
%%     /* Reply: {reply,Reply=NewState,NewState={ncalls+1,ncasts,ninfos}} */
%%     ei_x_encode_tuple_header(reply,3);
%%     ei_x_encode_atom(reply,"reply");
%%     encode_state(reply,ncalls+1,ncasts,ninfos);
%%     encode_state(reply,ncalls+1,ncasts,ninfos);
%% }
%%
%% /*
%%  * When casted, increment the number of casts, and reply with the new state.
%%  */
%% void gcs_handle_cast(
%%         const char *request_buff,
%%         const char *state_buff,
%%         ei_x_buff  *reply)
%% {
%%     long ncalls, ncasts, ninfos;
%%     gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);
%%
%%     /* Reply: {noreply,NewState={ncalls,ncasts+1,ninfos}} */
%%     ei_x_encode_tuple_header(reply,2);
%%     ei_x_encode_atom(reply,"noreply");
%%     encode_state(reply,ncalls,ncasts+1,ninfos);
%% }
%%
%% /*
%%  * When info-ed, increment the number of infos, and reply with the new state.
%%  */
%% void gcs_handle_info(
%%         const char *info_buff,
%%         const char *state_buff,
%%         ei_x_buff  *reply)
%% {
%%     long ncalls, ncasts, ninfos;
%%     gcs_decode(state_buff,(int*)0,"{lll}",3,&ncalls,&ncasts,&ninfos);
%%
%%     /* Reply: {noreply,NewState={ncalls,ncasts,ninfos+1}} */
%%     ei_x_encode_tuple_header(reply,2);
%%     ei_x_encode_atom(reply,"noreply");
%%     encode_state(reply,ncalls,ncasts,ninfos+1);
%% }
%%
%% /*
%%  * We don't need to clean anything up when terminating.
%%  */
%% void gcs_terminate(const char *reason_buff, const char *state_buff) { }
%% '''
%%
%% Once you compile (with the appropriate flags so the compiler finds
%% `gen_c_server.h' and `ei.h') and link (with the appropriate flags to the
%% linker links in `libgen_c_server', `erl_interface', and `ei' libraries) this
%% node, you can use it from Erlang as follows:
%% ```
%% {ok,Pid} = gen_c_server:start("/path/to/my/c/node/executable",[],[]),
%% {1,0,0} = gen_c_server:call(Pid,"Any message"),
%% ok = gen_c_server:cast(Pid,"Any old message"),
%% {2,1,0} = gen_c_server:call(Pid,"Any message"),
%% Pid ! "Any message, really",
%% {3,1,1} = gen_c_server:call(Pid,[]),
%% gen_c_server:stop(Pid).
%% '''
%% Note that the Erlang shell has to have a registered name, which means
%% you have to start it with either the `-name' or `-sname' options passed in.
%% This is because the C node needs a registered Erlang node to connect to.
%%
%% == Limitations ==
%%
%% Currently, not all replies from the callback functions are accepted.
%% In particular,
%%
%% <ul>
%% <li> `gcs_handle_call' can only reply `{reply,Reply,NewState}',
%%      `{reply,Reply,NewState,hibernate}' or `{stop,Reason,Reply,NewState}'.
%% </li>
%% <li> `gcs_handle_cast' can only reply `{noreply,NewState}',
%%      `{noreply,NewState,hibernate}' or `{stop,Reason,NewState}'.
%% </li>
%% <li> `gcs_handle_info' can only reply `{noreply,NewState}',
%%      `{noreply,NewState,hibernate}' or `{stop,Reason,NewState}'.
%% </li>
%% </ul>
%%
%% @author Cesar Crusius
%% @copyright 2016 Cesar Crusius
%%
%% @end
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
%% 7                    ----->                                       }
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

%%==============================================================================
%%
%% Public API
%%
%%==============================================================================
-export([start/3,start_link/3,call/2,call/3,cast/2,stop/1]).

%%==============================================================================
%%
%% gen_server callbacks
%%
%%==============================================================================
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,terminate/2]).

%%==============================================================================
%%
%% Internal state
%%
%%==============================================================================
-record(state, {
          port, % ......... The Erlang port used to communicate with the C node
          mbox, % ......... Messages to the C node will be sent here
          buffer, % ....... Buffer for stdout capturing
          c_node_state % .. The C node's own state
         }).

state_new() -> #state{
                  port   = undefined,
                  mbox   = undefined,
                  buffer = undefined,
                  c_node_state = undefined
                 }.

state_disconnect(State) -> State#state{ port=undefined, mbox=undefined }.
state_clearbuffer(State) -> State#state{ buffer=undefined }.

%%==============================================================================
%%
%% Starting
%%
%% Delegates to gen_server:start with the proper arguments, which will call
%% init/1 below.
%%
%%==============================================================================
%%
%% @doc Create a stand-alone C node server process.
%% A stand-alone server process is one which is not a part of a supervision
%% tree, and thus has no supervisor.
%%
%% See {@link start_link/3}
%% for a description of arguments and return values.
%%
%% @end
%%
%%==============================================================================
start(CNode,Args,Options) ->
    TraceLevel = proplists:get_value(tracelevel,Options,1),
    gen_server:start(?MODULE
                    ,[CNode,TraceLevel,Args]
                    ,proplists:delete(tracelevel,Options)).
%%==============================================================================
%%
%% @doc Create a stand-alone C node server process as a part of a supervision
%% tree. The function should be called, directly or indirectly, by the
%% supervisor. It will, among other things, ensure that the gen_server is
%% linked to the supervisor.
%%
%% There are only two differences between this function and
%% `gen_server:start_link/3':
%%
%% <ul>
%% <li>
%%   The first argument, `CNode', is a string containing the name of the C node
%%   executable (instead of `gen_server''s `Module' argument). If it is not a
%%   fully qualified path, the executable should be in some directory in
%%   `$PATH'.
%% </li>
%% <li>
%%   The `init' function that is usually called by `gen_server:start_link'
%%   should be a C function `gcs_init' implemented in the C node (see
%%   {@section Writing a C node}, above, for details).
%% </li>
%% </ul>
%%
%% See <a href="http://erlang.org/doc/man/gen_server.html#start_link-3">
%% `gen_server:start_link/3'</a> for a complete description of other arguments
%% and return values.
%%
%% @end
%%
%%==============================================================================
start_link(CNode,Args,Options) ->
    TraceLevel = proplists:get_value(tracelevel,Options,1),
    gen_server:start_link(?MODULE
                    ,[CNode,TraceLevel,Args]
                    ,proplists:delete(tracelevel,Options)).

%%==============================================================================
%%
%% init
%%
%%==============================================================================
%%
%% @private
%%
init([CNode,TraceLevel,Args]) ->
    process_flag(trap_exit, true),
    case os:find_executable(CNode) of
        false -> {stop, {command_not_found,CNode}};
        Cmd ->
            % We're not given a node ID, so we come up with one. The only
            % requirement we have is that it has to be short enough, and has to
            % uniquely identify CNode.
            NodeName = bin_to_hex(crypto:hash(md5,Cmd)),
            HostName = string:sub_word(atom_to_list(node()), 2, $@),
            MboxAtom = list_to_atom(lists:flatten([NodeName,"@",HostName])),
            Mbox     = {c_node,MboxAtom},
            Port = open_port( {spawn_executable, Cmd}
                            , [ {args, [ NodeName, HostName, atom_to_list(node())
                                       , atom_to_list(erlang:get_cookie())
                                       , integer_to_list(TraceLevel)
                                       ]}
                              , stream, {line,100}
                              , stderr_to_stdout
                              , exit_status
                              ]),
            case wait_for_startup((state_new())#state{port=Port, mbox=Mbox}) of
                {stop, Error} -> {stop, Error};
                {ok, State} ->
                    Mbox ! {init, self(), Args, undefined, undefined},
                    case wait_for_init(state_clearbuffer(State)) of
                        {ok, CNodeState} ->
                            {ok,State#state{c_node_state=CNodeState}};
                        {ok, CNodeState, X} ->
                            {ok,State#state{c_node_state=CNodeState},X};
                        Other -> Other
                    end
            end
    end.

bin_to_hex(<<H,T/binary>>) -> io_lib:format("~.16B",[H]) ++ bin_to_hex(T);
bin_to_hex(<<>>) -> [].

-define(C_NODE_READY_MSG,".-. . .- -.. -.--"). % Morse code for "ready"
%
% This stdout-based hack is too hacky, but I could not make it work by
% waiting for the node to come up using net_adm:ping plus waiting. An example
% on how that should work is in Erlang's source lib/stdlib/test/dets_SUITE.erl,
% in the ensure_node/2 function. It does not work here for some obscure reason.
% Until I can figure that out, the stdout hack stays.
%
wait_for_startup(#state{port=Port,buffer=Buffer}=State) ->
    receive
        {Port, {data, {eol, ?C_NODE_READY_MSG}}} ->
            {ok, state_clearbuffer(State)};
        {Port, {exit_status, N}}   -> {stop, {exit_status, N}};
        {Port, {data, Chunk}} ->
            wait_for_startup(State#state{
                               buffer=update_message_buffer(Buffer,Chunk)})
    end.

wait_for_init(#state{port=Port,mbox={_,Id},buffer=Buffer}=State) ->
    receive
        {Port, {exit_status, N}}   -> {stop, {exit_status, N}};
        {Port, {data, Chunk}} ->
            wait_for_init(State#state{
                               buffer=update_message_buffer(Buffer,Chunk)});
        {Id,Reply} -> Reply;
        Other -> {stop, {invalid_init_reply, Other}}
    end.

%%==============================================================================
%%
%% stopping
%%
%% R16's gen_server does not have the stop() function. We go with a call here.
%%
%%==============================================================================
stop(ServerRef) -> gen_server:call(ServerRef,stop).

%%==============================================================================
%%
%% terminate
%%
%%==============================================================================
%%
%% @private
%%
terminate(_Reason, #state{mbox=undefined}=_State) -> ok;
terminate(Reason, #state{mbox=Mbox,c_node_state=CNodeState} = State) ->
    Mbox ! {terminate, self(), Reason, CNodeState, undefined},
    wait_for_exit(state_clearbuffer(State)).

wait_for_exit(#state{port=Port,buffer=Buffer} = State) ->
    receive
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, _N}} -> ok;
        {'EXIT', Port, _Reason}   -> ok;
        {Port, {data, Chunk}} ->
            wait_for_exit(State#state{
                               buffer=update_message_buffer(Buffer,Chunk)});
        _Other ->
            wait_for_exit(State)
    end.


%%==============================================================================
%%
%% calls
%%
%%==============================================================================
%% @equiv call(ServerRef, Request, 5000)
%%
call(ServerRef, Request) ->
    %io:fwrite("gen_c_server:call(~w,~w)",[ServerRef,Request]),
    gen_server:call(ServerRef,Request).
%%
%% @doc Make a synchronous call.
%%
%% The only difference between this function and `gen_server:call/3' is that
%% the callback function should be implemented by a `gcs_handle_call' function
%% in the C node see {@section Writing a C node}, above, for details).
%%
%% See <a href="http://erlang.org/doc/man/gen_server.html#call-3">
%% `gen_server:call/3'</a> for a complete description of arguments
%% and return values.
%% @end
%%==============================================================================
call(ServerRef, Request, Timeout) ->
    %io:fwrite("gen_c_server:call(~w,~w,~w)",[ServerRef,Request,Timeout]),
    gen_server:call(ServerRef,Request,Timeout).

%%
%% The 'stop' call is generated from our own stop/1. It replies to gen_server
%% telling it to, well, stop, which will cause a call to terminate, which will
%% then take care of the C node stopping activities.
%%
%% @private
%%
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
%%
%% This is a normal call, which is forwarded to the C node. The expected reply
%% from the C node is
%%
%%      {'$gcs_call_reply',From,Reply}
%%
%% where 'Reply' is a gen_server-style reply. We have to wait for the reply
%% here, and block while waiting only for messages we understand.
%%
handle_call(Request, From, #state{mbox=Mbox, c_node_state=CNodeState} = State) ->
    %io:fwrite("handle_call(~w,~w,~w)",[Request,From,State]),
    {_,Id} = Mbox,
    Mbox ! {call, self(), Request, CNodeState, From},
    receive
        %
        % The C node is gone
        %
        {_Port, {exit_status, N}} when N =/= 0 ->
            {stop, {port_status, N}, State};
        %
        % 'reply'
        %
        {Id,{'$gcs_call_reply',From,{reply,Reply,NewCNodeState}}} ->
            {reply,Reply,State#state{c_node_state=NewCNodeState}};
        {Id,{'$gcs_call_reply',From,{reply,Reply,NewCNodeState,hibernate}}} ->
            {reply,Reply,State#state{c_node_state=NewCNodeState},hibernate};
        %
        % 'stop'
        %
        {Id,{'$gcs_call_reply',From,{stop,Reason,Reply,NewCNodeState}}} ->
            {stop,Reason,Reply,State#state{c_node_state=NewCNodeState}}
    end;
%%
%% What the hell is going on here?
%%
handle_call(_Request, _From, State) ->
    %io:fwrite("rogue handle_call(~w,~w,~w)",[Request,From,State]),
    {reply,ok,State}.

%%==============================================================================
%%
%% casts
%%
%%==============================================================================
%%
%% @doc Make an asynchronous call.
%%
%% The only difference between this function and `gen_server:cast/2' is that
%% the callback function should be implemented by a `gcs_handle_cast' function
%% in the C node see {@section Writing a C node}, above, for details).
%%
%% See <a href="http://erlang.org/doc/man/gen_server.html#cast-2">
%% `gen_server:cast/2'</a> for a complete description of arguments
%% and return values.
%% @end
cast(ServerRef, Request) ->
    gen_server:cast(ServerRef, Request).
%%
%% @private
%%
handle_cast(Request, #state{mbox=Mbox, c_node_state=CNodeState} = State) ->
    {_,Id} = Mbox,
    Mbox ! {cast, self(), Request, CNodeState, undefined},
    receive
        %
        % The C node is gone
        %
        {_Port, {exit_status, N}} when N =/= 0 ->
            {stop, {port_status, N}, State};
        %
        % 'noreply'
        %
        {Id,{'$gcs_cast_reply',{noreply,NewCNodeState}}} ->
            {noreply,State#state{c_node_state=NewCNodeState}};
        {Id,{'$gcs_cast_reply',{noreply,NewCNodeState,hibernate}}} ->
            {noreply,State#state{c_node_state=NewCNodeState},hibernate};
        %
        % 'stop'
        %
        {Id,{'$gcs_cast_reply',{stop,Reason,NewCNodeState}}} ->
            {stop,Reason,State#state{c_node_state=NewCNodeState}}
    end;
%%
%% What the hell is going on here?
%%
handle_cast(_Request, State) ->
    %io:fwrite("rogue handle_cast(~w,~w)",[_Request,State]),
    {noreply,State}.



%%==============================================================================
%%
%% handle_info
%%
%%==============================================================================
%%
%% handle_info for termination messages
%%
%%==============================================================================
%%
%% @private
%%
handle_info({Port, {exit_status, 0}}, #state{port=Port} = State) ->
    error_logger:info_report("C node exiting"),
    {stop, normal, state_disconnect(State)};
handle_info({Port, {exit_status, N}}, #state{port=Port} = State) ->
    error_logger:error_report("C node exiting"),
    {stop, {port_status, N}, state_disconnect(State)};
handle_info({'EXIT', Port, Reason}, #state{port=Port} = State) ->
    error_logger:error_report("C node exiting"),
    {stop, {port_exit, Reason}, state_disconnect(State)};
%%==============================================================================
%%
%% handle_info for stdout messages from C node
%%
%%==============================================================================
handle_info({Port, {data, Chunk}}, #state{port=Port,buffer=Buffer} = State) ->
    {noreply, State#state{buffer=update_message_buffer(Buffer,Chunk)}};
%%==============================================================================
%%
%% Other info: pass it on to the C node
%%
%%==============================================================================
handle_info(Info, #state{mbox=Mbox, c_node_state=CNodeState} = State) ->
    {_,Id} = Mbox,
    Mbox ! {info, self(), Info, CNodeState, undefined},
    receive
        %
        % The C node is gone
        %
        {_Port, {exit_status, N}} when N =/= 0 ->
            {stop, {port_status, N}, State};
        %
        % 'noreply'
        %
        {Id,{'$gcs_info_reply',{noreply,NewCNodeState}}} ->
            {noreply,State#state{c_node_state=NewCNodeState}};
        {Id,{'$gcs_info_reply',{noreply,NewCNodeState,hibernate}}} ->
            {noreply,State#state{c_node_state=NewCNodeState},hibernate};
        %
        % 'stop'
        %
        {Id,{'$gcs_info_reply',{stop,Reason,NewCNodeState}}} ->
            {stop,Reason,State#state{c_node_state=NewCNodeState}}
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
update_message_buffer(undefined, {eol, S}) -> io:fwrite("~s~n",[S]), undefined;
update_message_buffer(undefined, {noeol, S}) -> io:fwrite("~s",[S]), undefined;
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
update_message_buffer(Buffer,{eol, S})   -> [$\n,S|Buffer];
update_message_buffer(Buffer,{noeol, S}) -> [S|Buffer].

