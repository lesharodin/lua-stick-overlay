local SAMPLE_INTERVAL_TICKS = 2
local ARM_HIGH_THRESHOLD = 512
local LOG_PREFIX = "/LOGS/STICK"
local LOG_EXT = ".CSV"
local MAX_LOG_INDEX = 999
local CONFIG_PATH = "stklog.cfg"

if chdir then
  chdir("/SCRIPTS/TOOLS")
end

local CHANNELS = {}
for i = 1, 16 do
  CHANNELS[i] = "ch" .. i
end

local cfg = {
  arm = 5,
  order = 1,
  stopSec = 60,
}

local ORDER_NAMES = { "AETR", "TAER", "RETA" }

local items = {
  { key = "arm", label = "Arm" },
  { key = "order", label = "Order" },
  { key = "stopSec", label = "StopSec" },
}

local selected = 1
local editing = false
local screen = "status"
local config_dirty = false
local state = "idle"
local file = nil
local current_path = nil
local start_tick = 0
local last_sample_tick = nil
local low_since_tick = nil
local sample_count = 0
local last_error = nil
local last_arm = 0
local last_values = { roll = 0, pitch = 0, thr = 0, yaw = 0 }

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function normalize(value)
  value = value or 0
  local scaled = value * 1000 / 1024
  if scaled >= 0 then
    return clamp(math.floor(scaled + 0.5), -1000, 1000)
  end
  return clamp(math.ceil(scaled - 0.5), -1000, 1000)
end

