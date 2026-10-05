class_name CameraShake
## Camera shake (camera.md#camera-shake): CameraShakeStart (0x8004AF94) picks one of three byte
## scripts and pulses both pads through VibrateAll; CameraShakeStep (0x8004AFCC) adds the
## script's next byte to the camera's pitch every frame until −128.

const END := -128


static func start(fight: FightState, script: int, events: SimEvents) -> void:
	fight.shake_script = script
	fight.shake_pos = 0
	events.add(SimEvents.Kind.SHAKE, -1, script)
	Vibration.all(fight, script, events)


## The pitch offset of this frame (4096 units), 0 without a running script.
static func step(fight: FightState) -> int:
	if fight.shake_script < 0:
		return 0
	var value := fight.tables.shake_scripts[fight.shake_script][fight.shake_pos]
	fight.shake_pos += 1
	if value == END:
		fight.shake_script = -1
		value = 0
	return value
