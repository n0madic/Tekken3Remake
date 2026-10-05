class_name Tracking
## Heading tracking modes (moves.md#facing-and-tracking): set by the transition at move start,
## applied by `FighterPhysics` every frame.

enum {
	NONE = 0,                   ## heading follows facing
	AIM = 1,                    ## towards aimDir, budget 180°
	TARGET = 2,                 ## towards the opponent, budget 120°
	TARGET_HALF = 3,            ## as TARGET at half the rate
	TARGET_SLOW = 4,            ## budget 20°, only while no timed turn runs
	TARGET_FAST = 5,            ## up to 100° a frame, budget 210°
	AFTER_ACTIVE = 6,           ## timed turns towards aimDir every 5 frames after the active window
	EASE_BY_POSE = 7,           ## towards aimDir weighted by the pose frame (push-back)
	EASE = 8,                   ## towards aimDir over the first 8 frames
	APPROACH = 9,               ## facing towards the opponent's position at move start
	SIDE_STEP = 10,
	TIMED = 11,                 ## only the timed turn
	TIMED_ALERT = 12,           ## a timed turn started against an attack alert
}
