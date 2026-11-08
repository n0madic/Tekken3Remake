class_name ArcadeFlowData
extends RefCounted
## What the arcade's game flow reads from its program (`imported/tables/arcade_flow.json`,
## tools/remake_import/arcade_flow.py).

const FILE := "tables/arcade_flow.json"
const STAGE := "stage"
const MUSIC := "music"
const VOICE := "voice"
const NAME := "name"
const ENBU_EVENT := 5                     ## s16 values per event of the attract's script

## One entry of the day schedule (0x801FF648).
class Unlock:
	var day := 0
	var kind := 0
	var argument := 0


var roster: PackedInt32Array              ## 0x80179BA8: the select's characters in their order
var unlocks: Array[Unlock] = []
var demo_characters: PackedInt32Array     ## 0x801FF928
var characters: Array = []                ## by costume key: name, stage, music, voice, mokujin_bank
var alphabet := ""                        ## 0x80179678: the name entry's symbols
var rejected_names := PackedStringArray()
var select_state_anim: PackedInt32Array   ## 0x80179DF4: two values per player state
var select_decided: PackedInt32Array      ## 0x80179DE4: two values per player state
var select_default_cell: PackedInt32Array ## 0x80179B7C: the side's first cell
var select_spark_x: PackedInt32Array    ## 0x80179B58: per side, the portrait the sparks rise over
var select_spark_y: PackedInt32Array    ## 0x801FFAB0: per layout, where they start
var enbu_script: PackedInt32Array         ## 0x80186FF8: five s16 per event
var ogre_scripts: Array[PackedInt32Array] = []  ## 0x80187208, 0x8018723C: by the human's side
var record_wins: PackedInt32Array         ## 0x80179ED4: the characters of a fresh cabinet's versus records
var movie_frames := 0                     ## the attract movie's files, one per frame of 4 vblanks


static func load_from(path: String) -> ArcadeFlowData:
	var d: Dictionary = JsonFile.read(path)
	var out := ArcadeFlowData.new()
	out.roster = JsonFile.ints(d["roster"])
	for row: Array in d["unlocks"]:
		var u := Unlock.new()
		u.day = row[0]
		u.kind = row[1]
		u.argument = row[2]
		out.unlocks.append(u)
	out.demo_characters = JsonFile.ints(d["demo_characters"])
	out.characters = d["characters"]
	out.alphabet = d["alphabet"]
	var rejected: Array = d["rejected_names"]
	out.rejected_names = PackedStringArray(rejected)
	out.select_state_anim = JsonFile.ints(d["select_state_anim"])
	out.select_decided = JsonFile.ints(d["select_decided"])
	out.select_default_cell = JsonFile.ints(d["select_default_cell"])
	out.select_spark_x = JsonFile.ints(d["select_spark_x"])
	out.select_spark_y = JsonFile.ints(d["select_spark_y"])
	out.enbu_script = JsonFile.ints(d["enbu_script"])
	var ogre_scripts: Array = d["ogre_scripts"]
	for script: Array in ogre_scripts:
		out.ogre_scripts.append(JsonFile.ints(script))
	out.record_wins = JsonFile.ints(d["record_wins"])
	out.movie_frames = d["movie_frames"]
	return out


func character(key: int) -> Dictionary:
	return characters[key]


func stage_of(key: int) -> int:
	return JsonFile.number(character(key)[STAGE])


func music_of(key: int) -> int:
	return JsonFile.number(character(key)[MUSIC])


func voice_of(key: int) -> int:
	return JsonFile.number(character(key)[VOICE])


func name_of(key: int) -> String:
	return str(character(key)[NAME])
