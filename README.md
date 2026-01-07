# Rime config (frost + LaTeX)

This user directory is based on the `rime-frost` schema, with LaTeX math symbols added from `rime_latex` and wired into `rime_frost`.

## LaTeX auto-commit inside rime_frost

LaTeX input is enabled via `rime_frost.custom.yaml` and a custom Lua processor `lua/latex_auto_commit.lua`. The processor commits a symbol when:
- the input starts with `\` and is longer than 1 character, and
- the candidate comment is empty (meaning the symbol name is fully matched).

This gives the same "type \alpha then auto-commit" behavior as the standalone LaTeX schema while staying inside `rime_frost`.

Relevant files:
- `rime_frost.custom.yaml`
- `lua/latex_auto_commit.lua`
- `custom_latex_user.txt`

## Pin candidates: pin_cand_filter vs custom_phrase.txt

There are two ways to force preferred candidates:

- `pin_cand_filter` (in `rime_frost.custom.yaml`) only reorders candidates that already appear. It does not create new entries. It scans only the first 100 candidates, so low-frequency items (for example `祂` in a short code like `t`) may not be pinned if they fall beyond that range.

- `custom_phrase.txt` adds entries into a dedicated dictionary with very high weight, so they appear at the top even if they are rare or would not normally appear early. This is the reliable option when the candidate list is large.

Rule of thumb:
- Use `pin_cand_filter` for small candidate sets or specific full codes.
- Use `custom_phrase.txt` when the candidate list is large or you need a guaranteed top result.
