-- Auto-commit LaTeX symbols when the input is complete.
local M = {}

local function get_log_path()
  if rime_api and rime_api.get_user_data_dir then
    return rime_api.get_user_data_dir() .. "/logs/latex_auto_commit.log"
  end
  return "./logs/latex_auto_commit.log"
end

local function log_line(env, msg)
  if not env or not env.enable_log or not env.log_path then
    return
  end
  local ok, file = pcall(io.open, env.log_path, "a")
  if not ok or not file then
    return
  end
  file:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg .. "\n")
  file:close()
end

local function safe_field(value)
  if value == nil then
    return "nil"
  end
  if value == "" then
    return "<empty>"
  end
  return value
end

local function get_candidate(ctx)
  local cand = ctx:get_selected_candidate()
  if (not cand) and ctx.menu and ctx.menu.get_candidate_at then
    cand = ctx.menu:get_candidate_at(0)
  end
  return cand
end

local function has_single_candidate(ctx)
  if not (ctx.menu and ctx.menu.get_candidate_at) then
    return false
  end
  local first = ctx.menu:get_candidate_at(0)
  if not first then
    return false
  end
  return ctx.menu:get_candidate_at(1) == nil
end

local function add_code_prefixes(counts, seen, code)
  if not code or code == "" then
    return
  end
  if code:sub(1, 1) ~= "\\" then
    return
  end
  if seen[code] then
    return
  end
  seen[code] = true
  for i = 1, #code do
    local prefix = code:sub(1, i)
    counts[prefix] = (counts[prefix] or 0) + 1
  end
end

local function load_prefix_counts()
  if not (rime_api and rime_api.get_user_data_dir) then
    return nil
  end
  local user_dir = rime_api.get_user_data_dir()
  local counts = {}
  local seen = {}
  local loaded = false

  local function load_tsv(path, requires_yaml_end)
    local file = io.open(path, "r")
    if not file then
      return false
    end
    local in_body = not requires_yaml_end
    for line in file:lines() do
      if line ~= nil and line ~= "" then
        line = line:match("[^\r\n]+")
      end
      if not line or line == "" then
        -- skip
      elseif not in_body then
        if line:match("^%.%.%.") then
          in_body = true
        end
      elseif not line:match("^#") then
        local _, _, _, code = line:find("^([^\t]+)\t([^\t]+)")
        if code then
          add_code_prefixes(counts, seen, code)
        end
      end
    end
    file:close()
    return true
  end

  if load_tsv(user_dir .. "/latex.dict.yaml", true) then
    loaded = true
  end
  if load_tsv(user_dir .. "/custom_latex_user.txt", false) then
    loaded = true
  end
  if loaded then
    return counts
  end
  return nil
end

local function try_commit(ctx, engine, env)
  if not (ctx:is_composing() or ctx:has_menu()) then
    return false
  end

  local input = ctx.input or ""
  if input:sub(1, 1) ~= "\\" or #input < 2 then
    return false
  end

  local cand = get_candidate(ctx)
  if not cand then
    return false
  end
  local single_candidate = has_single_candidate(ctx)
  local unique_prefix = false
  if env and env.latex_prefix_counts then
    unique_prefix = env.latex_prefix_counts[input] == 1
  end
  local fast_ok = false
  if env and env.fast_commit_single_candidate then
    fast_ok = single_candidate or unique_prefix
  end
  if env then
    local cand2_exists = false
    if ctx.menu and ctx.menu.get_candidate_at then
      cand2_exists = ctx.menu:get_candidate_at(1) ~= nil
    end
    local prefix_count = env.latex_prefix_counts and env.latex_prefix_counts[input] or 0
    log_line(env, "input=" .. safe_field(input) ..
      " cand=" .. safe_field(cand.text) ..
      " comment=" .. safe_field(cand.comment) ..
      " prefix_count=" .. tostring(prefix_count) ..
      " unique_prefix=" .. tostring(unique_prefix) ..
      " fast_ok=" .. tostring(fast_ok) ..
      " single_candidate=" .. tostring(single_candidate) ..
      " cand2=" .. tostring(cand2_exists) ..
      " composing=" .. tostring(ctx:is_composing()) ..
      " menu=" .. tostring(ctx:has_menu()))
  end
  if not fast_ok and cand.comment and cand.comment ~= "" then
    return false
  end

  engine:commit_text(cand.text)
  ctx:clear()
  log_line(env, "commit input=" .. safe_field(input) .. " text=" .. safe_field(cand.text))
  return true
end

function M.init(env)
  env.in_commit = false
  env.name_space = env.name_space:gsub('^*', '')
  local config = env.engine.schema.config
  env.enable_log = config:get_bool(env.name_space .. "/enable_log") or false
  env.fast_commit_single_candidate = config:get_bool(env.name_space .. "/fast_commit_single_candidate") or false
  env.latex_prefix_counts = load_prefix_counts()
  env.log_path = env.enable_log and get_log_path() or nil
  log_line(env, "init log_path=" .. safe_field(env.log_path) ..
    " prefix_counts_loaded=" .. tostring(env.latex_prefix_counts ~= nil) ..
    " fast_commit_single_candidate=" .. tostring(env.fast_commit_single_candidate))
  env.notifier = env.engine.context.update_notifier:connect(function(ctx)
    if env.in_commit then
      return
    end
    env.in_commit = true
    local ok = try_commit(ctx, env.engine, env)
    env.in_commit = false
    return ok
  end)
end

function M.func(key, env)
  if key:release() then
    return 2
  end
  if try_commit(env.engine.context, env.engine, env) then
    return 1
  end
  return 2
end

return M
