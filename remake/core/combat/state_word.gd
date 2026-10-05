class_name StateWord
## The most common state word of each state class (combat.md#attack-levels-postures-and-guards):
## the fighter's posture (bits 0–2), guard bits (3–4) and class (bits 11–15).

enum {
	STAND = 0x842,
	GUARD_HIGH = 0x1052,            ## standing guard
	STAND_STANCE = 0x1952,          ## slot 3: guard for humans only (bit 8)
	CROUCH = 0x2021,
	GUARD_LOW = 0x2829,             ## crouching guard
	CROUCH_STANCE = 0x3129,         ## slot 40
	DOWN = 0x3884,
	DOWN_OTHER = 0x4284,
	LAUNCHED = 0x4C02,              ## launched hit reactions
	NO_POSTURE = 0x5000,            ## cannot be hit by any attack word
	JUMP = 0x6042,
}
