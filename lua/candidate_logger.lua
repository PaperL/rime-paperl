-- Log the visible candidate page to a daily CSV file when semicolon is pressed.
local M = {}

local function report_error(message)
  if log and log.error then
    log.error("[candidate_logger] " .. tostring(message))
  end
end

local function csv_field(value)
  local text = value == nil and "" or tostring(value)
  -- Keep every event on one physical line while preserving control characters.
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\r", "\\r")
  text = text:gsub("\n", "\\n")
  text = text:gsub('"', '""')
  return '"' .. text .. '"'
end

local function csv_line(fields)
  local encoded = {}
  for index, value in ipairs(fields) do
    encoded[index] = csv_field(value)
  end
  return table.concat(encoded, ",") .. "\n"
end

local function get_log_path()
  local user_dir = "."
  if rime_api and rime_api.get_user_data_dir then
    user_dir = rime_api.get_user_data_dir()
  end
  return user_dir .. "/candidate_logs/candidate_log_" .. os.date("%Y%m%d") .. ".csv"
end

local function get_debug_log_path()
  local user_dir = "."
  if rime_api and rime_api.get_user_data_dir then
    user_dir = rime_api.get_user_data_dir()
  end
  return user_dir .. "/candidate_logs/candidate_debug_" .. os.date("%Y%m%d") .. ".csv"
end

local function is_empty_file(path)
  local file = io.open(path, "rb")
  if not file then
    return true
  end
  local size = file:seek("end") or 0
  file:close()
  return size == 0
end

local function current_segment(context)
  local composition = context.composition
  if not composition or composition:empty() then
    return nil
  end
  return composition:back()
end

local function page_size(env)
  local size = env.engine.schema.page_size
  if size and size > 0 then
    return size
  end
  size = env.engine.schema.config:get_int("menu/page_size")
  if size and size > 0 then
    return size
  end
  return 5
end

