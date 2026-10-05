class_name ScriptedFighter
extends RefCounted
## A fighter driven by a scene script (the Enbu event format, modes.md#enbu-attract-demonstration):
## the runner record of `enbu.ovl` (`0x8010C43C + 10·i`: state, costume, move slot, end frame,
## frame) around the fighter's own state.

enum State {
	IDLE,          ## 0: nothing runs; the fighter is not drawn
	MOVE,          ## 1: the move advances one pose frame per frame
	RELOAD_WAIT,   ## 2: a costume change counts down
	RELOAD_START,  ## 3
	RELOAD_LOAD,   ## 4: load the model's members
	RELOAD_MODEL,  ## 5: set up the model (the new costume is drawn from here on)
	RELOAD_PARTS,  ## 6: set up the parts
}

const RELOAD_DELAY := 2

var fighter := FighterState.new()
var state := State.IDLE
var costume := 0
var slot := 0
var end_frame := 0
var frame := 0
var drawn := false             ## the fighter was animated (and drawn) this frame
var model_costume := 0         ## the costume slot whose model the fighter shows
var skeleton: FighterSkeleton  ## joints of the last animated frame
var stick_shown := true        ## part 18's draw flag (FighterBody.stick_shown)
