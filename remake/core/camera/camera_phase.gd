class_name CameraPhase
## The fight camera's phase `g_cameraPhase` (0x80095890, camera.md#director): set by the fight
## start, the director and the round flow.

enum {
	RESET = 0,                  ## reset the sources and choose the intro, then INTRO
	INTRO = 1,                  ## the round intro, then FIGHT
	FIGHT = 2,                  ## the fight camera with cinematic cameras
	WINNER_0 = 3,               ## set up the winner camera for fighter 0 / 1, then WINNER
	WINNER_1 = 4,
	WINNER = 5,
	LOSER_0 = 6,                ## the loser camera of the match-deciding round: fighter 0 / 1
	LOSER_1 = 7,
}
