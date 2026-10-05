class_name AiTables
extends RefCounted
## The CPU opponent's tables (`imported/tables/ai.json`, tools/remake_import/ai.py; ai.md).
##
## Input scripts are lists of u16 steps (numpad direction in bits 0–3, buttons in bits 8–11):
## the first step is pressed when the script starts, the others on the following frames.

const GROUPS := 3
const LEVELS := 10

## The character hooks (ai.md#character-hooks): against the opponent's bank (A) or playing the
## CPU's own (B); IDLE hooks only return −1.
enum Hook { NONE, IDLE, VS_PAUL, AS_KING, VS_YOSHIMITSU, AS_HWOARANG, VS_OGRE, VS_GON }
## The converter's names (tools/remake_import/ai.py HOOK_NAMES).
const HOOK_NAMES := {
	"": Hook.NONE, "idle": Hook.IDLE, "vs_paul": Hook.VS_PAUL, "as_king": Hook.AS_KING,
	"vs_yoshimitsu": Hook.VS_YOSHIMITSU, "as_hwoarang": Hook.AS_HWOARANG, "vs_ogre": Hook.VS_OGRE,
	"vs_gon": Hook.VS_GON,
}


## The per-bank-type record at 0x80022F80.
class Bank:
	var counter := 0                            ## +0: the bank has counter moves (reactions 5)
	var parry_high := PackedInt32Array()        ## +4: parry script against mids and highs (kind 7)
	var parry_low := PackedInt32Array()         ## +8: against lows (kind 8)
	var setups: Array[Setup] = []               ## +0xC: the bank's setups


## A bank setup: a script started when its draw passes and a branch into `slot` is open.
class Setup:
	var chance := 0
	var slot := 0
	var steps := PackedInt32Array()


var params: Array[Array] = []                   ## [group][level] → 55 s16 words (AiLoadParams)
var band_thresholds: Array[PackedInt32Array] = []   ## per character id: 6 s16 (0x80098640)
var band_reach := PackedInt32Array()            ## per distance band: the reach bits allowed
var approach_reach := PackedInt32Array()        ## per reach band: reach bits that stop an approach
var numpad_pads := PackedInt32Array()           ## pad bits of numpad directions 0–9 (script steps)
var direction_masks := PackedInt32Array()       ## the command direction bit of numpad 0–9
var direction_pads := PackedInt32Array()        ## pad bits of numpad 0–9 (plain commands)
var button_pads := PackedInt32Array()           ## pad bits of command bits 0–3
var side_steps: Array[PackedInt32Array] = []    ## AiSideStep's scripts per side
var tap_forward := PackedInt32Array()           ## the script of command 0xC001
var tap_back := PackedInt32Array()              ## 0xC002
var back_dash := PackedInt32Array()             ## FUN_8005968C (0x80022EB2)
var wake_up := PackedInt32Array()               ## 0x80022E96
var king_throws: Array[PackedInt32Array] = []
var king_vs_crouch: Array[PackedInt32Array] = []
var king_ground: Array[PackedInt32Array] = []
var ogre_escapes := PackedInt32Array()          ## pads against the fire breath (0x80023308)
var actions := PackedInt32Array()               ## the neutral actions (0x800230E0)
var evasion_states := PackedInt32Array()        ## 0x800230EC
var hook_banks := PackedInt32Array()            ## AiHookForBank's table: bank type, hook A, hook B
var hooks_a := PackedInt32Array()               ## Hook
var hooks_b := PackedInt32Array()
var banks: Array[Bank] = []
var force_words := PackedInt32Array()           ## Tekken Force (M4)


static func load_from(path: String) -> AiTables:
	var d: Dictionary = JsonFile.read(path)
	var t := AiTables.new()
	for group: Array in d["params"]:
		var levels: Array[PackedInt32Array] = []
		for words: Array in group:
			levels.append(JsonFile.ints(words))
		t.params.append(levels)
	t.band_thresholds = FightTables._rows(d["band_thresholds"])
	t.band_reach = JsonFile.ints(d["band_reach"])
	t.approach_reach = JsonFile.ints(d["approach_reach"])
	t.numpad_pads = JsonFile.ints(d["numpad_pads"])
	t.direction_masks = JsonFile.ints(d["direction_masks"])
	t.direction_pads = JsonFile.ints(d["direction_pads"])
	t.button_pads = JsonFile.ints(d["button_pads"])
	t.side_steps = FightTables._rows(d["side_steps"])
	t.tap_forward = JsonFile.ints(d["tap_forward"])
	t.tap_back = JsonFile.ints(d["tap_back"])
	t.back_dash = JsonFile.ints(d["back_dash"])
	t.wake_up = JsonFile.ints(d["wake_up"])
	t.king_throws = FightTables._rows(d["king_throws"])
	t.king_vs_crouch = FightTables._rows(d["king_vs_crouch"])
	t.king_ground = FightTables._rows(d["king_ground"])
	t.ogre_escapes = JsonFile.ints(d["ogre_escapes"])
	t.actions = JsonFile.ints(d["actions"])
	t.evasion_states = JsonFile.ints(d["evasion_states"])
	for h: Array in d["hooks"]:
		t.hook_banks.append(JsonFile.number(h[0]))
		t.hooks_a.append(_hook_named(str(h[1])))
		t.hooks_b.append(_hook_named(str(h[2])))
	for b: Dictionary in d["banks"]:
		var bank := Bank.new()
		bank.counter = JsonFile.number(b["counter"])
		bank.parry_high = JsonFile.ints(b["parry_high"])
		bank.parry_low = JsonFile.ints(b["parry_low"])
		for s: Array in b["setups"]:
			var setup := Setup.new()
			setup.chance = JsonFile.number(s[0])
			setup.slot = JsonFile.number(s[1])
			setup.steps = JsonFile.ints(s[2])
			bank.setups.append(setup)
		t.banks.append(bank)
	t.force_words = JsonFile.ints(d["force_words"])
	return t


## The difficulty words of a group and level, clamped as unsigned values (AiLoadParams).
func words(group: int, level: int) -> PackedInt32Array:
	var levels: Array = params[mini(group & 0xFFFFFFFF, GROUPS - 1)]
	return levels[mini(level & 0xFFFFFFFF, LEVELS - 1)]


## AiHookForBank (0x80062B50): hook A (the opponent's bank) or B (the CPU's own).
func hook(bank_type: int, own: bool) -> Hook:
	for k in hook_banks.size():
		if hook_banks[k] == bank_type:
			return (hooks_b[k] if own else hooks_a[k]) as Hook
	return Hook.NONE


static func _hook_named(hook_name: String) -> Hook:
	if not HOOK_NAMES.has(hook_name):
		Log.error("AiTables: unknown hook \"%s\" (reconvert the disc)" % hook_name)
		return Hook.NONE
	return HOOK_NAMES[hook_name] as Hook


func bank(bank_type: int) -> Bank:
	return banks[bank_type] if bank_type >= 0 and bank_type < banks.size() else Bank.new()
