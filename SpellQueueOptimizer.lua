--[[--------------------------------------------------------------------
 SpellQueueOptimizer
 Author: Maximilian Anton Grimm | grimm@grimmcreative.com
 Version: 1.0.0

 Purpose:
   Automatically tunes the SpellQueueWindow (SQW) to a sensible value
   derived from your current latency (GetNetStats) and specialization.
   Runs on login/zone/spec change and periodically.

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

-- Spec categories (coarse buckets)
-- channel_heavy  : benefits from a slightly larger SQW for smooth channel clipping/queuing
-- proc_reactive  : too large SQW may swallow reactive inputs
-- burst_precise  : generally prefers a tighter SQW window
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
-- Baseline:
--   channel_heavy : ping * 3.0, clamped  90..140
--   proc_reactive : ping * 2.5, clamped  70..110
--   burst_precise : ping * 2.0, clamped  60..100
-- Rounded to 10 ms. On typical EU pings (20–35 ms) this yields ~80–110 ms.
local function ComputeOptimalSQW(pingMs, specId)
  if not pingMs or pingMs <= 0 then
    return 100 -- safe default
  end

  local raw
  if SPEC_CHANNEL_HEAVY[specId] then
    raw = pingMs * 3.0
    raw = Clamp(raw, 90, 140)
  elseif SPEC_PROC_REACTIVE[specId] then
    raw = pingMs * 2.5
    raw = Clamp(raw, 70, 110)
  else
    -- default/fallback to burst_precise tuning
    raw = pingMs * 2.0
    raw = Clamp(raw, 60, 100)
  end

  return RoundToNearest10(raw)
end

-- Get current home/world latency (ms)
local function GetCurrentPings()
  local _, _, home, world = GetNetStats()
  return tonumber(home) or 0, tonumber(world) or 0
end

-- Get current spec ID (e.g., 258 for Shadow)
local function GetCurrentSpecID()
  local specIndex = GetSpecialization and GetSpecialization()
  if not specIndex then return nil end
  local specId = GetSpecializationInfo(specIndex)
  return specId
end

-- Core: evaluate and apply SQW
local function EvaluateAndApplySQW(reason)
  if not SpellQueueOptimizerDB.enabled then
    return
  end

  -- Manual override takes precedence
  if SpellQueueOptimizerDB.override and tonumber(SpellQueueOptimizerDB.override) then
    local overrideVal = tonumber(SpellQueueOptimizerDB.override)
    local current = tonumber(GetCVar("SpellQueueWindow")) or 0
    if current ~= overrideVal then
      SetCVar("SpellQueueWindow", overrideVal)
      Print(string.format("Override active – set SQW to %d ms (%s).", overrideVal, reason or ""))
    else
      Print(string.format("Override active – SQW already %d ms (%s).", overrideVal, reason or ""))
    end
    return
  end

  local home, world = GetCurrentPings()
  local ping = math.max(home, world) -- conservative: use the worse value
  local specId = GetCurrentSpecID() or 0
  local optimal = ComputeOptimalSQW(ping, specId)

  local current = tonumber(GetCVar("SpellQueueWindow")) or 0
  if current ~= optimal then
    SetCVar("SpellQueueWindow", optimal)
    local specTxt = specId ~= 0 and ("SpecID " .. specId) or "unknown spec"
    Print(string.format("Ping H/W: %d/%d ms → %s → SQW %d ms (%s).", home, world, specTxt, optimal, reason or ""))
  else
    Print(string.format("SQW already optimal (%d ms). Ping H/W: %d/%d ms (%s).", current, home, world, reason or ""))
  end
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
  elseif event == "CVAR_UPDATE" then
    -- observe external changes to SpellQueueWindow
    if arg1 == "SpellQueueWindow" or arg1 == "spellqueuewindow" then
      local v = tonumber(GetCVar("SpellQueueWindow")) or 0
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
    print("  /sqo set <ms>       - Set fixed override (e.g., /sqo set 100)")
    print("  /sqo clear          - Remove override (return to auto mode)")
    print("  /sqo quiet|verbose  - Toggle chat verbosity")
    return
  end

  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  if cmd == "show" then
    local home, world = GetCurrentPings()
    local current = tonumber(GetCVar("SpellQueueWindow")) or 0
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
      v = Clamp(v, 10, 400) -- hard bounds (Blizzard uses 400 as default upper)
      SpellQueueOptimizerDB.override = v
      SetCVar("SpellQueueWindow", v)
      Print("Override active → SQW set to " .. v .. " ms.")
    else
      Print("Please provide milliseconds. Example: /sqo set 100")
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