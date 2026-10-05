class_name BranchCondition
## Branch row condition types (moves.md#branch-conditions): `MoveSystem.condition` evaluates
## 0x00–0x44, `BranchFindReversal` the reversal types 0x45–0x4B. `P` is the row parameter.

enum {
	ALWAYS = 0,
	CONTACT = 1,                    ## own attack touched the opponent this move
	SITUATION_FIRST = 2,            ## 2–0x13: the throw situation code equals the type, distAdj ≤ P
	SITUATION_LAST = 0x13,
	SITUATION_2_6 = 0x14,           ## 0x14–0x17: the situation code is one of a pair, distAdj ≤ P
	SITUATION_3_7 = 0x15,
	SITUATION_4_8 = 0x16,
	SITUATION_5_9 = 0x17,
	NEAR = 0x18,                    ## dist ≤ P
	FAR = 0x19,                     ## dist ≥ P
	HIT = 0x1A,                     ## own contact not covered by the opponent's guard
	OPP_GUARDED = 0x1B,
	WHIFFED = 0x1C,
	OPP_NOT_THROWING = 0x1D,
	OPP_ATTACKING = 0x1E,
	OPP_ATTACKING_STANDING = 0x1F,
	OPP_ATTACKING_CROUCHING = 0x20,
	OPP_NOT_ATTACKING = 0x21,
	OPP_STANDING = 0x22,            ## on the ground
	OPP_CROUCHING = 0x23,           ## on the ground
	TURNED_AWAY = 0x24,             ## relAngle > 90°
	TURNED_SIDE_A = 0x25,           ## headingDelta in [0x4E38, 0x8000)
	TURNED_SIDE_B = 0x26,           ## headingDelta in [0x8000, 0xB1C6]
	FACING_QUADRANT_0 = 0x27,
	FACING_QUADRANT_1 = 0x28,
	FACING_QUADRANT_3 = 0x29,
	FACING_QUADRANT_2 = 0x2A,
	OPP_QUADRANT_0 = 0x2B,
	OPP_QUADRANT_1 = 0x2C,
	OPP_QUADRANT_3 = 0x2D,
	OPP_QUADRANT_2 = 0x2E,
	NEVER = 0x2F,
	HIGH_ATTACK_COMING = 0x30,      ## the opponent's high attack, not past its window, dist < 0x700
	RECOVERED = 0x31,               ## knock-down recovery counters both zero
	RECOVERING = 0x32,
	BODY_CONTACT = 0x33,
	BODY_CONTACT_GROUNDED = 0x34,   ## and the opponent neither airborne nor down
	OPP_DOWN = 0x35,
	OPP_NOT_DOWN = 0x36,
	OPP_DOWN_NEAR = 0x37,           ## down, its move has no air window, dist ≤ P
	OPP_DOWN_TURNED_AWAY = 0x38,    ## down and relAngle ≥ 90°
	OPP_COUNTER_HIT = 0x39,         ## took a counter hit and is not airborne
	TAP_LP = 0x3A,                  ## 0x3A–0x3C: latched button taps (set condFlagUsed)
	TAP_RP = 0x3B,
	TAP_BOTH = 0x3C,
	KO = 0x3D,                      ## own health is zero
	SIDE_CLEAR = 0x3E,
	SIDE_SET = 0x3F,
	SIDE_CLEAR_TURNED_AWAY = 0x40,
	SIDE_SET_TURNED_AWAY = 0x41,
	NOT_LAUNCHED = 0x42,            ## not in a launch reaction, health non-zero
	POWER = 0x43,                   ## powerTimer running
	NO_POWER = 0x44,
	REVERSAL_HIT = 0x45,            ## 0x45–0x4B: reversals (combat.md#reversals-and-parries)
	REVERSAL_HIGH = 0x46,
	REVERSAL_MID = 0x47,
	REVERSAL_LOW = 0x48,
	REVERSAL_HIGH_MID = 0x49,
	REVERSAL_SLOT = 0x4A,
	REVERSAL_ANIM = 0x4B,
}