local function collect_record(env)
  local context = env.engine.context
  local segment = current_segment(context)
  if not segment then
    return nil, "candidate menu has no active segment"
  end

  local size = page_size(env)
  local selected_index = segment.selected_index or 0
  local page_start = math.floor(selected_index / size) * size
  local candidates = {}

  for offset = 0, size - 1 do
    local candidate = segment:get_candidate_at(page_start + offset)
    if not candidate then
      break
    end
    candidates[#candidates + 1] = candidate
  end

  if #candidates == 0 then
    return nil, "candidate menu returned no candidates"
  end

  local previous_commit = context.commit_history:latest_text() or ""
  local schema_id = env.engine.schema.schema_id
    or env.engine.schema.config:get_string("schema/schema_id")
    or ""
  local fields = {
    os.date("%Y-%m-%d %H:%M:%S"),
    schema_id,
    previous_commit,
    context.input or "",
    math.floor(page_start / size) + 1,
    (selected_index - page_start) + 1,
    #candidates,
  }

  for _, candidate in ipairs(candidates) do
    fields[#fields + 1] = candidate.text or ""
    fields[#fields + 1] = candidate.comment or ""
    fields[#fields + 1] = candidate.type or ""
  end

  return {
    fields = fields,
    candidate_count = #candidates,
  }
end

local function make_header(candidate_count)
  local fields = {
    "timestamp",
    "schema",
    "previous_commit",
    "input",
    "page",
    "highlighted_rank",
    "candidate_count",
  }
  for index = 1, candidate_count do
    fields[#fields + 1] = "candidate_" .. index .. "_text"
    fields[#fields + 1] = "candidate_" .. index .. "_comment"
    fields[#fields + 1] = "candidate_" .. index .. "_type"
  end
  return fields
end

local function append_record(record)
  local path = get_log_path()
  local needs_header = is_empty_file(path)
  local ok, result, message = pcall(function()
    local file, open_error = io.open(path, "ab")
    if not file then
      return false, open_error
    end

    local write_ok, write_error
    if needs_header then
      write_ok, write_error = file:write(csv_line(make_header(record.candidate_count)))
      if not write_ok then
        file:close()
        return false, write_error
      end
    end
    write_ok, write_error = file:write(csv_line(record.fields))
    local close_ok, close_error = file:close()
    if not write_ok then
      return false, write_error
    end
    if not close_ok then
      return false, close_error
    end
    return true
  end)

  if not ok then
    return false, result
  end
  return result, message
end

local function candidate_debug_text(candidate, index)
  local dynamic_type = ""
  if candidate.get_dynamic_type then
    local ok, value = pcall(function()
      return candidate:get_dynamic_type()
    end)
    if ok and value then
      dynamic_type = value
    end
  end
  return table.concat({
    tostring(index),
    candidate.text or "",
    candidate.comment or "",
    candidate.type or "",
    dynamic_type,
    tostring(candidate.start or ""),
    tostring(candidate._end or ""),
    tostring(candidate.quality or ""),
    candidate.preedit or "",
  }, "\t")
end

local function append_debug_record(env)
  local context = env.engine.context
  local segment = current_segment(context)
  if not (segment and segment.menu) then
    return false, "candidate menu has no active segment"
  end

  -- Force the filtered translation to reveal whether candidates exist beyond
  -- the visible page. Twenty is enough for diagnosis without exhausting a
  -- potentially large Chinese candidate list.
  local prepared_count = segment.menu:prepare(20)
  local internal_count = segment.menu:candidate_count()
  local candidates = {}
  for index = 0, math.min(internal_count, 20) - 1 do
    local candidate = segment:get_candidate_at(index)
    if not candidate then
      break
    end
    candidates[#candidates + 1] = candidate_debug_text(candidate, index)
  end

  local schema_id = env.engine.schema.schema_id
    or env.engine.schema.config:get_string("schema/schema_id")
    or ""
  local fields = {
    os.date("%Y-%m-%d %H:%M:%S"),
    schema_id,
    context.input or "",
    segment.status or "",
    segment.selected_index or 0,
    page_size(env),
    prepared_count,
    internal_count,
    table.concat(candidates, " || "),
  }
  local header = {
    "timestamp",
    "schema",
    "input",
    "segment_status",
    "selected_index",
    "page_size",
    "prepared_count_up_to_20",
    "internal_candidate_count",
    "candidates_index_text_comment_type_dynamic_start_end_quality_preedit",
  }

  local path = get_debug_log_path()
  local needs_header = is_empty_file(path)
  local ok, result, message = pcall(function()
    local file, open_error = io.open(path, "ab")
    if not file then
      return false, open_error
    end
    if needs_header then
      local header_ok, header_error = file:write(csv_line(header))
      if not header_ok then
        file:close()
        return false, header_error
      end
    end
    local write_ok, write_error = file:write(csv_line(fields))
    local close_ok, close_error = file:close()
    if not write_ok then
      return false, write_error
    end
    if not close_ok then
      return false, close_error
    end
    return true
  end)
  if not ok then
    return false, result
  end
  return result, message
end

function M.func(key, env)
  if key:release() or key:repr() ~= "semicolon" then
    return 2 -- kNoop
  end

  local context = env.engine.context
  if not context:has_menu() then
    return 2 -- Keep normal semicolon punctuation outside a candidate menu.
  end

  local record, collect_error = collect_record(env)
  if not record then
    report_error(collect_error)
    return 1 -- Consume semicolon without clearing the user's input.
  end

  local debug_written, debug_error = append_debug_record(env)
  if not debug_written then
    report_error("failed to append candidate debug log: " .. tostring(debug_error))
  end

  local written, write_error = append_record(record)
  if not written then
    report_error("failed to append candidate log: " .. tostring(write_error))
    return 1 -- Preserve the composition so the user can retry.
  end

  context:clear()
  return 1 -- kAccepted
end

return M
