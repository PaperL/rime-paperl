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

## Pin candidates: pin_cand_filter vs custom_phrase.txt

There are two ways to force preferred candidates:

- `pin_cand_filter` (in [`rime_frost.custom.yaml`](rime_frost.custom.yaml)) only reorders candidates that already appear. It does not create new entries. It scans only the first 100 candidates, so low-frequency items (for example `祂` in a short code like `t`) may not be pinned if they fall beyond that range.

- [`custom_phrase.txt`](custom_phrase.txt) adds entries into a dedicated dictionary with very high weight, so they appear at the top even if they are rare or would not normally appear early. This is the reliable option when the candidate list is large.

Rule of thumb:
- Use `pin_cand_filter` for small candidate sets or specific full codes.
- Use [`custom_phrase.txt`](custom_phrase.txt) when the candidate list is large or you need a guaranteed top result.
