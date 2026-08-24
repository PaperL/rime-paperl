-- Auto-commit LaTeX symbols when the input is complete.
local M = {}

local function get_log_path()
  if rime_api and rime_api.get_user_data_dir then
    return rime_api.get_user_data_dir() .. "/candidate_logs/latex_auto_commit.log"
  end
  return "./candidate_logs/latex_auto_commit.log"
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

local function get_active_menu(ctx)
  local composition = ctx.composition
  if not composition or composition:empty() then
    return nil
  end
  local segment = composition:back()
  return segment and segment.menu or nil
end

local function get_candidate(ctx)
  local cand = ctx:get_selected_candidate()
  local menu = get_active_menu(ctx)
  if (not cand) and menu then
    cand = menu:get_candidate_at(0)
  end
  return cand
end

local function has_single_candidate(ctx)
  local menu = get_active_menu(ctx)
  if not menu then
    return false
  end
  return menu:prepare(2) == 1
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
  if env then
    local cand2_exists = false
    local menu = get_active_menu(ctx)
    if menu then
      cand2_exists = menu:get_candidate_at(1) ~= nil
    end
    log_line(env, "input=" .. safe_field(input) ..
      " cand=" .. safe_field(cand.text) ..
      " comment=" .. safe_field(cand.comment) ..
      " single_candidate=" .. tostring(single_candidate) ..
      " cand2=" .. tostring(cand2_exists) ..
      " composing=" .. tostring(ctx:is_composing()) ..
      " menu=" .. tostring(ctx:has_menu()))
  end
  if not single_candidate then
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
  env.log_path = env.enable_log and get_log_path() or nil
  log_line(env, "init log_path=" .. safe_field(env.log_path))
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
