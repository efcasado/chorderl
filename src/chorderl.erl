%%%-------------------------------------------------------------------
%%% @author Enrique Fernandez Casado <efcasado@gmail.com>
%%% @copyright (C) 2013, Enrique Fernandez Casado
%%% @doc
%%% Erlang implementation of the Chord protocol
%%% @end
%%% Created : 22 Apr 2013 by Enrique Fernandez Casado <efcasado@gmail.com>
%%%-------------------------------------------------------------------
%% TODO: Improve use of gen_tcp
%% TODO: Improve error handling (what if a node disconnects?)
%% TODO: Add timeouts
-module(chorderl).

-behaviour(gen_server).

-include("../include/chorderl.hrl").

%% API
-export([create/0, create/1, join/1, join/2, info/0]).
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Record representing the state of a running Chord node.
-record(state, 
        {
          me                        :: chord_node(),
          next,
          predecessor               :: chord_node(),
          fingers                   :: finger_table(),
          stabilize_interval,
          fixfingers_interval,
          checkpredecessor_interval,
          tcp_timeout
        }).

-define(TCP_SETTINGS, [binary, {active, false}]).
-define(SUPERVISOR, chorderl_sup).


%%%===================================================================
%%% API
%%%===================================================================

%% @doc Create a new Chord ring.
create() ->
    create([]).

create(Opts) ->
    supervisor:start_child(?SUPERVISOR, [[create, Opts]]).

%% @doc Join an existing Chord cluster.
join(BootstrapNode) ->
    join(BootstrapNode, []).

join(BootstrapNode, Opts) ->
    supervisor:start_child(?SUPERVISOR, [[{join, BootstrapNode}, Opts]]).

info() ->
    case gen_server:call(?MODULE, info) of
        {ok, State} ->
            pretty_print(State);
        Other ->
            Other
    end.

%% @doc Function used by the supervisor to start a chorderl process.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Mode, Opts]) ->
    io:format("[~s] Starting chorderl process~n", [?MODULE]),
    {ok, Port} = application:get_env(port),
    io:format("[~s] Port ( ~p )~n", [?MODULE, Port]),
    {ok, NIF} = application:get_env(network_interface),
    io:format("[~s] Network interface ( ~s )~n", [?MODULE, NIF]),
    {ok, TCPTimeout} = application:get_env(tcp_timeout),
    io:format("[~s] TCP timeout ( ~p )~n", [?MODULE, TCPTimeout]),
    Address = get_address(NIF),
    io:format("[~s] Address ( ~s )~n", [?MODULE, Address]),
    {ok, StabilizeInterval} = application:get_env(stabilize_interval),
    io:format("[~s] Stabilize interval ( ~p )~n", [?MODULE, StabilizeInterval]),
    {ok, FixFingersInterval} = application:get_env(fixfingers_interval),
    io:format("[~s] Fix fingers interval ( ~p )~n", [?MODULE, FixFingersInterval]),
    {ok, CheckPredecessorInterval} = application:get_env(checkpredecessor_interval),
    io:format("[~s] Check predecessor interval ( ~p )~n", [?MODULE, CheckPredecessorInterval]),
    case init_tcp(Address, Port) of
        ok ->
            Id = case proplists:get_value(id, Opts) of
                     undefined ->
                         chorderl_utils:sha1(Address ++ integer_to_list(Port));
                     ExtId ->
                         ExtId
                 end,
            io:format("[~s] Id ( ~s )~n", [?MODULE, Id]),
            Me = #chord_node{ id      = Id, 
                              address = Address, 
                              port    = Port
                            },
            State0 = #state{ me                        = Me,
                             next                      = 1,
                             stabilize_interval        = StabilizeInterval,
                             fixfingers_interval       = FixFingersInterval,
                             checkpredecessor_interval = CheckPredecessorInterval,
                             tcp_timeout               = TCPTimeout
                           },
            case init_fingers(Mode, State0) of
                {ok, State = #state{ stabilize_interval        = Int1, 
                                     fixfingers_interval       = Int2,
                                     checkpredecessor_interval = Int3
                                   }} ->
                    erlang:send_after(Int1, self(), stabilize),
                    erlang:send_after(Int2, self(), fix_fingers),
                    erlang:send_after(Int3, self(), check_predecessor),
                    {ok, State};
                {error, StateReason} ->
                    {stop, StateReason}
            end;
        {error, TCPReason} ->
            {stop, TCPReason}
    end.

init_tcp(AddressStr, Port) ->
    {ok, Address} = inet_parse:address(AddressStr),
    case gen_tcp:listen(Port, [binary, {active, true}, {ip, Address}]) of
        {ok, ListenSocket} ->
            MyPid = self(),
            spawn(fun() -> accept_loop(MyPid, ListenSocket) end),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

accept_loop(Parent, ListenSocket) ->
    {ok, AcceptSocket} = gen_tcp:accept(ListenSocket),
    ok = gen_tcp:controlling_process(AcceptSocket, Parent),
    accept_loop(Parent, ListenSocket).

