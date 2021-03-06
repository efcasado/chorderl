-module(chorderl_utils).

-include("../include/chorderl.hrl").

-export([
         id/1,
         finger_pos/2,
         betweenl/4, 
         betweenr/4, 
         between/4, 
         sha1/1
        ]).


%% =====================================================
%% Exported functions
%% =====================================================

%% Utility functions to calculate whether a given value
%% belongs to a circular range, or not. The circular 
%% range is expected to be [0, RingSize).

betweenl(Value, LBound, _RBound, _RingSize) when Value =:= LBound ->
    true;
betweenl(Value, LBound, RBound, RingSize) ->
    between(Value, LBound, RBound, RingSize).

betweenr(Value, _LBound, RBound, _RingSize) when Value =:= RBound ->
    true;
betweenr(Value, LBound, RBound, RingSize) ->
    between(Value, LBound, RBound, RingSize).

between(_Value, LBound, RBound, _RingSize) when LBound =:= RBound ->
    true;
between(Value, LBound, RBound, RingSize) when RBound < LBound ->
    NewValue = case Value < LBound of
                   true ->
                       RingSize - (LBound - Value) - 1;
                   false ->
                       Value - LBound
               end,
    between(NewValue, 0, RingSize - (LBound - RBound) - 1, RingSize);
between(Value, LBound, RBound, RingSize) ->
    LBound < Value andalso Value < RBound.

%%-type sha1(iolist() | binary()) -> iolist(). 
sha1(Data) -> 
    to_hexstring(crypto:sha(Data)).


finger_pos(Id, Nth) ->
    integer_to_list((Id + pow(Nth - 1)) rem pow(?M), 16).

id(Node) ->
    list_to_integer(Node#chord_node.id, 16).


%% =====================================================
%% Internal functions
%% =====================================================

to_hexstring(<<X:160/big-unsigned-integer>>) ->
    lists:flatten(io_lib:format("~40.16.0b", [X])). 

pow(N) ->
    erlang:trunc(math:pow(2, N)).
  
