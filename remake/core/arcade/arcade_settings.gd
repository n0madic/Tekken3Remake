class_name ArcadeSettings
extends RefCounted
## The operator's settings the game reads at boot (FUN_80189FF4, the EEPROM block at 0x8036EC1C).
## The remake runs on free play (0x8036EC4C): it has no coins.

var difficulty := 1                     ## 0x8021FD28 (EC4F)
var rounds_one := 1                     ## 0x8021FD94 (EC50): rounds to win − 1 against the CPU
var rounds_versus := 1                  ## 0x8021FD98 (EC51)
var life_one := 0                       ## 0x8021FDD0 (EC52): the life table's entry
var life_versus := 0                    ## 0x8021FC54 (EC53)
var guard_damage := 0                   ## 0x8021FDA8 (EC54)
var neutral_guard := 0                  ## 0x8021FC70 (EC55)
var round_time := 2                     ## 0x8021FC84 (EC56)
var reselect := 0                       ## 0x8021FB10 (EC57): a continue goes back to the select
var demo_bit := 0                       ## 0x8021FCA4 (EC58): flags 0x80374F1C bit 2
var attract_sound := 0                  ## 0x8021FC20 (EC59): the attract plays its sounds
var event_mode := 0                     ## 0x8021FC5C (EC5A): a game takes both sides
var cabinet := 0                        ## 0x8021FB74 (ECF4): 1 picks the other life table
