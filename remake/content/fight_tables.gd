class_name FightTables
extends RefCounted
## The executable's tables the fight simulation uses, converted into `imported/tables/`
## (`fight.json`, with the sine, square-root and arctangent tables of `pose.json` and
## `camera.json`, the per-costume tables of `fighter.json` and the CPU's `ai.json`). Meanings: moves.md, combat.md.

const REACTION_WORDS := 21

var sin_table: PackedInt32Array          ## g_sinTable (4096 + 1024 entries; cos from 1024 on)
var atan: PackedInt32Array               ## Atan2Angle's u8 octant table
var square_root: PackedInt32Array        ## FUN_8004B174's mantissas
var fighter: FighterTables
var pose: PoseTables
var common_branches: Array[PackedInt32Array] = []   ## rows as MotionBank.branches
var sequences_a: Array[PackedInt32Array] = []       ## window, steps… (commands 0xC00E–0xC04C)
var sequences_b: Array[PackedInt32Array] = []       ## commands 0xC7FF–0xC827
var builtin_attack_ids := PackedInt32Array()        ## ids of the 13 built-in attack descriptors
var builtin_attack_offsets := PackedInt32Array()    ## their offsets in `builtin_blob`
var builtin_blob := PackedByteArray()               ## the descriptors and the bytes after them
var air_kinds: Array[PackedInt32Array] = []         ## (ground offset, air move slot)
var push := PackedInt32Array()                      ## push tables: frames, speed, 8 offsets
var launch_push := PackedInt32Array()
var reactions: Array[PackedInt32Array] = []         ## 21 s16 per record
var forced_reaction := PackedInt32Array()
var throw_victim_slots := PackedInt32Array()
var close_reactions: Array[PackedInt32Array] = []   ## (reaction, distance)
var face_attack := PackedInt32Array()
var face_hit := PackedInt32Array()
var hurt_zone_joints := PackedInt32Array()
var body_sphere_joints := PackedInt32Array()
var hurt_radii: Array[PackedInt32Array] = []        ## per character, 14 radii
var body_radii: Array[PackedInt32Array] = []        ## per character, 8 body sphere radii
var camera: CameraTables
var health := PackedInt32Array()
var recovery_team := PackedInt32Array()      ## FUN_80051AD4: the team winner's recovery (1/256 of full) by eighths left
var recovery_survival := PackedInt32Array()  ## by the survival fight's time (300-frame steps)
var reversal_lists: Array[PackedInt32Array] = []    ## animation tags (reversal condition 0x4B)
var directions: Array[PackedInt32Array] = []        ## per side: pad direction bits of numpad 1–9
var shake_scripts: Array[PackedInt32Array] = []     ## camera shake pitch offsets, −128 ends
var characters: Array[Dictionary] = []              ## per costume key: name, voice_set, bank, stage, music
var sound_codes := PackedInt32Array()               ## g_soundTable: sound code per 12-bit sound id
var sound_scripts: Array[PackedInt32Array] = []     ## frame | type << 12 | code << 16, frame 0 ends
var voices: Array[VoiceSet] = []                    ## g_charVoices per voice set
var impact_voices := PackedInt32Array()             ## FUN_80041ED8
var round_voices := PackedInt32Array()              ## FUN_8003DCE0: "ROUND n" by round number
var result_voices := PackedInt32Array()             ## FUN_8003E158: 0x8009749A, by round result
var strike_sounds := PackedInt32Array()             ## FUN_80041F4C
var special_sounds := PackedInt32Array()            ## FUN_80041C48 case 3
var effects := EffectTables.new()
var vibration := VibrationTables.new()
var ai: AiTables


## The effect objects' tables (effects.md#effect-objects).
class EffectTables:
	var breath_offsets: Array[Array] = []    ## per player: two (x, y, z) from the head joint
	var flame_offsets: Array[PackedInt32Array] = []
	var cloud_offsets: Array[PackedInt32Array] = []
	var gas_offsets: Array[PackedInt32Array] = []
	var burn_joints := PackedInt32Array()
	var gas_times: Array[PackedInt32Array] = []     ## (frame, speed, height)
	var glow_joints := PackedInt32Array()           ## per descriptor joint: the glow joint
	var hand_offsets: Array[Array] = []             ## per character: glow offsets of joints 6, 10
	var segment_frames: Dictionary = {}             ## name → u8 per frame (0: segment off)
	var mokujin_sounds: Array[PackedInt32Array] = []   ## (sound id, replacement code)


## PadVibrate's patterns (sound.md#vibration).
class VibrationTables:
	var slots := PackedInt32Array()             ## per pattern: its queue slot 0–3
	var pulses := PackedInt32Array()            ## small-motor pulse mask per level (bit = frame & 7)
	var small: Array[PackedInt32Array] = []     ## per pattern: small-motor script steps
	var large: Array[PackedInt32Array] = []     ## per pattern: large-motor script steps


## A g_charVoices record (sound.md#character-voices).
class VoiceSet:
	var counts := PackedInt32Array()       ## voices per category (ids 0x2nnn–0x5nnn)
	var voices := PackedInt32Array()       ## the sound codes of all categories in order
	var shouts := PackedInt32Array()       ## attack shout voice ids
	var damage_counts := PackedInt32Array()   ## light, heavy
	var damage := PackedInt32Array()       ## damage voice ids: light, then heavy
	var cooldown := 0
	var ids := PackedInt32Array()          ## five more sound ids (+0x0E)


