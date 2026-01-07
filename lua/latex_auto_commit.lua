-- Auto-commit LaTeX symbols when the input is complete.
local M = {}

local function get_candidate(ctx)
  local cand = ctx:get_selected_candidate()
  if (not cand) and ctx.menu and ctx.menu.get_candidate_at then
    cand = ctx.menu:get_candidate_at(0)
  end
  return cand
end

local function try_commit(ctx, engine)
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
  if cand.comment and cand.comment ~= "" then
    return false
  end

  engine:commit_text(cand.text)
  ctx:clear()
  return true
end

function M.init(env)
  env.in_commit = false
  env.notifier = env.engine.context.update_notifier:connect(function(ctx)
    if env.in_commit then
      return
    end
    env.in_commit = true
    local ok = try_commit(ctx, env.engine)
    env.in_commit = false
    return ok
  end)
end

function M.func(key, env)
  if key:release() then
    return 2
  end
  if try_commit(env.engine.context, env.engine) then
    return 1
  end
  return 2
end

return M
