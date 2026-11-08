-- MAME autoboot script: a snapshot of every frame while the attract movie shows, with the game's
-- words at that frame (tools/research/verify_arcade_movie.py reads its log). The snapshots contain
-- game data: keep them under work/.
local space = manager.machine.devices[":maincpu"].spaces["program"]
local STATE, SUB, TIMER, PICTURE, ATTRACT_STEP = 0x8021FD20, 0x8021FD64, 0x8021FD4C, 0x8021F288, 0x8021F231
local FILE_INDEX, MAIN_FRAME, VBLANKS = 0x8021F8CC, 0x8021FD58, 0x8021F278
local ATTRACT, MOVIE, MOVIE_STEP, SUB_MOVIE_LAST, FRAMES_AFTER = 2, 1, 0, 2, 16
local LAST = tonumber(os.getenv("FLOW_LAST") or "12000")
local log = io.open(os.getenv("FLOW_LOG") or "movie.log", "w")
local n, snaps, after, seen = 0, 0, 0, false
emu.register_frame_done(function()
  n = n + 1
  local state, sub = space:read_u16(STATE), space:read_u16(SUB)
  local picture = space:read_u16(PICTURE)
  local shown = state == ATTRACT and (picture == MOVIE or (sub <= SUB_MOVIE_LAST and space:read_u8(ATTRACT_STEP) == MOVIE_STEP))
  if shown then
    after, seen = FRAMES_AFTER, true
  elseif after > 0 then
    after = after - 1
  end
  if shown or after > 0 then
    manager.machine.video:snapshot()
    log:write(string.format("%d snap=%04d state=%d sub=%d timer=%d pic=%d index=%d frame=%d vbl=%d\n", n, snaps, state, sub,
      space:read_u32(TIMER), picture, space:read_u32(FILE_INDEX), space:read_u32(MAIN_FRAME), space:read_u32(VBLANKS)))
    log:flush()
    snaps = snaps + 1
  end
  if n >= LAST or (seen and not shown and after == 0) then manager.machine:exit() end
end)
