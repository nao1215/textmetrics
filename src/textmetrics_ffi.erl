-module(textmetrics_ffi).

-export([to_nfc/1]).

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
