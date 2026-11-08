-- MAME autoboot script: what the arcade's sound CPU does, for verify_arcade_sound_vm.py. One event per line, in
-- emulated order:
--   T <time>     a write of the driver's clock (0xFFFDEA): a tick starts (or the boot's clear)
--   W <reg> <v>  a C352 register write (H8 0x280000 + 2·reg)
--   S <reg> <v>  a C352 register read, with what the chip answered
--   C <ofs> <v>  a word the main CPU (or this script) put in the shared RAM (H8 0x080000 + ofs)
--   R <ofs>      the H8 reads a word the main CPU wrote since the last tick: that write counts in this tick
--   F <frame>    a video frame ended
--
-- LOG_FILE      output (required)
-- LAST_FRAME    frames to run (default 3000)
-- INJECT_FILE   optional: "<frame> <ofs> <value>" lines (hex ofs and value), written at the frame's end
-- MUTE_MAIN     optional: from this frame on the main CPU's writes to the shared RAM have no effect
local log_path = assert(os.getenv("LOG_FILE"), "LOG_FILE")
local last_frame = tonumber(os.getenv("LAST_FRAME") or "3000")
local sub = manager.machine.devices[":sub"]
local main = manager.machine.devices[":maincpu"]
local h8 = sub.spaces["program"]
local r3000 = main.spaces["program"]
local mute_main = tonumber(os.getenv("MUTE_MAIN") or "0")
local out = io.open(log_path, "w")
local frame = 0
local pending = {}          -- shared words written and not yet known to be seen

local TIME_ADDRESS, C352_BASE, C352_LAST = 0xFFFDEA, 0x280000, 0x2807FF
local SHARED_BASE, SHARED_LAST = 0x080000, 0x0807FF
local MAIN_SHARED_BASE, MAIN_SHARED_LAST = 0x1F080000, 0x1F0807FF

local function shared_write(ofs, value)
  out:write(string.format("C %x %x\n", ofs, value))
  pending[ofs] = true
end

tap_time = h8:install_write_tap(TIME_ADDRESS, TIME_ADDRESS + 1, "time", function(offset, data, mask)
  out:write(string.format("T %x\n", data))
  pending = {}
  return data
end)
tap_chip_w = h8:install_write_tap(C352_BASE, C352_LAST, "c352w", function(offset, data, mask)
  out:write(string.format("W %x %x\n", (offset - C352_BASE) // 2, data))
  return data
end)
tap_chip_r = h8:install_read_tap(C352_BASE, C352_LAST, "c352r", function(offset, data, mask)
  out:write(string.format("S %x %x\n", (offset - C352_BASE) // 2, data))
  return data
end)
tap_shared_r = h8:install_read_tap(SHARED_BASE, SHARED_LAST, "sharedr", function(offset, data, mask)
  local ofs = (offset - SHARED_BASE) & 0xFFFE
  if pending[ofs] then
    out:write(string.format("R %x\n", ofs))
    pending[ofs] = nil
  end
  return data
end)
tap_main_w = r3000:install_write_tap(MAIN_SHARED_BASE, MAIN_SHARED_LAST, "mainw", function(offset, data, mask)
  if mute_main > 0 and frame >= mute_main then
    return r3000:read_u32(offset)
  end
  local ofs = offset - MAIN_SHARED_BASE
  if mask & 0xFFFF ~= 0 then
    shared_write(ofs, data & 0xFFFF)
  end
  if mask & 0xFFFF0000 ~= 0 then
    shared_write(ofs + 2, (data >> 16) & 0xFFFF)
  end
  return data
end)

local inject = {}
local inject_file = os.getenv("INJECT_FILE")
if inject_file then
  for line in io.lines(inject_file) do
    local t = {}
    for w in line:gmatch("%S+") do t[#t + 1] = w end
    if #t == 3 then
      local at = tonumber(t[1])
      inject[at] = inject[at] or {}
      table.insert(inject[at], {tonumber(t[2], 16), tonumber(t[3], 16)})
    end
  end
end

emu.register_frame_done(function()
  frame = frame + 1
  out:write(string.format("F %d\n", frame))
  for _, row in ipairs(inject[frame] or {}) do
    shared_write(row[1], row[2])
    h8:write_u16(SHARED_BASE + row[1], row[2])
  end
  if frame % 500 == 0 then out:flush() end
  if frame >= last_frame then
    out:close()
    manager.machine:exit()
  end
end)
