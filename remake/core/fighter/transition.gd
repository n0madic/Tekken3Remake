class_name Transition
## Move transition codes (moves.md#transition-codes): the low six bits of a branch row's flags,
## or the code a reaction, throw or collapse starts its move with. `MoveSystem` sets the frames,
## facing and tracking of the new move by it; `TransitionRemap` rewrites some before they are
## stored (`FightMath.transition_remap`).

enum {
	FACE_OPPONENT = 0,          ## restart, heading = facing = direction to the opponent
	CONTINUE_FACING = 1,        ## continue, facing = heading
	CONTINUE = 2,               ## continue (becomes CONTINUE_TRACK_SLOW into an active window)
	CONTINUE_FIXED = 3,         ## continue, never remapped
	HOLD_TURN = 4,              ## hold the pose for the branch window, timed turn to the opponent
	HOLD_TRACK = 5,             ## hold the pose for the branch window, slow tracking
	RESTART = 6,
	REVERSE = 7,                ## start at the last frame and play backwards
	REWIND = 8,                 ## one frame back and play backwards
	TRACK_FAST = 9,
	TURN = 10,                  ## restart with a timed turn, facing = heading
	TURN_AIM = 11,              ## restart with a timed turn, facing = aimDir
	TRACK_SLOW = 12,
	TRACK_HALF = 13,
	TRACK = 14,
	TRACK_AIM = 15,
	SLIDE = 16,                 ## restart, timed turn, slide to the opponent
	SWAP = 17,                  ## swap the move only
	SLIDE_CONTINUE = 18,
	SLIDE_TURNED = 19,          ## turned 180° first, then as SLIDE_CONTINUE
	CONTINUE_TRACK_SLOW = 20,
	CONTINUE_TRACK = 21,
	CONTINUE_EASE = 22,
	APPROACH = 23,
	EASE = 24,
	CONTINUE_EASE_TURNING = 25, ## as CONTINUE_EASE, keeping a running timed turn (becomes
	                            ## CONTINUE_EASE into an active window)
	STEP = 26,
	STEP_CROUCH = 27,           ## also counts as crouching for hit tests
	SIDE_STEP = 28,
	SIDE_STEP_CONTINUE = 29,
	LAUNCH = 30,                ## into air kind 5
	THROW = 0x21,               ## the thrower
	THROWN = 0x22,              ## the throw victim
	HIT_GUARD = 0x23,
	HIT_AIR = 0x24,             ## juggle
	HIT_DOWN = 0x25,
	HIT_COUNTER = 0x26,
	HIT_SIDE_1 = 0x27,          ## facing quadrant 1
	HIT_SIDE_3 = 0x28,          ## facing quadrant 3
	HIT_OTHER = 0x29,           ## a normal hit reaction HitSelectReaction never picks
	HIT_FRONT = 0x2A,
	HIT_BACK = 0x2B,
	TO_TERMINATOR = 0x2C,       ## a matched branch row redirects to its list's terminator
}