static func load_from(folder: String) -> FightTables:
	var t := FightTables.new()
	t.pose = PoseTables.load_from(folder.path_join("pose.json"))
	t.fighter = FighterTables.load_from(folder.path_join("fighter.json"))
	t.sin_table = t.pose.sin_table
	var camera: Dictionary = JsonFile.read(folder.path_join("camera.json"))
	t.atan = JsonFile.ints(camera["atan"])
	var d: Dictionary = JsonFile.read(folder.path_join("fight.json"))
	t.square_root = JsonFile.ints(d["square_root"])
	t.common_branches = _rows(d["common_branches"])
	t.sequences_a = _rows(d["sequences_a"])
	t.sequences_b = _rows(d["sequences_b"])
	for entry: Array in d["builtin_attacks"]:
		var pair := JsonFile.ints(entry)
		t.builtin_attack_ids.append(pair[0])
		t.builtin_attack_offsets.append(pair[1])
	var blob: Array = d["builtin_blob"]
	t.builtin_blob = PackedByteArray(blob)
	t.air_kinds = _rows(d["air_kinds"])
	t.push = JsonFile.ints(d["push"])
	t.launch_push = JsonFile.ints(d["launch_push"])
	t.reactions = _rows(d["reactions"])
	t.forced_reaction = JsonFile.ints(d["forced_reaction"])
	t.throw_victim_slots = JsonFile.ints(d["throw_victim_slots"])
	t.close_reactions = _rows(d["close_reactions"])
	t.face_attack = JsonFile.ints(d["face_attack"])
	t.face_hit = JsonFile.ints(d["face_hit"])
	t.hurt_zone_joints = JsonFile.ints(d["hurt_zone_joints"])
	t.body_sphere_joints = JsonFile.ints(d["body_sphere_joints"])
	t.hurt_radii = _rows(d["hurt_radii"])
	t.body_radii = _rows(d["body_radii"])
	t.camera = CameraTables.load_from(folder.path_join("camera.json"))
	t.health = JsonFile.ints(d["health"])
	t.recovery_team = JsonFile.ints(d["recovery_team"])
	t.recovery_survival = JsonFile.ints(d["recovery_survival"])
	t.reversal_lists = _rows(d["reversal_lists"])
	t.directions = _rows(d["directions"])
	t.shake_scripts = _rows(d["shake_scripts"])
	for c: Dictionary in d["characters"]:
		t.characters.append(c)
	t.sound_codes = JsonFile.ints(d["sound_codes"])
	t.sound_scripts = _rows(d["sound_scripts"])
	for v: Dictionary in d["voices"]:
		var s := VoiceSet.new()
		s.counts = JsonFile.ints(v["counts"])
		s.voices = JsonFile.ints(v["voices"])
		s.shouts = JsonFile.ints(v["shouts"])
		s.damage_counts = JsonFile.ints(v["damage_counts"])
		s.damage = JsonFile.ints(v["damage"])
		s.cooldown = JsonFile.number(v["cooldown"])
		s.ids = JsonFile.ints(v["ids"])
		t.voices.append(s)
	t.impact_voices = JsonFile.ints(d["impact_voices"])
	t.round_voices = JsonFile.ints(d["round_voices"])
	var vib: Dictionary = d["vibration"]
	t.vibration.slots = JsonFile.ints(vib["slots"])
	t.vibration.pulses = JsonFile.ints(vib["pulses"])
	for pattern: Array in vib["patterns"]:
		t.vibration.small.append(JsonFile.ints(pattern[0]))
		t.vibration.large.append(JsonFile.ints(pattern[1]))
	t.result_voices = JsonFile.ints(d["result_voices"])
	t.strike_sounds = JsonFile.ints(d["strike_sounds"])
	t.special_sounds = JsonFile.ints(d["special_sounds"])
	var e: Dictionary = d["effects"]
	for pair: Array in e["breath_offsets"]:
		t.effects.breath_offsets.append(_rows(pair))
	t.effects.flame_offsets = _rows(e["flame_offsets"])
	t.effects.cloud_offsets = _rows(e["cloud_offsets"])
	t.effects.gas_offsets = _rows(e["gas_offsets"])
	t.effects.burn_joints = JsonFile.ints(e["burn_joints"])
	t.effects.gas_times = _rows(e["gas_times"])
	t.effects.glow_joints = JsonFile.ints(e["glow_joints"])
	for pair: Array in e["hand_offsets"]:
		t.effects.hand_offsets.append(_rows(pair))
	var frames: Dictionary = e["segment_frames"]
	for name: String in frames:
		t.effects.segment_frames[name] = JsonFile.ints(frames[name])
	t.effects.mokujin_sounds = _rows(e["mokujin_sounds"])
	t.ai = AiTables.load_from(folder.path_join("ai.json"))
	return t


static func _rows(value: Variant) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for row: Array in value:
		out.append(JsonFile.ints(row))
	return out


## FUN_800364E8 / FUN_80036518: a per-costume face shape, 0 beyond the tables.
func face_shape(table: PackedInt32Array, slot: int) -> int:
	return table[slot] if slot >= 0 and slot < table.size() else 0


## The push values of push-table entry `index` (an s16 index): frames, speed, then offsets.
func push_entry(index: int) -> PackedInt32Array:
	return push.slice(index, index + 10)


func character(key: int) -> Dictionary:
	return characters[mini(key, characters.size() - 1)]
