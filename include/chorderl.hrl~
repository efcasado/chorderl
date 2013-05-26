%% Size of the Chord ring (in bits)
-define(M, 160).

%% Size of the Chord ring
-define(RING_SIZE, erlang:trunc(math:pow(2, ?M))).

%% Chord node representation
-record(chord_node, 
        {
          id,        %% Id in the Chord ring space.
          address,   %% Address used to contact the node.
          port
        }).

-type chord_node() :: #chord_node{}.

%% Finger table entry representation
-record(finger,
        {
          pos,
          node :: chord_node()
        }).

-type finger() :: #finger{}.
-type finger_table() :: list(finger()).
        
