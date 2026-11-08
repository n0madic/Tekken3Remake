class_name CpuRecord
extends RefCounted
## What a CPU fighter's AI record holds in both builds: the PlayStation's (`AiRecord`, 0x330 bytes at
## 0x8009F6C0 + 0x330 · slot) and the arcade's (`ArcadeAiRecord`, 0x364 bytes at 0x8029CF00 + 0x364 · slot).
## Each field comment gives the offset in both records; what only one has, or holds differently,
## stays in its own class. The shared functions of `CpuMachinery` read and write only these.

var slot := 0                            ## PS1 +0x00, arcade +0x00
var frame_count := 0                     ## PS1 +0x02, arcade +0x04: grows whenever the pose frame changes (bit 0 picks the walk)
var pad := 0                             ## PS1 +0x04, arcade +0x06: held pad produced this frame
var prev_pad := 0                        ## PS1 +0x06, arcade +0x08
var script_steps := PackedInt32Array()   ## PS1 +0x08, arcade +0x0C: the pending input script
var script_at := -1                      ## PS1 +0x08, arcade +0x0C: its next step, −1 none
var band := 0                            ## PS1 +0x14, arcade +0x20: distance band 0–5
var reach_band := 0                      ## PS1 +0x18, arcade +0x24: the opponent's reach band 1–5
var prev_distance := 0                   ## PS1 +0x20, arcade +0x30
var distance_change := 0                 ## PS1 +0x24, arcade +0x34
var move_changed := 0                    ## PS1 +0x28, arcade +0x1C
var far_count := 0                       ## PS1 +0x2A, arcade +0x38
var move_frames := 0                     ## PS1 +0x2C, arcade +0x3C
var health_seen := 0                     ## PS1 +0x30, arcade +0x40
var pose_frame_seen := 0                 ## PS1 +0x34, arcade +0x44
var neutral_action := 0                  ## PS1 +0x36, arcade +0x48
var approach := 0                        ## PS1 +0x38, arcade +0x4C
var approach_kind := 0                   ## PS1 +0x3A, arcade +0x50: 2 a long approach
var crouching := 0                       ## PS1 +0x3C, arcade +0x54
var guarding := 0                        ## PS1 +0x3E, arcade +0x58
var approach_hold := 0                   ## PS1 +0x40, arcade +0x5C
var setup_cooldown := 0                  ## PS1 +0x42, arcade +0x60
var neutral_cooldown := 0                ## PS1 +0x44, arcade +0x64
var air_cooldown := 0                    ## PS1 +0x46, arcade +0x68
var direction_hold := 0                  ## PS1 +0x48, arcade +0x6C
var crouch_timer := 0                    ## PS1 +0x4A, arcade +0x70
var crouch_attack_hold := 0              ## PS1 +0x4C, arcade +0x74
var move_frame_seen := 0                 ## PS1 +0x4E, arcade +0x78
var attacking := 0                       ## PS1 +0x50, arcade +0x7C: the CPU's move has an active window
var special_open := 0                    ## PS1 +0x52, arcade +0x80: an air or special move with its window open
var whiff_timer := 0                     ## PS1 +0x54, arcade +0x84
var collected_move: MoveRow              ## PS1 +0x58, arcade +0x88: the move the candidates were collected from
var pressed_move: MoveRow                ## PS1 +0x5C, arcade +0x8C
var last_attack: MoveRow                 ## PS1 +0x60, arcade +0x90
var wait := 0                            ## PS1 +0x68, arcade +0x98: frames before the next attack (−1: attack now)
var guard_holds := 0                     ## PS1 +0x6A, arcade +0x9C
var guard_delay := 0                     ## PS1 +0x6C, arcade +0xA0
var cancel_wait := 0                     ## PS1 +0x6E, arcade +0xA4: the wait before leaving the stand-up rows
var candidate_count := 0                 ## PS1 +0x70, arcade +0xB0
var marked_count := 0                    ## PS1 +0x72, arcade +0xB4
var hook_opponent := AiTables.Hook.NONE  ## PS1 +0x74, arcade +0xB8: hook A of the opponent's bank
var hook_own := AiTables.Hook.NONE       ## PS1 +0x78, arcade +0xBC: hook B of the CPU's own bank
var filter_no_lows := false              ## PS1 +0x7C, arcade +0xC0: the predicate installed for this frame
var announced_frames := 0                ## PS1 +0x80, arcade +0xC4
var passed_frames := 0                   ## PS1 +0x84, arcade +0xC8
var vs_stance := 0                       ## PS1 +0x88, arcade +0xCC: the opponent is Yoshimitsu in slot 0x456 (PS1) or 0x470
var move_block := 0                      ## PS1 +0x8A, arcade +0xD0
var guard_suspend := 0                   ## PS1 +0x8C, arcade +0xD4
var parried := 0                         ## PS1 +0x8E, arcade +0xE4
var punish := 0                          ## PS1 +0x8F, arcade +0xE8
var throw_next := 0                      ## PS1 +0x90, arcade +0xEC
var throw_chance := 0                    ## PS1 +0x91, arcade +0xF0
var evade_reason := 0                    ## PS1 +0x92, arcade +0xF4
var guard_memory := 0                    ## PS1 +0x93, arcade +0xF8
var evasion := 0                         ## PS1 +0x94, arcade +0xFC
var throw_steps := 0                     ## PS1 +0x96, arcade +0x100
var throw_list := 0                      ## PS1 +0x98, arcade +0x104
var throw_press_frame := 0               ## PS1 +0x9C, arcade +0x128
var throw_move: MoveRow                  ## PS1 +0xA0, arcade +0x10C
var strings_on := 0                      ## PS1 +0xC0, arcade +0x130
var no_strings := 0                      ## PS1 +0xD4, arcade +0x148
var planned_on := 0                      ## PS1 +0xD8, arcade +0x150
var links_on := 0                        ## PS1 +0x1A0, arcade +0x224
var link_skip := 0                       ## PS1 +0x1CC, arcade +0x220
var link_last := 0                       ## PS1 +0x1D0, arcade +0x258
var attacks_in_row := 0                  ## PS1 +0x1D2, arcade +0x25C
var attack_limit := 0                    ## PS1 +0x1D4, arcade +0x260
var opp_move_changed := 0                ## PS1 +0x204, arcade +0x27C
var opp_down := 0                        ## PS1 +0x208, arcade +0x284
var opp_until := 0                       ## PS1 +0x20A, arcade +0x288: frames until the opponent's attack is active (999: none)
var opp_coming := 0                      ## PS1 +0x20C, arcade +0x28C
var opp_unblockable := 0                 ## PS1 +0x20E, arcade +0x290
var opp_charging := 0                    ## PS1 +0x210, arcade +0x294
var coming_seen := 0                     ## PS1 +0x212, arcade +0x298
var opp_grabs := 0                       ## PS1 +0x214, arcade +0x29C
var opp_string := -1                     ## PS1 +0x216, arcade +0x2A0
var opp_high := 0                        ## PS1 +0x21A, arcade +0x2AC
var own_word := 0                        ## PS1 +0x220, arcade +0x2BC: the CPU's move +0x08
var own_state := 0                       ## PS1 +0x224, arcade +0x2C0: the CPU's move +0x04
var own_attack := 0                      ## PS1 +0x228, arcade +0x2C4
var opp_word := 0                        ## PS1 +0x22C, arcade +0x2C8
var opp_state := 0                       ## PS1 +0x230, arcade +0x2CC
var opp_attack := 0                      ## PS1 +0x234, arcade +0x2D0
var params := PackedInt32Array()         ## PS1 +0x238, arcade +0x2D4: the difficulty words


## Difficulty word `i`.
func word(i: int) -> int:
	return params[i]


func script_pending() -> bool:
	return script_at >= 0
