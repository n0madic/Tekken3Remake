class_name EffectPool
extends RefCounted
## The state of the effect objects (EffectObjects): the pool in allocation order and the
## globals of EffectsUpdate.

var objects: Array[EffectObjects.Obj] = []
var live := 0                       ## 0x800A965C: objects updated by the last EffectsUpdate
var replay_glows := 0               ## 0x800A0D38: the glows were re-created for the replay
var end_cleared := 0                ## 0x800A0D39: the pool was emptied for the round end
var burn_flags := 0                 ## 0x800AE39E: Gon's burning players (0x10 >> player)
var glow_mask := PackedInt32Array([0, 0])   ## 0x800A8B28: glowing joints per player
var counter := 0                    ## 0x80098BDC
var echo_voice := 0                 ## 0x800A0D40: SPU voice of the next replay echo
var segments: Array[Array] = [[], []]       ## projectile segments (start, end) per owner
var lights: Array[PackedInt32Array] = []    ## the frame's point lights (x, y, z, kind)
