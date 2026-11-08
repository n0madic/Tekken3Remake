class_name ArcadeProgress
extends RefCounted
## What the cabinet keeps between games (the EEPROM blocks of the table 0x8017992C): the day counter
## that opens the fighters, the time and versus records and the characters' play counts, and the
## roster the day gives (FUN_801BAE34).

const ROSTER_FIRST := 0x3FF             ## FUN_801B54BC: the ten originals
const UNLOCKABLE := 0x11FFFF            ## FUN_801B5424
const EXTRA_COSTUMES := 0x3A2           ## FUN_801B5468
const TIME_MASK := 0xFFFFFFF
const TIME_NONE := 359999               ## FUN_801C1634: a record at least this long is no record
const TIME_FIRST := 180000              ## FUN_801C2CDC: a fresh cabinet's records: fifty minutes…
const TIME_STEP := 3600                 ## … and one more per fighter of the first roster
const TIME_ROUNDS := 2 << 28            ## the record's rounds, the usual two
const NAME_LETTERS := 3                 ## FUN_801B8CD4
const COUNT_MAX := 0xFFFF               ## FUN_801B93E8: the play counts are u16
const COSTUME_KEYS := 4
const WINS_ROWS := 10
const KIND_WHO_IS_IT := 0
const KIND_COMING_SOON := 1
const KIND_UNLOCK := 2
const KIND_COSTUME := 3
const KIND_CLEAR := 4
## FUN_801B9608's counters of a game (0x8036EE36…3E) are the cabinet's book-keeping: not kept here.

## A row of the ranking: FUN_801B4D68's wins or a character's time.
class Row:
	var value := 0                      ## the time in frames with its flags, or the character
	var count := 0                      ## the wins, or the record's costume and side
	var name := ""


var day := 0                            ## 0x802F4B8C
var unlocked := ROSTER_FIRST            ## 0x8021FD60
var costumes := 0                       ## 0x8021FD6C
var who_is_it := Character.NONE                   ## 0x80273258: the demo's VS screen
var coming_soon := Character.NONE                 ## 0x80273254
var intruder := Character.NONE                    ## 0x80374F2D: FUN_801B5C28
var intruder_done := 0                  ## 0x80374F2C
var new_fighter := Character.NONE                 ## 0x80374F2F: FUN_801B7594
var plays := PackedInt32Array()         ## 0x8036EE40: per character (u16 × 4: picks, wins, losses, draws)
var times: Array[Row] = []              ## 0x80375034: per character
var wins: Array[Row] = []               ## 0x803750E4


func _init() -> void:
	plays.resize(Character.COUNT * 4)
	for i in Character.COUNT:
		times.append(Row.new())
	for i in WINS_ROWS:
		wins.append(Row.new())


## FUN_801C2CDC: a fresh cabinet's records (when the EEPROM's block is not valid): each named with
## the first letters of its character.
func reset_records(data: ArcadeFlowData) -> void:
	var time := TIME_FIRST
	for i in Character.COUNT:
		var row: Row = times[i]
		if ROSTER_FIRST >> i & 1 != 0:
			row.value = time | TIME_ROUNDS
			time += TIME_STEP
		else:
			row.value = TIME_NONE | TIME_ROUNDS
		row.name = short_name(data, i)
	for i in WINS_ROWS:
		var row: Row = wins[i]
		row.value = data.record_wins[i]
		row.count = ((WINS_ROWS - 1 - i) >> 1) + 1
		row.name = short_name(data, row.value)


## What the remake keeps of the cabinet's EEPROM between runs. The day stays out: it is not the
## players' (`--day`).
func saved_records() -> Dictionary:
	return {"plays": Array(plays), "times": _saved_rows(times), "wins": _saved_rows(wins)}


## Back from saved_records; what does not fit (no file, another version) leaves a fresh cabinet's.
func restore_records(saved: Dictionary) -> void:
	var saved_plays: Array = saved.get("plays", [])
	if saved_plays.size() == plays.size():
		plays = JsonFile.ints(saved_plays)
	var saved_times: Array = saved.get("times", [])
	var saved_wins: Array = saved.get("wins", [])
	_restore_rows(times, saved_times)
	_restore_rows(wins, saved_wins)


static func _saved_rows(rows: Array[Row]) -> Array:
	var out := []
	for row: Row in rows:
		out.append({"value": row.value, "count": row.count, "name": row.name})
	return out


static func _restore_rows(rows: Array[Row], saved: Array) -> void:
	if saved.size() != rows.size() or not saved.all(func(entry: Variant) -> bool: return entry is Dictionary):
		return
	for i in rows.size():
		var entry: Dictionary = saved[i]
		rows[i].value = JsonFile.number(entry.get("value", rows[i].value))
		rows[i].count = JsonFile.number(entry.get("count", rows[i].count))
		rows[i].name = str(entry.get("name", rows[i].name))


## FUN_801B8CD4: the first letters of a character's name.
static func short_name(data: ArcadeFlowData, character: int) -> String:
	return data.name_of(character * COSTUME_KEYS).left(NAME_LETTERS)


## FUN_801B93E8: a play count one more, up to a u16's largest.
func count_play(at: int) -> void:
	plays[at] = mini(plays[at] + 1, COUNT_MAX)


## FUN_801BAE34: the schedule up to the day, every time a game starts.
func apply_schedule(data: ArcadeFlowData) -> void:
	unlocked = ROSTER_FIRST
	costumes = 0
	_clear_candidates()
	for u: ArcadeFlowData.Unlock in data.unlocks:
		if day < u.day:
			break
		match u.kind:
			KIND_WHO_IS_IT:
				_vs_candidate(KIND_WHO_IS_IT, u.argument)
			KIND_COMING_SOON:
				_vs_candidate(KIND_COMING_SOON, u.argument)
				_set_intruder(u.argument)
			KIND_UNLOCK:
				_set_intruder(Character.NONE)
				new_fighter = mini(u.argument, Character.NONE)
				if u.argument < Character.NONE and (1 << u.argument) & UNLOCKABLE != 0:
					unlocked |= 1 << u.argument
			KIND_COSTUME:
				if u.argument < Character.NONE and (1 << u.argument) & EXTRA_COSTUMES & unlocked != 0:
					costumes |= 1 << u.argument
			KIND_CLEAR:
				_clear_candidates()


## FUN_801BADF4's candidates.
func _clear_candidates() -> void:
	who_is_it = Character.NONE
	coming_soon = Character.NONE
	_set_intruder(Character.NONE)
	new_fighter = Character.NONE


func _set_intruder(character: int) -> void:
	intruder = mini(character, Character.NONE)
	intruder_done = 0


## FUN_801B89C4.
func _vs_candidate(kind: int, character: int) -> void:
	var c := mini(character, Character.NONE)
	coming_soon = c if kind == KIND_COMING_SOON else Character.NONE
	who_is_it = c if kind == KIND_WHO_IS_IT else Character.NONE