local function channelName(index)
  return CHANNELS[clamp(index or 1, 1, #CHANNELS)]
end

local function channelLabel(index)
  return string.upper(channelName(index))
end

local function currentOrder()
  return ORDER_NAMES[clamp(cfg.order or 1, 1, #ORDER_NAMES)]
end

local function orderChannel(letter)
  local order = currentOrder()
  for i = 1, string.len(order) do
    if string.sub(order, i, i) == letter then
      return i
    end
  end
  return 1
end

local function armFlag(value)
  return (value or 0) > ARM_HIGH_THRESHOLD
end

local function formatPath(index)
  return string.format("%s%03d%s", LOG_PREFIX, index, LOG_EXT)
end

local function fileWrite(handle, text)
  if STKLOG_TEST then
    handle:write(text)
  else
    io.write(handle, text)
  end
end

local function fileReadLine(handle)
  if STKLOG_TEST then
    return handle:read("*l")
  end
  return io.read(handle, "*l")
end

local function fileFlush(handle)
  if STKLOG_TEST and handle.flush then
    handle:flush()
  end
end

local function fileClose(handle)
  if STKLOG_TEST then
    handle:close()
  else
    io.close(handle)
  end
end

local function findFreePath(open_fn)
  open_fn = open_fn or io.open

  for index = 1, MAX_LOG_INDEX do
    local path = formatPath(index)
    local existing = open_fn(path, "r")
    if existing then
      fileClose(existing)
    else
      return path
    end
  end

  return nil
end

local function writeLine(line)
  if not file then
    return false
  end

  fileWrite(file, line)
  fileWrite(file, "\n")
  return true
end

local function timestamp(now_tick)
  return (now_tick - start_tick) * 10
end

local function openLog(now_tick, open_fn)
  local path = findFreePath(open_fn)
  if not path then
    last_error = "No free log name"
    return false
  end

  local handle = (open_fn or io.open)(path, "w")
  if not handle then
    last_error = "Cannot open " .. path
    return false
  end

  file = handle
  current_path = path
  start_tick = now_tick
  last_sample_tick = nil
  low_since_tick = nil
  sample_count = 0
  last_error = nil

  writeLine("kind,t_ms,roll,pitch,thr,yaw,arm")
  writeLine("start,0,,,,,1")
  return true
end

local function closeLog(now_tick)
  if file then
    writeLine(string.format("stop,%d,,,,,0", timestamp(now_tick)))
    fileFlush(file)
    fileClose(file)
  end

  file = nil
  state = "idle"
  low_since_tick = nil
  last_sample_tick = nil
end

local function sample(now_tick, arm, roll, pitch, thr, yaw)
  if not file then
    return
  end

  if last_sample_tick and (now_tick - last_sample_tick) < SAMPLE_INTERVAL_TICKS then
    return
  end

  last_sample_tick = now_tick
  sample_count = sample_count + 1

  writeLine(string.format(
    "sample,%d,%d,%d,%d,%d,%d",
    timestamp(now_tick),
    normalize(roll),
    normalize(pitch),
    normalize(thr),
    normalize(yaw),
    armFlag(arm) and 1 or 0
  ))

  if sample_count % 50 == 0 then
    fileFlush(file)
  end
end

local function step(now_tick, arm, roll, pitch, thr, yaw, stop_sec, open_fn)
  local armed = armFlag(arm)
  local stop_ticks = clamp(stop_sec or 60, 0, 120) * 100

  if state == "idle" then
    if armed then
      if openLog(now_tick, open_fn) then
        state = "recording"
      else
        return
      end
    else
      return
    end
  end

  if armed then
    low_since_tick = nil
    state = "recording"
  elseif state == "recording" then
    low_since_tick = now_tick
    state = "pending_stop"
  end

  sample(now_tick, arm, roll, pitch, thr, yaw)

  if state == "pending_stop" and low_since_tick and (now_tick - low_since_tick) >= stop_ticks then
    closeLog(now_tick)
  end
end

local function readSource(index)
  return getValue(channelName(index)) or 0
end

local function loggerLoop()
  local arm = readSource(cfg.arm)
  local roll = readSource(orderChannel("A"))
  local pitch = readSource(orderChannel("E"))
  local thr = readSource(orderChannel("T"))
  local yaw = readSource(orderChannel("R"))

  last_arm = arm
  last_values.roll = roll
  last_values.pitch = pitch
  last_values.thr = thr
  last_values.yaw = yaw

  step(getTime(), arm, roll, pitch, thr, yaw, cfg.stopSec)
end

local function saveConfig()
  local f = io.open(CONFIG_PATH, "w")
  if not f then
    last_error = "Cannot save config"
    return
  end

  fileWrite(f, string.format(
    "%d,%d,%d\n",
    cfg.arm,
    cfg.order,
    cfg.stopSec
  ))
  fileClose(f)
  config_dirty = false
end

local function loadConfig()
  local f = io.open(CONFIG_PATH, "r")
  if not f then
    return
  end

  local line = fileReadLine(f)
  fileClose(f)
  if not line then
    return
  end

  local values = {}
  for value in string.gmatch(line, "([^,]+)") do
    values[#values + 1] = tonumber(value)
  end

  cfg.arm = clamp(values[1] or cfg.arm, 1, 16)
  if #values >= 6 then
    cfg.order = 1
    cfg.stopSec = clamp(values[6] or cfg.stopSec, 0, 120)
    saveConfig()
  else
    cfg.order = clamp(values[2] or cfg.order, 1, #ORDER_NAMES)
    cfg.stopSec = clamp(values[3] or cfg.stopSec, 0, 120)
  end
end

local function itemText(item)
  if item.key == "stopSec" then
    return tostring(cfg.stopSec)
  end
  if item.key == "order" then
    return currentOrder()
  end
  return channelLabel(cfg[item.key])
end

local function changeItem(delta)
  local item = items[selected]
  if not item then
    return
  end

  if item.key == "stopSec" then
    cfg.stopSec = clamp(cfg.stopSec + delta, 0, 120)
  elseif item.key == "order" then
    cfg.order = cfg.order + delta
    if cfg.order < 1 then
      cfg.order = #ORDER_NAMES
    elseif cfg.order > #ORDER_NAMES then
      cfg.order = 1
    end
  else
    cfg[item.key] = clamp(cfg[item.key] + delta, 1, 16)
  end

  config_dirty = true
  saveConfig()
end

local function drawText(x, y, text, flags)
  lcd.drawText(x, y, text, flags or 0)
end

local function drawBox(x, y, size)
  lcd.drawRectangle(x, y, size, size)
  lcd.drawLine(x + size / 2, y + 2, x + size / 2, y + size - 3, DOTTED, FORCE)
  lcd.drawLine(x + 2, y + size / 2, x + size - 3, y + size / 2, DOTTED, FORCE)
end

local function stickPos(value, center, radius)
  return math.floor(center + normalize(value) * radius / 1000 + 0.5)
end

local function drawStick(x, y, size, x_value, y_value, label)
  local radius = size / 2 - 4
  local center_x = x + size / 2
  local center_y = y + size / 2
  local px = stickPos(x_value, center_x, radius)
  local py = stickPos(-y_value, center_y, radius)

  drawBox(x, y, size)
  lcd.drawFilledRectangle(px - 1, py - 1, 3, 3)
  drawText(x + 1, y + size + 1, label, SMLSIZE)
end

local function stateLabel()
  if last_error then
    return "Error"
  end
  if state == "recording" then
    return "Recording"
  end
  if state == "pending_stop" then
    return "Stopping"
  end
  if armFlag(last_arm) then
    return "Armed"
  end
  return "Waiting for arm"
end

local function drawStatusScreen()
  lcd.clear()
  drawText(1, 0, stateLabel(), INVERS)
  drawText(94, 0, currentOrder(), INVERS)

  drawStick(7, 13, 36, last_values.yaw, last_values.thr, "Y/T")
  drawStick(85, 13, 36, last_values.roll, last_values.pitch, "R/P")

  if state == "recording" or state == "pending_stop" then
    drawText(4, 56, current_path or "LOG", SMLSIZE)
  elseif last_error then
    drawText(4, 56, "ERR: open /LOGS", SMLSIZE + BLINK)
  else
    drawText(4, 56, "ENT cfg", SMLSIZE)
  end

  drawText(94, 56, "ARM " .. channelLabel(cfg.arm), SMLSIZE)
end

local function drawSettingsScreen()
  lcd.clear()
  drawText(1, 0, "Settings", INVERS)
  drawText(82, 0, "EXIT back", INVERS)

  local y = 11
  for i = 1, #items do
    local flags = 0
    if i == selected then
      flags = INVERS
    end
    drawText(2, y, items[i].label, flags)
    drawText(58, y, itemText(items[i]), flags)
    y = y + 9
  end

  local armed = armFlag(last_arm)
  local status = state
  if armed then
    status = status .. " arm"
  end
  drawText(1, 56, status, 0)

  if editing then
    drawText(82, 56, "EDIT", BLINK)
  elseif last_error then
    drawText(55, 56, "ERR", BLINK)
  else
    drawText(65, 56, "ENT edit")
  end
end

local function drawDisplay()
  if screen == "settings" then
    drawSettingsScreen()
  else
    drawStatusScreen()
  end
end

local function nextItem(delta)
  selected = selected + delta
  if selected < 1 then
    selected = #items
  elseif selected > #items then
    selected = 1
  end
end

local function isNextEvent(event)
  return event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT or event == EVT_ROT_RIGHT or event == EVT_PLUS_BREAK
end

local function isPrevEvent(event)
  return event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT or event == EVT_ROT_LEFT or event == EVT_MINUS_BREAK
end

local function run(event)
  loggerLoop()

  if screen == "status" then
    if event == EVT_ENTER_BREAK or event == EVT_MENU_BREAK then
      screen = "settings"
    elseif event == EVT_EXIT_BREAK then
      return -1
    end
    drawDisplay()
    return 0
  end

  if event == EVT_ENTER_BREAK then
    editing = not editing
    if not editing and config_dirty then
      saveConfig()
    end
  elseif event == EVT_EXIT_BREAK then
    if editing then
      editing = false
      if config_dirty then
        saveConfig()
      end
    else
      screen = "status"
    end
  elseif isNextEvent(event) then
    if editing then
      changeItem(1)
    else
      nextItem(1)
    end
  elseif isPrevEvent(event) then
    if editing then
      changeItem(-1)
    else
      nextItem(-1)
    end
  end

  drawDisplay()
  return 0
end

local function background()
  loggerLoop()
  return 0
end

local function init()
  loadConfig()
end

local function getStatus()
  return {
    state = state,
    path = current_path,
    error = last_error,
    cfg = cfg,
  }
end

if STKLOG_TEST then
  return {
    armFlag = armFlag,
    normalize = normalize,
    orderChannel = function(order_index, letter)
      local old_order = cfg.order
      cfg.order = order_index
      local result = orderChannel(letter)
      cfg.order = old_order
      return result
    end,
    step = step,
    getStatus = getStatus,
    constants = {
      SAMPLE_INTERVAL_TICKS = SAMPLE_INTERVAL_TICKS,
      ARM_HIGH_THRESHOLD = ARM_HIGH_THRESHOLD,
    },
  }
end

return { run = run, background = background, init = init }
