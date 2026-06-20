--[[--------------------------------------------------------------------
 SpellQueueOptimizer
 Author: Maximilian Anton Grimm | grimm@grimmcreative.com
 Version: 1.1.0

 Purpose:
   Automatically tunes the SpellQueueWindow (SQW) to a sensible value
   derived from your current latency (GetNetStats) and specialization.
   Runs on login/zone/spec change and periodically.

 Midnight (12.0) notes:
   - Uses C_CVar / C_SpecializationInfo namespaces (with legacy fallbacks).
   - Secure CVars can no longer be set during combat; changes are deferred
     and re-applied on PLAYER_REGEN_ENABLED (combat end).
   - Tuning follows current guidance: baseline 200 ms + ping, clamped
     200..400 ms, with small per-spec corrections.

 License:
   You may use, modify, and redistribute this addon with attribution.
----------------------------------------------------------------------]]

local ADDON_NAME = "SpellQueueOptimizer"

-- SavedVariables (initialized with defaults on first load)
SpellQueueOptimizerDB = SpellQueueOptimizerDB or {}

-- Defaults and clamps
local defaults = {
  enabled  = true,
  interval = 300,     -- seconds (5 minutes)
  override = nil,     -- fixed SQW in ms; when set, auto logic is skipped
  verbose  = true,    -- chat output on/off
}

-- Utility: formatted printing with an addon tag
local function Print(msg)
  if SpellQueueOptimizerDB.verbose then
    print("|cff66ccffSQO|r: " .. (msg or ""))
  end
end

-- API shims: prefer modern C_* namespaces (Midnight 12.0), fall back to globals.
local function GetSQW()
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  return tonumber(get("SpellQueueWindow")) or 0
end

-- Returns true if the value was applied, false if it could not be (e.g. combat).
local function SetSQW(v)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  return set("SpellQueueWindow", v) ~= false
end

-- Utility: clamp number
local function Clamp(v, minv, maxv)
  if v < minv then return minv end
  if v > maxv then return maxv end
  return v
end

-- Utility: round to nearest 10 ms for cleaner values
local function RoundToNearest10(x)
  return math.floor((x + 5) / 10) * 10
end

-- Spec categories (coarse buckets) — used as SMALL corrections on top of the
-- ping-based baseline, not as the primary driver.
-- channel_heavy  : a touch more buffer for smooth channel clipping/queuing
-- proc_reactive  : slightly tighter so reactive inputs aren't swallowed
-- burst_precise  : neutral (uses the baseline)
local SPEC_CHANNEL_HEAVY = {
  [258] = true,   -- Priest: Shadow
  [270] = true,   -- Monk: Mistweaver
  [1467] = true,  -- Evoker: Devastation
  [1468] = true,  -- Evoker: Preservation
  [265] = true,   -- Warlock: Affliction
}

local SPEC_PROC_REACTIVE = {
  [63] = true, [64] = true, [62] = true, -- Mage specs
  [103] = true,   -- Druid: Feral
  [262] = true,   -- Shaman: Elemental
  [577] = true, [581] = true, -- DH
}

local SPEC_BURST_PRECISE = {
  [253] = true, [254] = true, [255] = true, -- Hunter
  [66] = true, [70] = true, [65] = true,    -- Paladin
  [71] = true, [72] = true, [73] = true,    -- Warrior
  [250] = true, [251] = true, [252] = true, -- DK
  [259] = true, [260] = true, [261] = true, -- Rogue
  [268] = true, [269] = true,               -- Monk
  [102] = true, [104] = true, [105] = true, -- Druid
  [256] = true, [257] = true,               -- Priest
  [264] = true,                             -- Shaman
  [266] = true, [267] = true,               -- Warlock
}

-- Compute target SQW (ms) from latency and spec bucket.
--
-- Current guidance (Midnight 12.0 theorycrafting): a larger SQW is generally
-- better for queue reliability. Keep it near the 400 ms cap; never go below
-- ~200 ms + your ping. This addon therefore uses:
--
--   baseline   = 200 + ping
--   correction = channel_heavy +30 | proc_reactive -20 | burst_precise 0
--   result     = clamp(baseline + correction, 200, 400), rounded to 10 ms
--
-- On a typical EU ping (20–35 ms) this yields ~210–260 ms — well inside the
-- recommended band, instead of the old aggressive 60–140 ms values.
local function ComputeOptimalSQW(pingMs, specId)
  local ping = (pingMs and pingMs > 0) and pingMs or 30 -- safe ping assumption

  local correction = 0
  if SPEC_CHANNEL_HEAVY[specId] then
    correction = 30
  elseif SPEC_PROC_REACTIVE[specId] then
    correction = -20
  end -- burst_precise / unknown: neutral

  local raw = 200 + ping + correction
  raw = Clamp(raw, 200, 400)
  return RoundToNearest10(raw)
end

-- Get current home/world latency (ms)
local function GetCurrentPings()
  local _, _, home, world = GetNetStats()
  return tonumber(home) or 0, tonumber(world) or 0
end

-- Get current spec ID (e.g., 258 for Shadow)
local function GetCurrentSpecID()
  local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  if not getSpec or not getInfo then return nil end
  local specIndex = getSpec()
  if not specIndex then return nil end
  return getInfo(specIndex)
end

-- Set true when a desired change could not be applied because we were in
-- combat; PLAYER_REGEN_ENABLED then re-runs the evaluation.
local pendingApply = false

