class_name GameProgress
extends ByteBlock
## The game's progress at 0x800982D0 (modes.md#save-block, #records): the 72-byte save block,
## the flow globals after it (transition target, attract step, menu cursor, …), the 432-byte
## record block and the ranking's globals. The save file holds the save block and the records;
## the flow globals live for the session. Defaults come from the executable image.

const BASE := 0x800982D0
const SIZE := 0x218
const SAVE_BLOCK := 0x48
const RECORDS := 0x5C                  ## 0x8009832C
const RECORDS_SIZE := 0x1B0
const TIME_RECORDS := RECORDS          ## 22 × (u32 frames, char name[4])
const SURVIVORS := RECORDS + 0xB0      ## 10 × (u16 character, u16 wins, char name[4])
const STATS := RECORDS + 0x100         ## 22 × (plays, wins, losses, draws) u16
const CHARACTERS := 22
## The save block's byte ranges (offset, length) the unlock schedule writes or reads (ProgressRules):
## the unlocked characters and Start costumes with the arcade clears that open the Theater's movies
## and the schedule's steps, the last unlocked character, the play-count steps and counter, the
## unlock class and the two "new" counters. They lie in the block's first 0x48 bytes, which save
## data starts with.
const UNLOCK_STATE: Array[Vector2i] = [Vector2i(0x00, 16), Vector2i(0x22, 1), Vector2i(0x2A, 4), Vector2i(0x2F, 1),
	Vector2i(0x36, 2)]

var unlocked: int:                     ## +0x00: bit per character
	get: return u32(0x00)
	set(v): put32(0x00, v)
var start_costumes: int:               ## +0x04: characters with a Start costume (costume 2)
	get: return u32(0x04)
	set(v): put32(0x04, v)
var cleared: int:                      ## +0x08: arcade clears
	get: return u32(0x08)
	set(v): put32(0x08, v)
var cleared2: int:                     ## +0x0C: second clears (Panda, Tiger, Gun Jack)
	get: return u32(0x0C)
	set(v): put32(0x0C, v)
var play_frames: int:                  ## +0x10: vertical blanks since power-on (0x800982E0)
	get: return u32(0x10)
	set(v): put32(0x10, v)
const KEY_NO_USE := 12                 ## the key configuration's NO USE action
const SPEAKER_MONO := 0                ## SPEAKER OUT: MONO, STEREO
var speaker: int:                      ## +0x14 SPEAKER OUT
	get: return u8(0x14)
	set(v): put8(0x14, v)
var bgm: int:                          ## +0x15 BGM SELECT
	get: return u8(0x15)
	set(v): put8(0x15, v)
var difficulty: int:                   ## +0x16 DIFFICULTY LEVEL
	get: return u8(0x16)
	set(v): put8(0x16, v)
var fight_count: int:                  ## +0x17 FIGHT COUNT (rounds to win − 1)
	get: return u8(0x17)
	set(v): put8(0x17, v)
var round_time: int:                   ## +0x18 ROUND TIME
	get: return u8(0x18)
	set(v): put8(0x18, v)
var guard_damage: int:                 ## +0x19 GUARD DAMAGE
	get: return u8(0x19)
	set(v): put8(0x19, v)
var character_change: int:             ## +0x1A CHARACTER CHANGE AT CONTINUE
	get: return u8(0x1A)
	set(v): put8(0x1A, v)
var options_colour: int:               ## +0x1B the OPTION title's colour switch (0x800982EB)
	get: return u8(0x1B)
	set(v): put8(0x1B, v)
const AUTO_SAVE := 0x21
var auto_save: int:                    ## +0x21 AUTO SAVE
	get: return u8(AUTO_SAVE)
	set(v): put8(AUTO_SAVE, v)
var quick_select: int:                 ## +0x20 QUICK SELECT
	get: return u8(0x20)
	set(v): put8(0x20, v)
var new_character: int:                ## +0x22: the last unlocked character (22: none)
	get: return u8(0x22)
	set(v): put8(0x22, v)
var demo_position: int:                ## +0x23: the demonstration fight's character position
	get: return u8(0x23)
	set(v): put8(0x23, v)
var force_hi_score: int:               ## +0x24 (0x800982F4)
	get: return u32(0x24)
	set(v): put32(0x24, v)
var force_keys: int:                   ## +0x28
	get: return u8(0x28)
	set(v): put8(0x28, v)
var cursor_hold: int:                  ## +0x29 SELECT CURSOR HOLD
	get: return u8(0x29)
	set(v): put8(0x29, v)
var play_steps: int:                   ## +0x2A: unlock steps opened by playing
	get: return u8(0x2A)
	set(v): put8(0x2A, v)
var play_steps_seen: int:              ## +0x2B: the play count has reached 100 once
	get: return u8(0x2B)
	set(v): put8(0x2B, v)
var fights_since_unlock: int:          ## +0x2C (u16)
	get: return u16(0x2C)
	set(v): put16(0x2C, v)
var ball_played: int:                  ## +0x2E: the first single-player Tekken Ball game was played
	get: return u8(0x2E)
	set(v): put8(0x2E, v)
var unlock_class: int:                 ## +0x2F: 1 at 15 characters, 2 with Doctor B.
	get: return u8(0x2F)
	set(v): put8(0x2F, v)
var demo_number: int:                  ## +0x30 (0x80098300): the attract demonstration
	get: return u8(0x30)
	set(v): put8(0x30, v)
var ball_new: int:                     ## +0x36: TEKKEN BALL MODE's "new" counter
	get: return u8(0x36)
	set(v): put8(0x36, v)
var theater_new: int:                  ## +0x37: THEATER MODE's "new" counter
	get: return u8(0x37)
	set(v): put8(0x37, v)
