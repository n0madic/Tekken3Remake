class_name StateBit
## Bits of a move's `state` word (combat.md#attack-levels-postures-and-guards): posture, guard,
## throw targeting and the state class; the AI reads a few higher bits
## (ai.md#candidates-from-the-branch-list). Bits 19, 21 and 22, whose meaning is not established,
## are left as numbers where they are read.

enum {
	CROUCHING = 1,
	STANDING = 2,
	DOWN = 4,                     ## lying
	POSTURE = 7,
	GUARD_CROUCHING = 8,
	GUARD_STANDING = 0x10,
	GUARDS = 0x18,
	HUMAN_GUARD = 0x100,          ## the guard is kept only for human-controlled fighters
	DOWN_REVERSED = 0x200,        ## lying the other way
	AIRBORNE = 0x400,
	CLASS_SHIFT = 11,             ## bits 11–15: the state class
	REACH_ANY = 0x10000,          ## the AI takes the move whatever the reach
	NOT_AI_ATTACK = 0x20000,      ## never counts as an attack for the AI's filters
	AI_UNUSABLE = 0x800000,       ## the AI never uses a candidate leading here
}
