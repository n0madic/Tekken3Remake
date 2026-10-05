class_name ProgressCard
extends RefCounted
## The memory card the game uses (remake-plan.md#save-data-and-settings): one of two save files,
## as the PlayStation's two card slots (the setting `memory_card`), and the remake's saving rules
## on top of the game's own: AUTO SAVE starts on for a player with no save, and leaving OPTIONS
## saves the options when auto save is on (or was on in the file, so that turning it off lasts).
## The game itself saves only after statistics or unlock updates (modes.md#memory-card-file).
##
## A trace replay's card is fresh and never written; `--fresh` starts from a fresh card too (with
## the game's defaults, auto save off) and neither reads nor writes the save file. `--unlock` opens every
## character, costume and mode in memory only: what the game reads has them open, what it writes
## keeps the unlock state the card had (its save, or the defaults).

const CARDS := 2

var store := SaveStore.new()
var card := 1
var reads := true                         ## false: every card is fresh (`--fresh`, a replay)
var writes := true                        ## false: saves succeed without writing (`--fresh`, a replay)
var auto_save_default := true             ## AUTO SAVE on for a fresh card
var unlock_all := false                   ## `--unlock`: everything open for this session, never saved
var defaults := PackedByteArray()         ## the save data at power-on: a fresh card starts from it
var _saved := PackedByteArray()           ## what the card holds now (empty: no file)


static func path_for(number: int) -> String:
	return SaveStore.PROGRESS_PATHS[clampi(number, 1, CARDS) - 1]


## Uses card `number` (1 or 2) from now on.
func select(number: int) -> void:
	card = clampi(number, 1, CARDS)
	store.progress_path = path_for(card)
	_saved = PackedByteArray()


## The progress a fresh card starts from: the game's defaults, with AUTO SAVE on outside the tests.
func fresh_progress(progress: GameProgress) -> void:
	progress.load_save_data(defaults)
	if auto_save_default:
		progress.auto_save = 1
	if unlock_all:
		ProgressRules.open_all(progress)


## The card's save for the game's start-up read (GameFlow.card_loader); empty when there is none.
func read() -> PackedByteArray:
	_saved = store.load_progress() if reads else PackedByteArray()
	return _opened(_saved) if unlock_all and not _saved.is_empty() else _saved


## Writes the progress (OptionsScreen.save_writer, auto save); returns a memory card result.
func write(bytes: PackedByteArray) -> int:
	if not writes:
		return SaveStore.CARD_DONE
	if unlock_all:
		bytes = GameProgress.with_unlock_state(bytes, _saved if not _saved.is_empty() else defaults)
	var result := store.save_progress(bytes)
	if result == SaveStore.CARD_DONE:
		_saved = bytes
	return result


## Whether leaving OPTIONS saves: auto save is on, or the card still has it on.
func saves_options(progress: GameProgress) -> bool:
	return progress.auto_save != 0 or (not _saved.is_empty() and _saved[GameProgress.AUTO_SAVE] != 0)


## Changes to the current card's contents in place: a fresh progress, then its save if it has one.
func load_into(progress: GameProgress) -> void:
	fresh_progress(progress)
	var saved := read()
	if not saved.is_empty():
		progress.load_save_data(saved)


## The card's save as the game reads it with `--unlock`: everything open.
func _opened(saved: PackedByteArray) -> PackedByteArray:
	var progress := GameProgress.new()
	progress.load_save_data(saved)
	ProgressRules.open_all(progress)
	return progress.save_data()
