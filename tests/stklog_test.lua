SOURCE = 0
VALUE = 1
STKLOG_TEST = true

local function loadLogger()
  return dofile("SCRIPTS/TOOLS/stklog.lua")
end

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(value, message)
  if not value then
    error(message, 2)
  end
end

local function newFs()
  local fs = {
    files = {},
    opened = {},
  }

  local function open(path, mode)
    if mode == "r" then
      if not fs.files[path] then
        return nil
      end
    elseif mode == "w" then
      fs.files[path] = {}
      fs.opened[#fs.opened + 1] = path
    else
      error("unsupported mode " .. tostring(mode))
    end

    local handle = {
      path = path,
      closed = false,
    }

    function handle:write(value)
      fs.files[path][#fs.files[path] + 1] = value
    end

    function handle:read()
      local parts = fs.files[path]
      local line = ""
      for _, part in ipairs(parts or {}) do
        if part == "\n" then
          return line
        end
        line = line .. part
      end
      if line ~= "" then
        return line
      end
      return nil
    end

    function handle:flush()
      self.flushed = true
    end

    function handle:close()
      self.closed = true
    end

    return handle
  end

  return fs, open
end

local function lines(fs, path)
  local parts = fs.files[path]
  local result = {}
  local current = ""

  for _, part in ipairs(parts or {}) do
    if part == "\n" then
      result[#result + 1] = current
      current = ""
    else
      current = current .. part
    end
  end

  return result
end

local function testNormalize()
  local logger = loadLogger()

  assertEqual(logger.normalize(1024), 1000, "1024 normalizes to 1000")
  assertEqual(logger.normalize(-1024), -1000, "-1024 normalizes to -1000")
  assertEqual(logger.normalize(512), 500, "512 normalizes to 500")
  assertEqual(logger.normalize(-512), -500, "-512 normalizes to -500")
  assertEqual(logger.normalize(0), 0, "0 normalizes to 0")
  assertEqual(logger.normalize(2048), 1000, "normalization clamps high")
  assertEqual(logger.normalize(-2048), -1000, "normalization clamps low")
end

local function testOrderMapping()
  local logger = loadLogger()

  assertEqual(logger.orderChannel(1, "A"), 1, "AETR maps A to CH1")
  assertEqual(logger.orderChannel(1, "E"), 2, "AETR maps E to CH2")
  assertEqual(logger.orderChannel(1, "T"), 3, "AETR maps T to CH3")
  assertEqual(logger.orderChannel(1, "R"), 4, "AETR maps R to CH4")

  assertEqual(logger.orderChannel(2, "T"), 1, "TAER maps T to CH1")
  assertEqual(logger.orderChannel(2, "A"), 2, "TAER maps A to CH2")
  assertEqual(logger.orderChannel(2, "E"), 3, "TAER maps E to CH3")
  assertEqual(logger.orderChannel(2, "R"), 4, "TAER maps R to CH4")

  assertEqual(logger.orderChannel(3, "R"), 1, "RETA maps R to CH1")
  assertEqual(logger.orderChannel(3, "E"), 2, "RETA maps E to CH2")
  assertEqual(logger.orderChannel(3, "T"), 3, "RETA maps T to CH3")
  assertEqual(logger.orderChannel(3, "A"), 4, "RETA maps A to CH4")
end

local function testStartAndStopAfterConfiguredDelay()
  local logger = loadLogger()
  local fs, open = newFs()

  logger.step(100, 1024, 0, 0, -1024, 0, 30, open)
  logger.step(102, 1024, 100, 200, -1024, -200, 30, open)
  logger.step(104, -1024, 100, 200, -1024, -200, 30, open)
  logger.step(3103, -1024, 100, 200, -1024, -200, 30, open)
  assertEqual(logger.getStatus().state, "pending_stop", "still pending before 30 seconds")
  logger.step(3104, -1024, 100, 200, -1024, -200, 30, open)
  assertEqual(logger.getStatus().state, "idle", "stops after 30 seconds low")

  local path = fs.opened[1]
  local log_lines = lines(fs, path)
  assertEqual(log_lines[1], "kind,t_ms,roll,pitch,thr,yaw,arm", "writes header")
  assertEqual(log_lines[2], "start,0,,,,,1", "writes start marker")
  assertEqual(log_lines[#log_lines], "stop,30040,,,,,0", "writes stop marker")
end

local function testRearmContinuesSameFile()
  local logger = loadLogger()
  local fs, open = newFs()

  logger.step(5000, 1024, 0, 0, 0, 0, 60, open)
  logger.step(5002, -1024, 0, 0, 0, 0, 60, open)
  logger.step(5010, 1024, 0, 0, 0, 0, 60, open)
  logger.step(5012, 1024, 0, 0, 0, 0, 60, open)

  assertEqual(#fs.opened, 1, "rearm keeps same file")
  assertEqual(logger.getStatus().state, "recording", "returns to recording")
end

local function testStopSecZero()
  local logger = loadLogger()
  local fs, open = newFs()

  logger.step(8000, 1024, 0, 0, 0, 0, 0, open)
  logger.step(8002, -1024, 0, 0, 0, 0, 0, open)

  assertEqual(logger.getStatus().state, "idle", "StopSec 0 closes immediately after low sample")
  local log_lines = lines(fs, fs.opened[1])
  assertEqual(log_lines[#log_lines], "stop,20,,,,,0", "immediate stop marker")
end

local function testOpenFailure()
  local logger = loadLogger()

  local function open()
    return nil
  end

  logger.step(10000, 1024, 0, 0, 0, 0, 60, open)
  assertEqual(logger.getStatus().state, "idle", "open failure leaves logger idle")
  assertTrue(logger.getStatus().error ~= nil, "open failure records error")
end

testNormalize()
testOrderMapping()
testStartAndStopAfterConfiguredDelay()
testRearmContinuesSameFile()
testStopSecZero()
testOpenFailure()

print("ok")
