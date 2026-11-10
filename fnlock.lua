-- Loaded by the optional setup with fixed paths and the validated XKB settings.
return function(config)
  local M = {}

  local function layout_matches()
    for field, value in pairs(config.layout) do
      if (hl.get_config("input.kb_" .. field) or "") ~= value then return false end
    end
    local file = hl.get_config("input.kb_file")
    return not file or file == "" or file == "[[EMPTY]]"
  end

  function M.apply(mode)
    assert(mode == "function" or mode == "media", "Invalid Fn Lock mode")
    assert(layout_matches(), "Keyboard layout changed; set up Fn Lock again")
    local keymap = mode == "media" and config.keymap or ""
    for _, name in ipairs(config.devices) do
      hl.device({ name = name, kb_file = keymap, resolve_binds_by_sym = true })
    end
  end

  function M.setup()
    local flag = io.open(config.mode, "r")
    if not flag then return end
    local mode = flag:read("*l")
    flag:close()
    if not layout_matches() or (mode ~= "function" and mode ~= "media") then return end
    M.apply(mode)
    local function bind(key, description, action)
      o.bind(key, description, action, { device = { inclusive = true, list = config.devices } })
    end
    bind("XF86Fn_Esc", config.description, config.command .. " fnlock toggle --notify")
    bind("XF86Launch5", "ROG Helper: Cycle power profile", config.command .. " fnlock-hotkey profile")
    bind("XF86Display", "ROG Helper: Display controls", { panel = "omarchy.monitor" })
    bind("XF86RFKill", "ROG Helper: Toggle airplane mode", config.command .. " fnlock-hotkey airplane")
  end

  return M
end
