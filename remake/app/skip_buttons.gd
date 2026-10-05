class_name SkipButtons
## A convenience of the remake: the game skips its start-up, attract sequence, replays and movies
## on Start only; ✕ and ○ skip them too (the steps see Start held with them).

const BUTTONS := PadState.CROSS | PadState.CIRCLE


## The pads with Start added to each holding ✕ or ○ while the game is on something they skip (not
## an ending or Theater movie: `skips_blocking_movie` reads those buttons themselves).
static func apply(pads: PackedInt32Array, flow: GameFlow, movie_playing: bool) -> PackedInt32Array:
	var out := pads.duplicate()
	if skippable(flow, movie_playing) and not flow.movie_blocking:
		for p in out.size():
			if out[p] & BUTTONS:
				out[p] |= PadState.START
	return out


## Whether an ending or Theater movie is skipped this frame: Start, ✕ or ○ newly pressed on either
## pad, by the pads the flow read while the movie played (a button still held from the choice that
## started it is no press).
static func skips_blocking_movie(flow: GameFlow) -> bool:
	if not flow.movie_blocking:
		return false
	var pressed := flow.sim.pads.physical_pressed
	return (pressed[0] | pressed[1]) & (PadState.START | BUTTONS) != 0


## Whether what shows is skipped with Start: the boot and title screens, the opening movies, the
## demonstration and its fight, a fight's replay, an ending or Theater movie.
static func skippable(flow: GameFlow, movie_playing: bool) -> bool:
	if movie_playing:
		return true
	match flow.state:
		GameFlow.State.TITLE, GameFlow.State.ENBU:
			return true
		GameFlow.State.TRANSITION:
			return flow.progress.transition_target in [GameFlow.State.TITLE, GameFlow.State.ENBU]
		GameFlow.State.FIGHT:
			# Not the win poses after a replay: the button held there picks the pose.
			return flow.region.mode == GameMode.DEMO or flow.fight.replay_playing != 0
	return false
