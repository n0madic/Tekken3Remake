class_name RoundState
## The round state `g_roundState` (fight-frame.md#round-flow), run by RoundFlow; FightMain reads it
## after each FightFrame.

enum {
	INTRO = 0,                  ## the round intro, then input on
	FIGHT = 1,                  ## the timer runs until a KO or the time is up
	RESULT = 2,                 ## the result shown, losers on scripted input
	REPLAY = 3,                 ## the replay after a KO (Tekken Ball: the deciding point's)
	REPLAY_DONE = 4,            ## the win poses and the round-end camera start
	WIN_POSES = 5,
	WIN_WAIT = 6,               ## win poses until they end, the hold runs out or Start
	AREA_CHANGE = 7,            ## Tekken Force: the level runner's area change, back to FIGHT
	STAGE_CLEAR = 8,            ## Tekken Force: STAGE CLEAR!! and the tally
	END = 9,                    ## the round is over: the next round or the match's end
	OGRE_SCENE = 10,            ## the Ogre scene starts
	PRACTICE_EXIT = 11,         ## the practice menu's exit to the main menu
}