init_fingers(create, State = #state{ me = Me }) ->
    Fingers = update_finger(0, Me, lists:map(fun(_) -> undefined end, lists:seq(1, ?M))),
    {ok, State#state{ fingers = Fingers }};
init_fingers({join, BootstrapAddress}, State = #state{ me = Me }) ->
    {ok, BootstrapNode} = get_bootstrap_node(BootstrapAddress),
    case call(BootstrapNode, {find_successor, Me#chord_node.id}, State#state.tcp_timeout) of
        {error, Reason} ->
            {error, Reason};
        {ok, Succ} ->
            Fingers = 
                update_finger(0, Succ, lists:map(fun(_) -> undefined end, lists:seq(1, ?M))),
            {ok, State#state{ fingers = Fingers }}
    end.

get_bootstrap_node(BootstrapAddress) ->
    [Address, Port] = string:tokens(BootstrapAddress, ":"),
    {ok, AddressStr} = inet_parse:address(Address),
    PortInt = list_to_integer(Port),
    {ok, #chord_node{address = AddressStr, port = PortInt}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({tcp, Socket, Msg}, State) ->
    NewState = 
        case binary_to_term(Msg) of
            ping ->
                gen_tcp:send(Socket, term_to_binary(pong)),
                State;
            predecessor ->
                gen_tcp:send(Socket, term_to_binary({ok, State#state.predecessor})),
                State;
            {find_successor, Id} ->
                Res = find_successor(Id, State),
                gen_tcp:send(Socket, term_to_binary(Res)),
                State;
            {notify, N} ->
                notify(N, State);
            _ ->
                io:format("[~p] Unsupported request received ( ~p )~n", [?MODULE, Msg]),
                State
        end,
    {noreply, NewState};
handle_info(stabilize, State) ->
    NewState = stabilize(State),
    [Succ|_] = NewState#state.fingers,
    erlang:send_after(State#state.stabilize_interval, self(), stabilize),
    {noreply, NewState};
handle_info(fix_fingers, State) ->
    NewState = fix_fingers(State),
    erlang:send_after(State#state.fixfingers_interval, self(), fix_fingers),
    {noreply, NewState};
handle_info(check_predecessor, State) ->
    NewState = check_predecessor(State),
    erlang:send_after(State#state.checkpredecessor_interval, self(), check_predecessor),
    {noreply, NewState};
handle_info({tcp_closed, _Port}, State) ->
    {noreply, State};
handle_info(Msg, State) ->
    io:format("[~p] Unsupported request received ( ~p )~n", [?MODULE, Msg]),
    {noreply, State}.

handle_call(info, _From, State) ->
    {reply, {ok, State}, State}. 


%% ==============================
%% Chord protocol functions
%% ==============================

%% {ok, undefined} | {ok, chord_node()} | {error, term()}
predecessor(Succ, State) ->
    case (State#state.me =:= Succ) of
        %% If node N is its own successor, there is no need to stablish a
        %% TCP connection to retrieve its predecessor.
        true  ->
            {ok, State#state.predecessor};
        false ->
            call(Succ, predecessor, State#state.tcp_timeout)
    end.
            

%% Called periodically. Verifies the successor (S) of the node (N) and tells
%% S about N.
stabilize(State) ->
    [Succ|_] = State#state.fingers,
    NewState = case predecessor(Succ, State) of
                   {error, Reason} ->
                       State;
                   {ok, undefined} ->
                       State;
                   {ok, Pred} ->
                       PredId = chorderl_utils:id(Pred),
                       SuccId = chorderl_utils:id(Succ),
                       MyId = chorderl_utils:id(State#state.me),
                       case chorderl_utils:between(PredId, MyId, SuccId, ?RING_SIZE) of
                           true ->
                               Fs = update_finger(0, Pred, State#state.fingers),
                               State#state{fingers = Fs};
                           false ->
                               State
                       end
               end,
    case (NewState#state.me =:= Succ) of
        true  ->
            ok;
        false ->
            cast(Succ, {notify, NewState#state.me})
    end,
    NewState.

notify(Node, State) ->
    case State#state.predecessor of
        undefined ->
            State#state{predecessor = Node};
        Pred ->
            PredId = list_to_integer(Pred#chord_node.id, 16),
            NodeId = list_to_integer(Node#chord_node.id, 16),
            MyId = list_to_integer((State#state.me)#chord_node.id, 16),
            case chorderl_utils:between(NodeId, PredId, MyId, ?RING_SIZE) of
                true ->
                    State#state{predecessor = Node};
                false ->
                    State
            end
    end.

fix_fingers(State) ->
    MyId = chorderl_utils:id(State#state.me),
    N = chorderl_utils:finger_pos(MyId, State#state.next),
    Next = next(State#state.next),
    NewFingers = case find_successor(N, State) of
                     {ok, NewF} ->
                         update_finger(State#state.next, NewF, State#state.fingers);
                     {error, _Reason} ->
                         State#state.fingers
                 end,
    State#state{next = Next, fingers = NewFingers}.

next(N) when N < ?M ->
    N + 1;
next(N) ->
    1.

check_predecessor(State) ->
    case State#state.predecessor of
        undefined ->
            State;
        Predecessor ->
            case call(Predecessor, ping, State#state.tcp_timeout) of
                pong ->
                    State;
                {error, _Reason} ->
                    State#state{predecessor = undefined}
            end
    end.

find_successor(Id, State) ->
    Me = State#state.me,
    MyId = list_to_integer(Me#chord_node.id, 16),
    [Succ| _] = State#state.fingers,
    case Succ of
        undefined ->
            {ok, Me};
        _ ->
            SuccId = list_to_integer(Succ#chord_node.id, 16),
            DecId = list_to_integer(Id, 16),
            case chorderl_utils:betweenr(DecId, MyId, SuccId, ?RING_SIZE) of
                true ->
                    {ok, Succ};
                false ->
                    case closest_preceding_node(Id, State) of
                        {ok, CPNode} ->
                            call(CPNode, {find_successor, Id}, State#state.tcp_timeout);
                        {ok, preceding_node_not_found} ->
                            {ok, Me}
                    end
            end
    end.

%% Searches the local finger table for the highest predecessor of the
%% specified id.
closest_preceding_node(Id, State) ->
    Me = State#state.me,
    N = list_to_integer(Me#chord_node.id, 16), 
    RFs = lists:reverse(State#state.fingers),
    do_closest_preceding_node(list_to_integer(Id, 16), N, RFs).

do_closest_preceding_node(Id, _N, []) ->
    {ok, preceding_node_not_found};
do_closest_preceding_node(Id, N, [undefined | Fs]) ->
    do_closest_preceding_node(Id, N, Fs);
do_closest_preceding_node(Id, N, [F | Fs]) ->
    FDec = chorderl_utils:id(F),
    case chorderl_utils:between(FDec, N, Id, ?RING_SIZE) of
        true ->
            {ok, F};
        false ->
            do_closest_preceding_node(Id, N, Fs)
    end.
    

%%%===================================================================
%%% Internal functions
%%%===================================================================

update_finger(0, NewF, [_F | Fs]) ->
    [NewF | Fs];
update_finger(Nth, NewF, FingerTable) when Nth =:= length(FingerTable) ->
    lists:append(FingerTable, [NewF]);
update_finger(Nth, NewF, FingerTable) ->
    {Pre, [_ | Post]} = lists:split(Nth, FingerTable), 
    lists:append(Pre, [NewF | Post]).


call(Node, Request, Timeout) when is_record(Node, chord_node) ->
    case send(Node, Request) of
        {ok, Socket} ->
            case gen_tcp:recv(Socket, 0, Timeout) of
                {ok, Res} ->
                    gen_tcp:close(Socket),
                    binary_to_term(Res);
                {error, Reason} ->
                    gen_tcp:close(Socket),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

cast(Node, Msg) when is_record(Node, chord_node) ->
    case send(Node, Msg) of
        {ok, Socket} ->
            gen_tcp:close(Socket);
        {error, Reason} ->
            {error, Reason}
    end.

send(#chord_node{address = Address, port = Port}, Msg) ->
    case gen_tcp:connect(Address, Port, ?TCP_SETTINGS) of
        {ok, Socket} ->
            case gen_tcp:send(Socket, term_to_binary(Msg)) of
                ok ->
                    {ok, Socket};
                {error, SendError} ->
                    gen_tcp:close(Socket),
                    {error, SendError}
            end;
        {error, ConnectError} ->
            {error, ConnectError}
    end.

%% @doc Returns the IP address associated to the specified network interface.
get_address(NIF) ->
    {ok, [{addr, Addr}]} = inet:ifget(NIF, [addr]),
    inet_parse:ntoa(Addr).


%% ====
%% Print functions
%% ====

pretty_print(#state{ me = Me, predecessor = Predecessor, fingers = Fingers }) ->
    io:format("Node: ~s~n", [to_str(Me)]),
    io:format("Predecessor: ~s~n", [to_str(Predecessor)]),
    [Succ| Fs] = Fingers,
    print_fingers(Succ, 0, 0, lists:zip(lists:seq(1, length(Fs)), Fs)).

print_fingers(Prev, From, To, []) ->
    io:format("Finger[~s]: ~s~n", [pos2str(From, To), to_str(Prev)]);    
print_fingers(Prev, From, To, [{Nth, F}| Fs]) ->
    case F =:= Prev of
        true ->
            print_fingers(Prev, From, Nth, Fs);
        false ->
            io:format("Finger[~s]: ~s~n", [pos2str(From, To), to_str(Prev)]),
            print_fingers(F, Nth, Nth, Fs)
    end.

pos2str(From, To) when From =:= To ->
    integer_to_list(From);
pos2str(From, To) ->
    io_lib:format("~p..~p", [From, To]).
    
to_str(#chord_node{id = Id, address = Address, port = Port}) ->    
    io_lib:format("~s ( ~s:~p )", [Id, Address, Port]);
to_str(undefined) ->
    "undefined".
    
    

%% ========================================
%% unused gen_server callbacks
%% ========================================

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
    
