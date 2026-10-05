class_name GameRam
extends RefCounted
## The game's memory as the screens' drawing reads it (their ports read tables, strings and
## state by address, as `tools/research/*_sim.py` do): the live byte blocks of the remake's screens
## first (a screen context, the progress block, the mode region), then the loaded overlays, then
## the executable, whose image spans the overlay slots (`imported/screens/ram/`, converted by
## `tools/remake_import/screen_vram.py`). The images are in Japan Rev.1's layout whichever release
## was converted; a text of another release that does not fit there is kept aside by address
## (`ram.json` "strings"). Strings read from the executable and the overlays are shown through the
## text locale (English when on, TextLocale).

class Block:
	extends RefCounted
	var name := ""                   ## the executable's or overlay's name ("" for a live block)
	var base := 0
	var bytes: PackedByteArray
	var live: ByteBlock              ## a remake block read in place (its `bytes` change)
	var strings: Dictionary = {}     ## address → text kept aside (another release's, too long to fit)

	func size() -> int:
		return live.bytes.size() if live != null else bytes.size()

	func data() -> PackedByteArray:
		return live.bytes if live != null else bytes


const MAX_STRING := 256

var blocks: Array[Block] = []        ## searched in order: the live blocks, then the overlays
var exe: Block                       ## searched last: the executable's image spans the overlay slots
var _files: Dictionary = {}          ## overlay name → Block
var directory := ""
var locale: TextLocale               ## null: the Japanese release's texts
var _shown: Dictionary = {}          ## address → string() of an image block (not live), as last localized
var _shown_locale: TextLocale        ## the locale and English flag _shown was made with
var _shown_english := false


static func load_from(dir: String) -> GameRam:
	var ram := GameRam.new()
	ram.directory = dir
	var index: Dictionary = JsonFile.read(dir.path_join("ram.json"))
	for name: String in index:
		var entry: Dictionary = index[name]
		var b := Block.new()
		b.name = name
		b.base = JsonFile.number(entry["base"])
		b.bytes = FileAccess.get_file_as_bytes(dir.path_join(str(entry["file"])))
		var aside: Dictionary = entry.get("strings", {})
		for key: String in aside:
			b.strings[key.to_int()] = str(aside[key])
		ram._files[name] = b
	ram.exe = ram._files["exe"]
	return ram


## Another view of the same memory images (shared, not re-read) with no live block or overlay.
func fresh() -> GameRam:
	var ram := GameRam.new()
	ram.directory = directory
	ram._files = _files
	ram.exe = exe
	return ram


## An overlay in its slot (the previous occupant of the same slot is dropped).
func load_overlay(name: String) -> void:
	var b: Block = _files.get(name)
	if b == null:
		return
	for i in range(blocks.size() - 1, -1, -1):
		if blocks[i].live == null and blocks[i].base == b.base:
			blocks.remove_at(i)
	blocks.append(b)
	_shown.clear()


## Takes a mapped byte block out of the search (a resident screen's context that shares an
## overlay slot: the quick select's at 0x800B9378 only while it is shown).
func unmap(block: ByteBlock) -> void:
	for i in range(blocks.size() - 1, -1, -1):
		if blocks[i].live == block:
			blocks.remove_at(i)
			_shown.clear()


## A remake byte block read at its game address (first in the search).
func map(base: int, block: ByteBlock) -> void:
	for other in blocks:
		if other.live == block:
			return
	var b := Block.new()
	b.base = base
	b.live = block
	blocks.push_front(b)
	_shown.clear()


func _find(address: int, size: int) -> Block:
	address &= 0xFFFFFFFF
	for b in blocks:
		if address >= b.base and address + size <= b.base + b.size():
			return b
	if exe != null and address >= exe.base and address + size <= exe.base + exe.size():
		return exe
	return null


func u8(address: int) -> int:
	var b := _find(address, 1)
	return 0 if b == null else b.data()[(address & 0xFFFFFFFF) - b.base]


func s8(address: int) -> int:
	return Fx.s8(u8(address))


func u16(address: int) -> int:
	var b := _find(address, 2)
	return 0 if b == null else b.data().decode_u16((address & 0xFFFFFFFF) - b.base)


func s16(address: int) -> int:
	return Fx.s16(u16(address))


func u32(address: int) -> int:
	var b := _find(address, 4)
	return 0 if b == null else b.data().decode_u32((address & 0xFFFFFFFF) - b.base)


func s32(address: int) -> int:
	return Fx.w32(u32(address))


## A zero-terminated string (at most MAX_STRING bytes, within the block it starts in), localized
## by that block.
func string(address: int) -> String:
	address &= 0xFFFFFFFF
	var english := locale != null and locale.english
	if locale != _shown_locale or english != _shown_english:
		_shown.clear()
		_shown_locale = locale
		_shown_english = english
	if _shown.has(address):
		return _shown[address] as String
	var b := _find(address, 1)
	if b == null:
		return ""
	var s: String = b.strings.get(address, "")
	if s.is_empty():
		var data := b.data()
		var start := address - b.base
		var end := data.find(0, start)
		end = mini(data.size() if end < 0 else end, start + MAX_STRING)
		s = data.slice(start, end).get_string_from_ascii()
	if english and not b.name.is_empty():
		s = locale.text(b.name, s)
	if b.live == null:
		_shown[address] = s
	return s


## `n` bytes from `address`.
func bytes(address: int, n: int) -> PackedByteArray:
	var a := address & 0xFFFFFFFF
	# The first block the range touches (as u8 searches) gives it all when it holds it all.
	for b: Block in blocks + [exe]:
		if b != null and a < b.base + b.size() and a + n > b.base:
			if a >= b.base and a + n <= b.base + b.size():
				return b.data().slice(a - b.base, a - b.base + n)
			break
	# Across blocks or partly unmapped (0): byte by byte.
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		out[i] = u8(address + i)
	return out
