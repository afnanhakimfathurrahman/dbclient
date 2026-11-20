---
name: validate-changes
description: Validate every code change in this repo the way CI does (flutter analyze + flutter test), before calling work done or opening a PR. Use after any edit to app/, before committing, and whenever CI or a pull request fails.
---

# Validate changes (CI parity)

CI (`.github/workflows/ci.yml`) runs, in `app/`:

1. `flutter pub get`
2. `flutter analyze` — **fails on any issue, including `info` lints**
3. `flutter test`

A change is not done until all three pass.

## What is NOT an error

`N packages have newer versions incompatible with dependency constraints.
Try 'flutter pub outdated'` is informational output of `flutter pub get`.
Never "fix" it by bumping dependencies; look at the step that actually failed.

## 1. Before committing: self-review the diff for analyzer lints

`flutter analyze` uses `package:flutter_lints` (see `app/analysis_options.yaml`)
with Dart ^3.13. Check every changed Dart file for these, which have failed CI
before:

- **use_null_aware_elements**: in list/set/map literals write `?value` /
  `'key': ?value`, never `if (x case final v?) v` or `if (x != null) x`.
- Unused imports, unused locals/fields, `prefer_const_constructors`,
  `use_key_in_widget_constructors` (public widgets need `super.key`),
  `use_build_context_synchronously` (check `mounted` after `await`),
  `unnecessary_import`, `prefer_final_fields`.
- New public API used across files: grep for stale references after renames
  (`grep -rn "OldName" app/lib app/test`).
- Every subclass of a `sealed` class must be handled in all `switch`es on it
  (e.g. `WorkspaceTab` in `features/editor/workspace.dart`).

## 2. Run the checks locally when Flutter exists

```bash
command -v flutter && cd app && flutter pub get && flutter analyze && flutter test
```

On the Termux device follow the global device rules: one heavy command per
call, run in the background with a log in `$TMPDIR`, read only the tail/grep.
Run single test files while iterating (`flutter test test/foo_test.dart`).

## 3. No Flutter locally (Termux): validate through CI

Flutter is not installed on the phone, so push the branch and read CI.
Requires `GITHUB_TOKEN` in the environment (a token with `repo`/`actions:read`
for the repo). Never write a token into files, commits or command output.

```bash
git push -u origin HEAD             # only when the user asked to push
bash .claude/skills/validate-changes/ci-check.sh   # waits for the run of HEAD
```

`ci-check.sh` finds the CI run for the current commit, waits for it, and on
failure prints the failing step plus analyzer issues (`error|warning|info •`)
and failing tests. Fix every reported issue, push again, re-run until green.

If `GITHUB_TOKEN` is not set, stop and ask the user to set it (e.g.
`export GITHUB_TOKEN=...` in `~/.bashrc`), or to paste the failing CI log.

## 4. Report

Tell the user exactly what ran and its result (analyze issues count, tests
passed/failed). If nothing could run, say the change is unverified.
