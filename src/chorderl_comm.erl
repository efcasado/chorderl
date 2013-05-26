-module(chorderl_comm).

-include("../include/chorderl.hrl").

-export([call/2, call/3, cast/2]).

-define(TCP_SETTINGS, [binary, {active, false}]).


call(Node, Request) when is_record(Node, chord_node) ->
    call(Node, Request, infinity).

call(Node, Request, Timeout) when is_record(Node, chord_node) ->
    case send(Node, Request) of
        {ok, Socket} ->
            case gen_tcp:recv(Socket, 0, Timeout) of
                {ok, Res} ->
                    gen_tcp:close(Socket),
                    binary_to_term(Res);
                {error, _Reason} ->
                    gen_tcp:close(Socket),
                    {error, commerror}
            end;
        {error, _Reason} ->
            {error, commerror}
    end.

cast(Node, Msg) when is_record(Node, chord_node) ->
    case send(Node, Msg) of
        {ok, Socket} ->
            gen_tcp:close(Socket);
        {error, _Reason} ->
            {error, commerror}
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
