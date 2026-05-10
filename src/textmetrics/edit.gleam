//// Edit-script algebraic data type and helpers shared by the diff
//// module.
////
//// An [`EditScript`](#EditScript) is a linear sequence of
//// [`Edit`](#Edit) values describing how to transform one list into
//// another. Replaying the `Equal` and `Delete` steps recovers the
//// original (`old`) list, while replaying `Equal` and `Insert` steps
//// recovers the new list.
////
//// This module operates on plain lists; it does not perform Unicode
//// normalization. Callers comparing strings should split inputs into
//// graphemes via `gleam/string.to_graphemes` before computing a diff.

import gleam/list

/// A single edit step.
///
/// - `Equal(item)` — `item` is present in both inputs at the
///   corresponding position.
/// - `Insert(item)` — `item` appears only in the new input.
/// - `Delete(item)` — `item` appears only in the old input.
pub type Edit(a) {
  Equal(item: a)
  Insert(item: a)
  Delete(item: a)
}

/// A complete edit script — a list of [`Edit`](#Edit) values that
/// describes how to transform one list into another.
pub type EditScript(a) =
  List(Edit(a))

/// A run of consecutive edits sharing the same constructor.
///
/// `runs/1` groups a script's `Equal` / `Insert` / `Delete` steps into
/// `EqualRun` / `InsertRun` / `DeleteRun` so consumers (unified-diff
/// emission, syntax highlighting, …) can iterate by block instead of by
/// item.
pub type Run(a) {
  EqualRun(items: List(a))
  InsertRun(items: List(a))
  DeleteRun(items: List(a))
}

/// Replay the `Equal` and `Delete` steps of `script` to recover the
/// `old` list.
///
/// `recover_old(diff(old, new)) == old` for every input pair, by
/// construction.
pub fn recover_old(script: EditScript(a)) -> List(a) {
  do_recover_old(script, [])
}

fn do_recover_old(script: EditScript(a), acc: List(a)) -> List(a) {
  case script {
    [] -> list.reverse(acc)
    [Equal(item), ..rest] -> do_recover_old(rest, [item, ..acc])
    [Delete(item), ..rest] -> do_recover_old(rest, [item, ..acc])
    [Insert(_), ..rest] -> do_recover_old(rest, acc)
  }
}

/// Replay the `Equal` and `Insert` steps of `script` to recover the
/// `new` list.
///
/// `recover_new(diff(old, new)) == new` for every input pair, by
/// construction.
pub fn recover_new(script: EditScript(a)) -> List(a) {
  do_recover_new(script, [])
}

fn do_recover_new(script: EditScript(a), acc: List(a)) -> List(a) {
  case script {
    [] -> list.reverse(acc)
    [Equal(item), ..rest] -> do_recover_new(rest, [item, ..acc])
    [Insert(item), ..rest] -> do_recover_new(rest, [item, ..acc])
    [Delete(_), ..rest] -> do_recover_new(rest, acc)
  }
}

/// Total number of `Insert` and `Delete` operations in `script`.
///
/// For an optimal Myers diff this equals
/// `distance.levenshtein_list(old, new)` with substitution counted as
/// one insert plus one delete.
pub fn cost(script: EditScript(a)) -> Int {
  do_cost(script, 0)
}

fn do_cost(script: EditScript(a), acc: Int) -> Int {
  case script {
    [] -> acc
    [Equal(_), ..rest] -> do_cost(rest, acc)
    [Insert(_), ..rest] -> do_cost(rest, acc + 1)
    [Delete(_), ..rest] -> do_cost(rest, acc + 1)
  }
}

/// Group consecutive edits that share a constructor into runs.
pub fn runs(script: EditScript(a)) -> List(Run(a)) {
  do_runs(script, [])
}

fn do_runs(script: EditScript(a), acc: List(Run(a))) -> List(Run(a)) {
  case script {
    [] -> list.reverse(acc)
    [Equal(item), ..rest] -> {
      let #(items, remaining) = take_while_equal(rest, [item])
      do_runs(remaining, [EqualRun(items), ..acc])
    }
    [Insert(item), ..rest] -> {
      let #(items, remaining) = take_while_insert(rest, [item])
      do_runs(remaining, [InsertRun(items), ..acc])
    }
    [Delete(item), ..rest] -> {
      let #(items, remaining) = take_while_delete(rest, [item])
      do_runs(remaining, [DeleteRun(items), ..acc])
    }
  }
}

fn take_while_equal(
  script: EditScript(a),
  acc: List(a),
) -> #(List(a), EditScript(a)) {
  case script {
    [Equal(item), ..rest] -> take_while_equal(rest, [item, ..acc])
    _ -> #(list.reverse(acc), script)
  }
}

fn take_while_insert(
  script: EditScript(a),
  acc: List(a),
) -> #(List(a), EditScript(a)) {
  case script {
    [Insert(item), ..rest] -> take_while_insert(rest, [item, ..acc])
    _ -> #(list.reverse(acc), script)
  }
}

fn take_while_delete(
  script: EditScript(a),
  acc: List(a),
) -> #(List(a), EditScript(a)) {
  case script {
    [Delete(item), ..rest] -> take_while_delete(rest, [item, ..acc])
    _ -> #(list.reverse(acc), script)
  }
}
