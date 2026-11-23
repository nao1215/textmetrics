-module(textmetrics_ffi).

-export([to_nfc/1, array_from_list/1, array_size/1, array_at/2]).

%% Normalise an arbitrary Unicode string to Normalization Form C.
%%
%% Used by `textmetrics/internal/unicode:to_nfc/1` so that distance
%% functions compare canonically-equivalent inputs as equal.
%% Falls back to the original input on the (very rare) cases where
%% `unicode:characters_to_nfc_binary/1` cannot decode the binary —
%% the upstream API can return an `{error, _, _}` tuple for invalid
%% UTF-8, but Gleam `String` values are always valid UTF-8 so this
%% branch is defensive only.
to_nfc(S) when is_binary(S) ->
    case unicode:characters_to_nfc_binary(S) of
        B when is_binary(B) -> B;
        _ -> S
    end.

%% Fixed-size arrays with constant-time reads for the Myers search. The
%% Gleam caller checks the index against `array_size/1` first. A tuple
%% holds at most 16,777,215 elements, so longer lists use the `array`
%% module, whose reads are logarithmic.
array_from_list(List) ->
    try
        {tuple, list_to_tuple(List)}
    catch
        error:Reason when Reason =:= badarg; Reason =:= system_limit ->
            {array, array:from_list(List)}
    end.

array_size({tuple, Tuple}) -> tuple_size(Tuple);
array_size({array, Array}) -> array:size(Array).

array_at({tuple, Tuple}, Index) -> element(Index + 1, Tuple);
array_at({array, Array}, Index) -> array:get(Index, Array).
