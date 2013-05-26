-module(chorderl_comm).

-export([call/2, cast/2]).

call(To, Message) ->
    case send(To, Message) of
        {ok, Socket} ->
            gen_tcp:recv(Socket, 0);
        Other ->
            Other
    end.

cast(To, Message) ->
    send(To, Message).

send(To, Message) ->
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, 8080, []),
    gen_tcp:send(Socket, Message),
    {ok, Socket}.
