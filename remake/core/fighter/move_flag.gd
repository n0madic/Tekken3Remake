class_name MoveFlag
## Bits of a move's flag word (+0x24, moves.md#move-flags-0x24), as masks of the 32-bit word
## (the game tests them on `flags >> 8`). The low byte is the move's camera byte.

enum {
	NO_BLEND = 0x100,             ## no motion blending from this move
	NO_BLEND_FORWARD = 0x200,     ## no blending into the next or stance move
	ABOUT_TO_HIT = 0x400,         ## aboutToHit during the whole move
	ALERT = 0x800,                ## attackAlert at move start; cannot be parried
	LAUNCH_ANGLE = 0x1000,        ## launches add the reaction angle; no knock-down counters
	BUFFER_INPUT = 0x2000,        ## a command buffer is kept during the move
	STICK_GUARD = 0x4000,         ## the guard stance follows the stick
	POWER = 0x10000,              ## powerTimer at move start (Tekken Force: a forced hit)
	BODY_ADJUST = 0x20000,        ## body-separation adjustment
	REACT_CHAIN = 0x40000,        ## counted by reactChain
	PARTNER = 0x80000,            ## facing and anchor from the throw partner
	REANCHOR = 0x10000000,        ## re-anchor root motion when a move is entered from this one
	TRACK_ROOT = 0x20000000,      ## the camera follows the root rather than the anchor
	LOOK_AT = 0x40000000,         ## head look-at
}
