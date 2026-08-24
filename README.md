# Rime config (frost + LaTeX)

This user directory is based on the `rime-frost` schema ([gaboolic/rime-frost](https://github.com/gaboolic/rime-frost)), with the dictionary core from `RIME-LMDG` ([amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG)). LaTeX math symbols are added from `rime_latex` ([shenlebantongying/rime_latex](https://github.com/shenlebantongying/rime_latex)) and wired into `rime_frost`. The macOS frontend is `squirrel` ([rime/squirrel](https://github.com/rime/squirrel)).

## LaTeX quick input inside rime_frost

LaTeX input is enabled via [`rime_frost.custom.yaml`](rime_frost.custom.yaml) and the Lua processor [`lua/latex_auto_commit.lua`](lua/latex_auto_commit.lua).

How it works:
- `\` is allowed as input by extending `speller/alphabet`, so `\alpha` stays in the composing buffer.
- `recognizer/patterns/latex_input` matches `^\[a-zA-Z]+$`, and `table_translator@latex_input` reads from [`latex.dict.yaml`](latex.dict.yaml) and [`custom_latex_user.txt`](custom_latex_user.txt).
- The Lua processor watches the context and commits a symbol when the input starts with `\` and a valid candidate exists.

Default behavior (safe):
- Only auto-commit when the candidate is fully matched (candidate comment is empty).
- Example: `\alpha` auto-commits, but `\alp` does not.

Fast commit (optional):
- Enable `latex_auto_commit/fast_commit_single_candidate: true` in [`rime_frost.custom.yaml`](rime_frost.custom.yaml) to auto-commit as soon as the LaTeX candidate becomes unique.
- This uses both [`latex.dict.yaml`](latex.dict.yaml) and [`custom_latex_user.txt`](custom_latex_user.txt) to determine uniqueness, so `\alp` can commit `α` without pressing any confirm key.

Relevant files:
- [`rime_frost.custom.yaml`](rime_frost.custom.yaml)
- [`lua/latex_auto_commit.lua`](lua/latex_auto_commit.lua)
- [`custom_latex_user.txt`](custom_latex_user.txt)
- [`latex.dict.yaml`](latex.dict.yaml)

Logging (optional):
- Set `latex_auto_commit/enable_log: true` in [`rime_frost.custom.yaml`](rime_frost.custom.yaml).
- Logs are written to [`logs/latex_auto_commit.log`](logs/latex_auto_commit.log).

## Candidate-page feedback logging

When the candidate menu is open, press `;` to record the visible candidate page and then clear the composition, like pressing `Escape`. Nothing is committed. Outside a candidate menu, `;` keeps its normal punctuation behavior. This replaces the original `;` shortcut for selecting candidate 2; use the `2` key for that selection instead.

Daily CSV files are created in the Rime user directory only when the shortcut is used:

- Directory: `~/Library/Rime/candidate_logs/`
- Path pattern: `~/Library/Rime/candidate_logs/candidate_log_YYYYMMDD.csv`
- Example for 2026-08-24: `candidate_logs/candidate_log_20260824.csv`
- The files are local runtime data and are ignored by Git.

Each trigger writes one CSV row containing the timestamp, schema, previous Rime commit, raw input, page number, highlighted rank, and candidate count. Every candidate then contributes `text`, `comment`, and `type` columns in display order. The number of candidate column groups follows the number of candidates actually present on that page.

If the CSV cannot be written, the semicolon is consumed but the composition remains open so the input is not silently lost. The implementation is in [`lua/candidate_logger.lua`](lua/candidate_logger.lua) and is enabled by [`rime_frost.custom.yaml`](rime_frost.custom.yaml).

Processed logs are moved to `candidate_logs/archive/`; both active and archived CSV files remain local and are ignored by Git. Add a `_processed_YYYYMMDD-HHMMSS` suffix when archiving so a new log from the same day cannot overwrite an older archive. Handle an entry according to the desired result: if the word already exists but is ordered too low, add it to `pin_cand_filter`; if it is absent, add an exact entry to [`custom_phrase.txt`](custom_phrase.txt); use user-frequency tuning only when the problem is learned history rather than a stable preference. Redeploy, verify the input, and archive the daily CSV only after every row in that file has been handled.

## Pin candidates: pin_cand_filter vs custom_phrase.txt

There are two ways to force preferred candidates:

- `pin_cand_filter` (in [`rime_frost.custom.yaml`](rime_frost.custom.yaml)) only reorders candidates that already appear. It does not create new entries. It scans only the first 100 candidates, so low-frequency items (for example `祂` in a short code like `t`) may not be pinned if they fall beyond that range.

- [`custom_phrase.txt`](custom_phrase.txt) adds entries into a dedicated dictionary with very high weight, so they appear at the top even if they are rare or would not normally appear early. This is the reliable option when the candidate list is large.

Rule of thumb:
- Use `pin_cand_filter` for small candidate sets or specific full codes.
- Use [`custom_phrase.txt`](custom_phrase.txt) when the candidate list is large or you need a guaranteed top result.

## Manual User Learning Frequency

User learning can override static dictionary weights. If a candidate has `*`, it is a learned user phrase (see [`lua/is_in_user_dict.lua`](lua/is_in_user_dict.lua)).

Learning-driven frequency tuning:

1. Edit only target lines in the current snapshot, for example [`sync/a2a2a7e4-ca81-44f5-98f5-51a5e57ca9a7/rime_frost_lmdg.userdb.txt`](sync/a2a2a7e4-ca81-44f5-98f5-51a5e57ca9a7/rime_frost_lmdg.userdb.txt).
2. Use small changes first, then verify input behavior.
3. Keep changes focused; avoid broad edits.
4. During verification, avoid committing the undesired candidate once, or it may be learned back immediately.

Quick field reference:

- `c`: usage count (higher usually ranks higher)
- `t`: recency tick context
- `d`: internal model factor

## Deploy & Sync Button

- `Deploy`: rebuilds schema and dictionaries (for example `rime_frost_lmdg`).
- `Sync user data`: merges snapshot txt into live userdb, then writes merged results back to snapshot txt.
- `Sync user data` is merge + write-back, not one-way overwrite. Manual edits can be changed by merge results.

Even on one machine, multiple folders under [`sync`](sync) can exist because sync is keyed by `installation_id` (see [`installation.yaml`](installation.yaml)), not strictly by physical devices.

## Shortcut

This section records currently enabled shortcuts from the active config (`default.yaml` + `rime_frost.schema.yaml` + `rime_frost.custom.yaml`). Commented examples are not included.

Switcher:
- `F4`: open schema switcher.
- `Control+grave`: open schema switcher.
- `Control+Shift+grave`: open schema switcher.

Composing and paging (`key_binder/bindings`):
- `semicolon` (`;`, when has menu): log the visible candidate page, then clear the composition without committing; candidate 2 remains available through the `2` key.
- `backslash` (`\\`, when composing): move to the first syllable of the current unconfirmed input for single-character selection (`Home`, then `Shift+Right`); with an empty composition, `\\` remains the LaTeX prefix.
- `Tab` (when composing): move caret to next syllable (`Shift+Right`).
- `Shift+Tab` (when composing): move caret to previous syllable (`Shift+Left`).
- `Alt+Right` (when composing): move caret to next syllable (`Shift+Right`).
- `Alt+Left` (when composing): move caret to previous syllable (`Shift+Left`).
- `minus` (when has menu): page up.
- `equal` (when has menu): page down.

Mode toggles:
- `Control+Shift+3`: toggle `ascii_punct`.
- `Control+Shift+numbersign`: toggle `ascii_punct`.
- `Control+Shift+4`: toggle `traditionalization`.
- `Control+Shift+dollar`: toggle `traditionalization`.

Editing:
- `Control+k` (when composing): send `Shift+Delete`.

Numpad mapping (when composing):
- `KP_0`..`KP_9`: map to `0`..`9`.
- `KP_Decimal`: map to `period`.

Select-character Lua keys (`key_binder` root):
- `bracketleft` (`[`): `select_first_character`.
- `bracketright` (`]`): `select_last_character`.

ASCII composer switch behavior:
- `Caps_Lock`: `clear`.
- `Shift_L`: `commit_code`.
- `Shift_R`: `noop`.
- `Control_L`: `noop`.
- `Control_R`: `noop`.

Notes:
- `rime_frost.custom.yaml` adds the composing-only `backslash` binding; it also patches translators/processors and pin candidates.
- If you later enable `cold_word_drop`, extra shortcut keys (for example `Control+j` / `Control+d`) can be added explicitly.