var transition_target: int:            ## +0x48 (0x80098318)
	get: return u8(0x48)
	set(v): put8(0x48, v)
var previous_state: int:               ## +0x49
	get: return u8(0x49)
	set(v): put8(0x49, v)
var enbu_target: int:                  ## +0x4A
	get: return u8(0x4A)
	set(v): put8(0x4A, v)
var enbu_cached: int:                  ## +0x4B
	get: return u8(0x4B)
	set(v): put8(0x4B, v)
var screen_cached: int:                ## +0x4C: the screen overlay in memory (0 none)
	get: return u8(0x4C)
	set(v): put8(0x4C, v)
var card_read: int:                    ## +0x4D: the start-up memory card read has been done
	get: return u8(0x4D)
	set(v): put8(0x4D, v)
var attract_step: int:                 ## +0x4E (0x8009831E)
	get: return u8(0x4E)
	set(v): put8(0x4E, v)
var menu_cursor: int:                  ## +0x50 (0x80098320)
	get: return u8(0x50)
	set(v): put8(0x50, v)
var menu_to_options: int:              ## +0x51: the main menu opens on OPTION MODE
	get: return u8(0x51)
	set(v): put8(0x51, v)
var record_entry: int:                 ## +0x54 (0x80098324): the time record just set (its address)
	get: return u32(0x54)
	set(v): put32(0x54, v)
var survivor_entry: int:               ## +0x58 (0x80098328): the survivor entry just made (its address)
	get: return u32(0x58)
	set(v): put32(0x58, v)
var ranking_page: int:                 ## +0x20C (0x800984DC)
	get: return u8(0x20C)
	set(v): put8(0x20C, v)
var ranking_stage: int:                ## +0x20D: the ranking backdrop's stage cycle
	get: return u8(0x20D)
	set(v): put8(0x20D, v)
var name_entry: int:                   ## +0x20E: bit 0 time attack, bit 1 survival
	get: return u8(0x20E)
	set(v): put8(0x20E, v)
var entry_player: int:                 ## +0x20F
	get: return u8(0x20F)
	set(v): put8(0x20F, v)
var entry_character: int:              ## +0x210
	get: return u8(0x210)
	set(v): put8(0x210, v)


## The progress of a new game: the executable's image of the block.
static func defaults(image: PackedByteArray) -> GameProgress:
	var p := GameProgress.new(SIZE)
	p.bytes = image.duplicate()
	p.bytes.resize(SIZE)
	return p


func _init(size: int = SIZE) -> void:
	super(size)


## Controller setting of a player (+0x1C, passed to FUN_8002A3C0).
func controller(player: int) -> int:
	return u8(0x1C + player)


## The last character chosen by a player (+0x1E, 0x58: none).
func last_character(player: int) -> int:
	return u8(0x1E + player)


func set_last_character(player: int, key: int) -> void:
	put8(0x1E + player, key)


## A player's button layout: the action of L2, R2, L1, R1, △, ○, ✕, □ (+0x38).
func button_action(player: int, button: int) -> int:
	return u8(0x38 + 8 * player + button)


## Whether a button has an action in the key configuration (buttons 0–7: L2 R2 L1 R1 △ ○ ✕ □,
## the pad bits 1 << button).
func button_assigned(player: int, button: int) -> bool:
	return button_action(player, button) != KEY_NO_USE


func set_button_action(player: int, button: int, action: int) -> void:
	put8(0x38 + 8 * player + button, action)


# ---- records ----------------------------------------------------------------------------------

func time_record(character: int) -> int:
	return u32(TIME_RECORDS + 8 * character)


func set_time_record(character: int, frames: int) -> void:
	put32(TIME_RECORDS + 8 * character, frames)


func time_record_name(character: int) -> String:
	return _name(TIME_RECORDS + 8 * character + 4)


func survivor(rank: int) -> Vector2i:
	return Vector2i(u16(SURVIVORS + 8 * rank), u16(SURVIVORS + 8 * rank + 2))


func survivor_name(rank: int) -> String:
	return _name(SURVIVORS + 8 * rank + 4)


## A character's statistic: 0 plays, 1 wins, 2 losses, 3 draws.
func stat(character: int, which: int) -> int:
	return u16(STATS + 8 * character + 2 * which)


func set_stat(character: int, which: int, v: int) -> void:
	put16(STATS + 8 * character + 2 * which, v)


## FUN_80051948: a character's usage, plays + losses + draws.
func usage(character: int) -> int:
	return stat(character, 0) + stat(character, 2) + stat(character, 3)


## FUN_8004CEF0 (strcpy): a name into the record block, with its terminator.
func put_name(at: int, text: String) -> void:
	var raw := text.to_ascii_buffer()
	for k in raw.size():
		put8(at + k, raw[k])
	put8(at + raw.size(), 0)


func _name(at: int) -> String:
	var s := ""
	for k in 4:
		var c := u8(at + k)
		if c == 0:
			break
		s += char(c)
	return s


## The part the save file keeps: the save block and the records.
func save_data() -> PackedByteArray:
	return bytes.slice(0, SAVE_BLOCK) + bytes.slice(RECORDS, RECORDS + RECORDS_SIZE)


## Save data `data` with the unlock state of the save data `kept` (UNLOCK_STATE).
static func with_unlock_state(data: PackedByteArray, kept: PackedByteArray) -> PackedByteArray:
	var out := data.duplicate()
	for part in UNLOCK_STATE:
		for i in range(part.x, part.x + part.y):
			out[i] = kept[i]
	return out


func load_save_data(data: PackedByteArray) -> void:
	for i in SAVE_BLOCK:
		bytes[i] = data[i]
	for i in RECORDS_SIZE:
		bytes[RECORDS + i] = data[SAVE_BLOCK + i]
