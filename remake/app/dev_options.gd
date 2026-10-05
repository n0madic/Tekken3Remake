class_name DevOptions
extends RefCounted
## The development options the game, fight and M0 entry points share (command line after `--`,
## or the web build's query string): `--screenshot=<path>` saves the frame after `--frames=<n>`
## steps (DEFAULT_FRAMES without it) and quits, `--speed=<n>` runs n steps per physics tick,
## `--seed=<n>` fixes the random seed (−1: none given), `--stats` shows the step timings and
## `--graphics=<preset>` uses a graphics preset for the session (Settings.session, never saved),
## `--shading=<original|smooth|curved>` a Shading likewise.

const DEFAULT_FRAMES := 90        ## the default of `--frames`
## Seconds the entry points wait before quitting: the audio server releases a stopped playback on
## its next mix, so a stream still playing at exit is reported as leaked.
const AUDIO_DRAIN := 0.2

var screenshot_path := ""
var screenshot_frames := DEFAULT_FRAMES
var speed := 1
var seed := -1
var stats := false
var capturing := false
var _gpu_msec := 0.0
var _gpu_frames := 0          ## the screenshot frame is reached: draw it at the step itself


## The shared options of `args`; the entry points read their own options from `args` themselves.
static func parse(args: PackedStringArray) -> DevOptions:
	var o := DevOptions.new()
	var frames_given := false
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--screenshot="):
			o.screenshot_path = value
		elif arg.begins_with("--frames="):
			frames_given = true
			if not value.is_valid_int():
				Log.warning("DevOptions: %s is not a whole number of steps; the screenshot is after %d" % [arg, DEFAULT_FRAMES])
			else:
				o.screenshot_frames = maxi(1, value.to_int())   # steps count from 1
				if value.to_int() < 1:
					Log.warning("DevOptions: %s: the first step is the earliest frame to save" % arg)
		elif arg.begins_with("--speed="):
			o.speed = maxi(1, value.to_int())
		elif arg.begins_with("--seed="):
			o.seed = value.to_int() & 0x7FFFFFFF
		elif arg == "--stats":
			o.stats = true
		elif arg.begins_with("--graphics="):
			_use_for_session("graphics", value, arg)
		elif arg.begins_with("--shading="):
			_use_for_session("shading", value, arg)
	if not o.screenshot_path.is_empty() and not frames_given:
		Log.info("DevOptions: --screenshot without --frames: the frame after step %d" % DEFAULT_FRAMES)
	return o


## A setting's choice for this session, when this build offers it.
static func _use_for_session(key: String, value: String, arg: String) -> void:
	if value in Settings.choices(key):
		Settings.session[key] = value
	else:
		Log.warning("DevOptions: %s is not one of %s; the setting is used" % [arg, Settings.choices(key)])


## Whether `event` is the press that shows or hides the `--stats` line (F3).
static func toggles_stats(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == InputRouter.STATS_KEY


## Quits after AUDIO_DRAIN seconds (the entry points' way out, once their sound is stopped).
static func quit_after_drain(tree: SceneTree) -> void:
	await tree.create_timer(AUDIO_DRAIN).timeout
	tree.quit()


## Whether a screenshot was asked for and `steps` is its frame.
func screenshot_due(steps: int) -> bool:
	return not screenshot_path.is_empty() and steps == screenshot_frames


## Stops at the screenshot frame: the frames drawn from now on show the last step exactly (no
## interpolation, so a screenshot does not depend on the frame timing), and the next one is saved.
func capture(viewport: Viewport, done: Callable) -> void:
	capturing = true
	save_screenshot.call_deferred(viewport, done)


## The `--stats` line's render timings: the frame rate and the GPU time of `viewport`'s frames
## (milliseconds, a running average), also logged once a second for benchmarks.
func render_stats(viewport: Viewport) -> String:
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	_gpu_msec = lerpf(_gpu_msec, RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.05)
	var line := "%d fps  gpu %.2f ms" % [Engine.get_frames_per_second(), _gpu_msec]
	_gpu_frames += 1
	if _gpu_frames % maxi(Engine.get_frames_per_second(), 1) == 0:
		Log.info("stats: " + line)
	return line


## The interpolation weight to draw with: `fraction`, or the last step itself while capturing.
func weight(fraction: float) -> float:
	return 1.0 if capturing else fraction


## Saves the next drawn frame of `viewport` to `screenshot_path`, then calls `done`.
func save_screenshot(viewport: Viewport, done: Callable) -> void:
	if DisplayServer.window_can_draw():
		await RenderingServer.frame_post_draw
	else:
		# A hidden or covered window draws no frames, so frame_post_draw would never come: once
		# this frame's _process has shown the step (the next frame's start), draw it here.
		var tree := viewport.get_tree()
		await tree.process_frame
		await tree.process_frame
		Log.info("DevOptions: the window cannot draw; drawing the screenshot frame directly")
		RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.save_png(screenshot_path)
	done.call()