-- Core: evaluate and apply SQW.
-- Returns the desired value so callers can re-use it.
local function EvaluateAndApplySQW(reason)
  if not SpellQueueOptimizerDB.enabled then
    return
  end

  -- Determine the desired value (override beats auto logic).
  local desired, detail
  if SpellQueueOptimizerDB.override and tonumber(SpellQueueOptimizerDB.override) then
    desired = tonumber(SpellQueueOptimizerDB.override)
    detail = "Override"
  else
    local home, world = GetCurrentPings()
    local ping = math.max(home, world) -- conservative: use the worse value
    local specId = GetCurrentSpecID() or 0
    desired = ComputeOptimalSQW(ping, specId)
    detail = string.format("Ping H/W %d/%d ms, %s", home, world,
      specId ~= 0 and ("SpecID " .. specId) or "unknown spec")
  end

  local current = GetSQW()
  if current == desired then
    Print(string.format("SQW already %d ms (%s; %s).", current, detail, reason or ""))
    pendingApply = false
    return desired
  end

  -- Midnight: secure CVars cannot be set in combat. Defer if needed.
  if InCombatLockdown() then
    pendingApply = true
    Print(string.format("In combat – will set SQW to %d ms after combat (%s).", desired, reason or ""))
    return desired
  end

  if SetSQW(desired) then
    pendingApply = false
    Print(string.format("SQW %d → %d ms (%s; %s).", current, desired, detail, reason or ""))
  else
    -- Could not apply (e.g. protected). Try again after combat just in case.
    pendingApply = true
    Print(string.format("Could not set SQW right now; will retry (%s).", reason or ""))
  end
  return desired
end

-- Periodic ticker
local ticker
local function StartTicker()
  if ticker then ticker:Cancel() end
  local interval = tonumber(SpellQueueOptimizerDB.interval) or defaults.interval
  interval = Clamp(interval, 60, 900) -- 1–15 minutes safety
  ticker = C_Timer.NewTicker(interval, function()
    EvaluateAndApplySQW("periodic")
  end)
  Print(string.format("Auto-check every %d s enabled.", interval))
end

-- Event wiring
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CVAR_UPDATE")

f:SetScript("OnEvent", function(_, event, arg1, _)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    -- merge defaults
    for k, v in pairs(defaults) do
      if SpellQueueOptimizerDB[k] == nil then
        SpellQueueOptimizerDB[k] = v
      end
    end
    Print("loaded. Type /sqo for help.")
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    EvaluateAndApplySQW("login/zone")
    StartTicker()
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    EvaluateAndApplySQW("spec changed")
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- world ping can shift on instance change
    EvaluateAndApplySQW("instance changed")
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- combat ended: apply anything that was deferred during combat
    if pendingApply then
      EvaluateAndApplySQW("after combat")
    end
  elseif event == "CVAR_UPDATE" then
    -- observe external changes to SpellQueueWindow
    if arg1 == "SpellQueueWindow" or arg1 == "spellqueuewindow" then
      local v = GetSQW()
      Print(string.format("CVar SpellQueueWindow changed → %d ms.", v))
    end
  end
end)

-- Slash command: /sqo
SLASH_SQO1 = "/sqo"
SlashCmdList.SQO = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" or msg == "help" then
    print("|cff66ccffSQO|r Commands:")
    print("  /sqo show           - Show current SQW & ping")
    print("  /sqo now            - Recalculate & apply now")
    print("  /sqo on|off         - Enable/disable auto-optimization")
    print("  /sqo interval <s>   - Set interval 60..900 seconds (default 300)")
    print("  /sqo set <ms>       - Set fixed override (e.g., /sqo set 250)")
    print("  /sqo clear          - Remove override (return to auto mode)")
    print("  /sqo quiet|verbose  - Toggle chat verbosity")
    return
  end

  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  if cmd == "show" then
    local home, world = GetCurrentPings()
    local current = GetSQW()
    local specId = GetCurrentSpecID() or 0
    local mode = (SpellQueueOptimizerDB.override and "Override")
              or (SpellQueueOptimizerDB.enabled and "Auto")
              or "Manual"
    print(string.format("|cff66ccffSQO|r Status: SQW %d ms | Ping H/W %d/%d ms | Spec %s | Mode %s",
      current, home, world, (specId ~= 0 and specId or "unknown"), mode))
  elseif cmd == "now" then
    EvaluateAndApplySQW("manual")
  elseif cmd == "on" then
    SpellQueueOptimizerDB.enabled = true
    Print("Auto-optimization enabled.")
    EvaluateAndApplySQW("enabled")
    StartTicker()
  elseif cmd == "off" then
    SpellQueueOptimizerDB.enabled = false
    Print("Auto-optimization disabled. (Value persists until changed.)")
    if ticker then ticker:Cancel() end
  elseif cmd == "interval" then
    local v = tonumber(rest)
    if v then
      v = Clamp(v, 60, 900)
      SpellQueueOptimizerDB.interval = v
      Print("Interval set to " .. v .. " s.")
      StartTicker()
    else
      Print("Invalid interval. Example: /sqo interval 180")
    end
  elseif cmd == "set" then
    local v = tonumber(rest)
    if v then
      v = Clamp(v, 0, 400) -- hard bounds (Blizzard caps SQW at 400 ms)
      SpellQueueOptimizerDB.override = v
      EvaluateAndApplySQW("override set") -- handles combat deferral
    else
      Print("Please provide milliseconds. Example: /sqo set 250")
    end
  elseif cmd == "clear" then
    SpellQueueOptimizerDB.override = nil
    Print("Override cleared. Returning to automatic optimization.")
    EvaluateAndApplySQW("override cleared")
  elseif cmd == "quiet" then
    SpellQueueOptimizerDB.verbose = false
    print("|cff66ccffSQO|r: Verbosity reduced.")
  elseif cmd == "verbose" then
    SpellQueueOptimizerDB.verbose = true
    print("|cff66ccffSQO|r: Verbosity enabled.")
  else
    Print("Unknown command. Use /sqo help for usage.")
  end
end