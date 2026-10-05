class_name BankType
## Motion bank types (`bankType`, fighter +0x16 = character record +9; divmot-banks.md). Most equal
## the character id; costumes share their character's bank (Tiger 8, Panda 11, True Ogre 14),
## Mokujin borrows one (9 in its record), and bank 15 is unused.

enum {
	PAUL = 0,
	LAW = 1,
	LEI = 2,
	KING = 3,
	YOSHIMITSU = 4,
	NINA = 5,
	HWOARANG = 6,
	XIAOYU = 7,
	EDDY = 8,
	JIN = 9,
	JULIA = 10,
	KUMA = 11,
	BRYAN = 12,
	HEIHACHI = 13,
	OGRE = 14,
	GUN_JACK = 16,
	ANNA = 17,
	DOCTOR_B = 18,
	GON = 19,
	FORCE_ENEMY = 20,             ## Tekken Force's enemies
}
