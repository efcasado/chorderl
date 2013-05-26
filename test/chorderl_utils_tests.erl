-module(chorderl_utils_tests).

-include_lib("eunit/include/eunit.hrl").


between_test_() ->
    {"Between test",
     [
      {"0  (0, 0)", fun() -> ?assertNot(chorderl_utils:between(0, 0, 0, 0)) end},
      {"1  (1, 1)", fun() -> ?assertNot(chorderl_utils:between(1, 1, 1, 1)) end},
      {"3  (3, 3)", fun() -> ?assertNot(chorderl_utils:between(3, 3, 3, 3)) end},
      {"0  (0, 0)", fun() -> ?assertNot(chorderl_utils:between(0, 0, 0, 3)) end},
      {"1  (0, 1)", fun() -> ?assertNot(chorderl_utils:between(1, 0, 1, 3)) end},
      {"1  (0, 2)", fun() ->    ?assert(chorderl_utils:between(1, 0, 2, 3)) end},
      {"3  (0, 3)", fun() -> ?assertNot(chorderl_utils:between(3, 0, 3, 3)) end},
      {"0  [0, 0)", fun() ->    ?assert(chorderl_utils:betweenl(0, 0, 0, 3)) end},
      {"1  [0, 1)", fun() -> ?assertNot(chorderl_utils:betweenl(1, 0, 1, 3)) end},
      {"1  [0, 2)", fun() ->    ?assert(chorderl_utils:betweenl(1, 0, 2, 3)) end},
      {"3  [0, 3)", fun() -> ?assertNot(chorderl_utils:betweenl(3, 0, 3, 3)) end},
      {"0  (0, 0]", fun() ->    ?assert(chorderl_utils:betweenr(0, 0, 0, 3)) end},
      {"1  (0, 1]", fun() ->    ?assert(chorderl_utils:betweenr(1, 0, 1, 3)) end},
      {"1  (0, 2]", fun() ->    ?assert(chorderl_utils:betweenr(1, 0, 2, 3)) end},
      {"3  (0, 3]", fun() ->    ?assert(chorderl_utils:betweenr(3, 0, 3, 3)) end},
      {"3  (3, 0)", fun() -> ?assertNot(chorderl_utils:between(3, 3, 0, 3)) end},
      {"3  [3, 0)", fun() ->    ?assert(chorderl_utils:betweenl(3, 3, 0, 3)) end},
      {"3  (3, 0]", fun() -> ?assertNot(chorderl_utils:betweenr(3, 3, 0, 3)) end},
      {"2  (3, 1)", fun() -> ?assertNot(chorderl_utils:between(2, 3, 1, 3)) end},
      {"2  [3, 1)", fun() -> ?assertNot(chorderl_utils:betweenl(2, 3, 1, 3)) end},
      {"2  (3, 1]", fun() -> ?assertNot(chorderl_utils:betweenr(2, 3, 1, 3)) end}
     ]
    }.

sha1_test_() ->
    {"SHA-1 test",
     [
      {"SHA1('127.0.0.1')", fun() -> ?assertEqual(chorderl_utils:sha1("127.0.0.1"), 
                                                  "4b84b15bff6ee5796152495a230e45e3d7e947d9") 
                            end}
     ]
    }.


