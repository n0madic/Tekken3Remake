class_name ArcadeSelectSide
extends RefCounted
## A side's record in the character select (context 0x802C8300 + 0x34 + 0x80 · player).

const NONE := 0x16

var state := 0                      ## +0
var cell := 0                       ## +4: the column
var row := 0                        ## +8
var rest := 0                       ## +0xC: the frames since the cursor moved
var anim_a := 0                     ## +0x10
var anim_b := 0                     ## +0x14
var shown_key := NONE               ## +0x1C
var shown_costume := 1              ## +0x20
var character := NONE               ## +0x24
var costume := 0                    ## +0x28
var chosen_wait := 0                ## +0x2C
var chosen_anim := 0                ## +0x34
var kept_character := NONE          ## +0x40
var kept_costume := 0               ## +0x44
var default_cell := 0               ## +0x7C
