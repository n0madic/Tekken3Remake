# Resident routine index

Status: generated from the call graph of the decompiled Japan Rev.1 executable (`work/decomp`), with notes for the larger routines. It lists every unnamed resident routine that no other document mentions by address (444 routines, 78 KB), grouped by the nearest documented caller, so that each belongs to a described subsystem. Effect routines are listed with the effect type(s) whose update reaches them.

The groups follow the documents: `FightFrame` and its steps ([fight-frame.md](fight-frame.md)), the fight set-up (`FUN_8002A660`, `FUN_8002AB68`, `FightAllocBuffers`), the camera (`CameraDirector`, `FUN_80066568`, [camera.md](camera.md)), fighter drawing and animation (`FighterComposeJoints`, `FighterAnimate`, [3dmk-models.md](../formats/3dmk-models.md), [animation.md](../formats/animation.md)), sound and CD (`MusicPlay`, `FUN_8006B9E4`, `FUN_8006AE4C`, `Ds*`, [sound.md](sound.md)), and `FUN_800B0A10`, the boot module overwritten by the overlays.

## Effect objects ([effects.md](effects.md))

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8006E3B8` | 80 | `EffectsUpdate` |  | Part of effect type 6, 8. |
| `0x8006F840` | 84 | `EffectsUpdate` |  | Part of effect type 0. |
| `0x8006F894` | 20 | `EffectsUpdate` |  | Part of effect type 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20. |
| `0x8007004C` | 84 | `EffectsUpdate` |  | Part of effect type 0. |
| `0x800700A0` | 24 | `EffectsUpdate` |  | Part of effect type 0. |
| `0x800700B8` | 52 | `EffectsUpdate` |  | Part of effect type 0. |
| `0x800700EC` | 84 | `EffectsUpdate` |  | Part of effect type 1. |
| `0x80070140` | 612 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 1. |
| `0x800703A4` | 308 | `EffectsUpdate` |  | Part of effect type 1. |
| `0x800704D8` | 84 | `EffectsUpdate` |  | Part of effect type 2. |
| `0x8007052C` | 708 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 2. |
| `0x800707F0` | 192 | `EffectsUpdate` |  | Part of effect type 2. |
| `0x800708B0` | 84 | `EffectsUpdate` |  | Part of effect type 3. |
| `0x80070904` | 472 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 3. |
| `0x80070ADC` | 896 | `EffectsUpdate` | `ApplyRotMatrix`, `DynamicLightSet`, `SetRotMatrix` | Part of effect type 3. |
| `0x80070E5C` | 84 | `EffectsUpdate` |  | Part of effect type 4. |
| `0x80070EB0` | 576 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 4. |
| `0x800710F0` | 152 | `EffectsUpdate` |  | Part of effect type 4. |
| `0x80071188` | 84 | `EffectsUpdate` |  | Part of effect type 5. |
| `0x800711DC` | 540 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 5. |
| `0x800713F8` | 156 | `EffectsUpdate` |  | Part of effect type 5. |
| `0x80071494` | 916 | `EffectsUpdate` | `DynamicLightSet` | Part of effect type 6. |
| `0x80071828` | 384 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 6. |
| `0x800719A8` | 260 | `EffectsUpdate` |  | Part of effect type 6. |
| `0x80071AAC` | 284 | `EffectsUpdate` |  | Part of effect type 6. |
| `0x80071BC8` | 324 | `EffectsUpdate` |  | Part of effect type 6. |
| `0x80071D0C` | 216 | `EffectsUpdate` |  | Part of effect type 7. |
| `0x80071DE4` | 428 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 7. |
| `0x80071F90` | 216 | `EffectsUpdate` |  | Part of effect type 7. |
| `0x80072068` | 220 | `EffectsUpdate` |  | Part of effect type 7. |
| `0x80072144` | 824 | `EffectsUpdate` | `DynamicLightSet` | Part of effect type 8. |
| `0x8007247C` | 320 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 8. |
| `0x800725BC` | 248 | `EffectsUpdate` |  | Part of effect type 8. |
| `0x800726B4` | 216 | `EffectsUpdate` |  | Part of effect type 8. |
| `0x8007278C` | 32 | `EffectsUpdate` |  | Part of effect type 8. |
| `0x800727AC` | 296 | `EffectsUpdate` |  | Part of effect type 8. |
| `0x800728D4` | 288 | `EffectsUpdate` |  | Part of effect type 9. |
| `0x800729F4` | 284 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 9. |
| `0x80072B10` | 216 | `EffectsUpdate` |  | Part of effect type 9. |
| `0x80072BE8` | 252 | `EffectsUpdate` |  | Part of effect type 9. |
| `0x80072CE4` | 396 | `EffectsUpdate` |  | Part of effect type 10. |
| `0x80072E70` | 468 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 10. |
| `0x80073044` | 280 | `EffectsUpdate` |  | Part of effect type 10. |
| `0x8007315C` | 196 | `EffectsUpdate` | `DynamicLightSet` | Part of effect type 11. |
| `0x80073220` | 284 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 11. |
| `0x8007333C` | 592 | `EffectsUpdate` |  | Part of effect type 11. |
| `0x8007358C` | 240 | `EffectsUpdate` |  | Part of effect type 11. |
| `0x8007367C` | 288 | `EffectsUpdate` |  | Part of effect type 11. |
| `0x8007379C` | 84 | `EffectsUpdate` |  | Part of effect type 12. |
| `0x800737F0` | 624 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 12. |
| `0x80073A60` | 308 | `EffectsUpdate` |  | Part of effect type 12. |
| `0x80073B94` | 84 | `EffectsUpdate` |  | Part of effect type 13. |
| `0x80073BE8` | 720 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 13. |
| `0x80073EB8` | 192 | `EffectsUpdate` |  | Part of effect type 13. |
| `0x80073F78` | 616 | `EffectsUpdate` | `DynamicLightSet` | Part of effect type 15. |
| `0x800741E0` | 524 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 15. |
| `0x800743EC` | 424 | `EffectsUpdate` |  | Part of effect type 15. |
| `0x80074594` | 244 | `EffectsUpdate` |  | Part of effect type 15. |
| `0x80074688` | 172 | `EffectsUpdate` |  | Part of effect type 15. |
| `0x80074734` | 72 | `EffectsUpdate` |  | Part of effect type 16. |
| `0x8007477C` | 76 | `EffectsUpdate` | `SoundPlayFighter`, `SpuGetKeyStatus` | Part of effect type 16. |
| `0x800747C8` | 156 | `EffectsUpdate` |  | Part of effect type 17. |
| `0x80074864` | 24 | `EffectsUpdate` |  | Part of effect type 17. |
| `0x8007487C` | 112 | `EffectsUpdate` | `SoundPlayFighter` | Part of effect type 17. |
| `0x800748EC` | 100 | `EffectsUpdate` | `SoundPlayFighter` | Part of effect type 17. |
| `0x80074950` | 132 | `EffectsUpdate` |  | Part of effect type 18. |
| `0x800749D4` | 100 | `EffectsUpdate` |  | Part of effect type 18. |
| `0x80074A38` | 156 | `EffectsUpdate` | `SoundPlayFighter` | Part of effect type 18. |
| `0x80074AD4` | 204 | `EffectsUpdate` |  | Part of effect type 19. |
| `0x80074BA0` | 28 | `EffectsUpdate` |  | Part of effect type 19. |
| `0x80074BBC` | 348 | `EffectsUpdate` |  | Part of effect type 19. |
| `0x80074D18` | 244 | `EffectsUpdate` |  | Part of effect type 20. |
| `0x80074E0C` | 336 | `EffectsUpdate` | `SetPolyFT4`, `SetSemiTrans` | Part of effect type 20. |
| `0x80074F5C` | 304 | `EffectsUpdate` |  | Part of effect type 20. |

## PsyQ library code (not game logic)

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8008E9AC` | 236 |  |  | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x8008EAEC` | 496 |  |  | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x8008EF70` | 140 |  |  | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x800904DC` | 112 |  |  | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x80090608` | 484 |  | `CONCAT11`, `CONCAT12`, `CONCAT13` | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x800907EC` | 648 |  |  | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x80090A74` | 236 |  |  | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x80090BF4` | 176 |  |  | PsyQ libspu/libsnd internals; no caller in the game (linked library code), or called inside the library. |
| `0x800933E8` | 532 |  | `CONCAT44` | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x800935FC` | 200 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x800936C4` | 472 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x8009389C` | 564 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80093AD0` | 144 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80093B60` | 40 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80093BA8` | 132 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80093C2C` | 332 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80093D78` | 56 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80093DB0` | 212 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80094438` | 32 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80094458` | 20 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x8009446C` | 32 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x8009448C` | 32 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x800944AC` | 32 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x800944CC` | 20 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x80094D88` | 16 |  |  | Callback registered by `FUN_80094ACC` (library). |
| `0x800954C8` | 220 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x800955A4` | 44 |  |  | Callback registered by `FUN_8009515C` (library). |
| `0x800955DC` | 32 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |
| `0x800955FC` | 160 |  |  | PsyQ library internals (libcd/libapi); no caller in the game (linked library code), or called inside the library. |

## fight set-up FUN_8002AB68

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002BE54` | 112 | `fight set-up FUN_8002AB68`, `RoundFlow` | `InputClear` | Helper of fight set-up FUN_8002AB68. |
| `0x8002C298` | 12 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x80039288` | 64 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8003A140` | 32 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8003A374` | 20 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8003CD9C` | 36 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8003EE88` | 12 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x80046F6C` | 44 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8004A6A4` | 92 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8004AEFC` | 32 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8004AF88` | 12 | `fight set-up FUN_8002AB68`, `CameraDirector` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8004E520` | 60 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8004E868` | 20 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8004F5C4` | 212 | `fight set-up FUN_8002AB68` |  | Mokujin: picks the character whose moves he copies at random among the unlocked IDs 0–13 and 16 (`0x800982D0 & 0x13FFF`). |
| `0x80063358` | 12 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8006CB40` | 12 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8006E8FC` | 164 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x8006EC40` | 68 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x800777AC` | 96 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |
| `0x800B30DC` | 60 | `fight set-up FUN_8002AB68` |  | Helper of fight set-up FUN_8002AB68. |

## boot module FUN_800B0A10

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80029700` | 28 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x80029AE8` | 144 | `boot module FUN_800B0A10`, `FUN_800B0B24`, `FUN_800B0B54` | `EnableEvent`, `OpenEvent`, `StopRCnt`, `VSyncCallback` | Helper of boot module FUN_800B0A10. |
| `0x80067540` | 8 | `boot module FUN_800B0A10`, `FUN_800B0B24`, `FUN_800B0B54` |  | Helper of boot module FUN_800B0A10. |
| `0x80067ECC` | 224 | `boot module FUN_800B0A10`, `FUN_800B0B24`, `FUN_800B0B54` |  | Camera choice lists: one-time set-up of the list table `0x800244F8` (flag `0x800988E4`). |
| `0x8006C850` | 32 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x8007B2FC` | 108 | `boot module FUN_800B0A10` | `ChangeClearPAD`, `InitCARD2` | Helper of boot module FUN_800B0A10. |
| `0x8007B368` | 56 | `boot module FUN_800B0A10` | `ChangeClearPAD`, `StartCARD2` | Helper of boot module FUN_800B0A10. |
| `0x8007B3E8` | 16 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x80092B1C` | 32 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x80092F5C` | 72 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x800930C4` | 44 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x800932D8` | 204 | `boot module FUN_800B0A10` | `ChangeClearRCnt`, `SysDeqIntRP`, `SysEnqIntRP` | Library interrupt set-up (`SysEnqIntRP` for the CD/vblank handler). |
| `0x80093B8C` | 12 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x80094ACC` | 352 | `boot module FUN_800B0A10` |  | Library: installs the pad/card interrupt callbacks. |
| `0x8009515C` | 52 | `boot module FUN_800B0A10` |  | Helper of boot module FUN_800B0A10. |
| `0x800B0E1C` | 76 | `boot module FUN_800B0A10` | `VSync` | Helper of boot module FUN_800B0A10. |
| `0x800B0E68` | 16 | `boot module FUN_800B0A10` | `EnableEvent`, `OpenEvent` | Helper of boot module FUN_800B0A10. |
| `0x800B1064` | 292 | `boot module FUN_800B0A10` |  | Boot module: initialises both pad records (`0x800A95F8`) from the table `0x800B11B0`. |

## FightAllocBuffers

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80031F58` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x8004830C` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x80048784` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x8004A69C` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x80069AA0` | 28 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x8006CAE0` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x8006D2F4` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x8006E7FC` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x80079D88` | 68 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x80079DCC` | 332 | `FightAllocBuffers` |  | FightAllocBuffers: per-mode layout of the packet/OT areas from `0x800AE508`. |
| `0x80079F18` | 60 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x80079F54` | 264 | `FightAllocBuffers` |  | FightAllocBuffers: the two display-buffer work areas (`0x800A3E38`, 0x7860 bytes each). |
| `0x800B1500` | 68 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x800B4A58` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x800B4A60` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x800B5C94` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x800B5C9C` | 8 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |
| `0x800D4834` | 1 | `FightAllocBuffers` |  | Helper of FightAllocBuffers. |

## CD/sound system FUN_8006AE4C

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8006AFC4` | 60 | `CD/sound system FUN_8006AE4C` | `DsGetToc` | Helper of CD/sound system FUN_8006AE4C. |
| `0x8006B010` | 28 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x8006C168` | 40 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x8008E97C` | 48 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x8008EFFC` | 324 | `CD/sound system FUN_8006AE4C` | `DsReadySystemMode` | CD/sound: resets the CD read state (`0x800AE4F8..0x800AE500`). |
| `0x8008F140` | 268 | `CD/sound system FUN_8006AE4C` | `DsReadySystemMode` | CD/sound: stops the CD and clears the read state. |
| `0x8008FD7C` | 152 | `CD/sound system FUN_8006AE4C` | `VSyncCallbacks` | Helper of CD/sound system FUN_8006AE4C. |
| `0x8008FE14` | 216 | `CD/sound system FUN_8006AE4C` | `DsIntToPos` | libds: clears the command queue. |
| `0x8008FFA8` | 12 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x8008FFB4` | 12 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x8008FFC0` | 12 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x8008FFCC` | 12 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x80090CA4` | 116 | `CD/sound system FUN_8006AE4C`, `DsGetToc` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x80090D18` | 16 | `CD/sound system FUN_8006AE4C`, `DsGetToc` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x80090D28` | 16 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |
| `0x8009185C` | 28 | `CD/sound system FUN_8006AE4C` |  | Helper of CD/sound system FUN_8006AE4C. |

## Called from overlays

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002959C` | 116 | `select:FUN_8010ea2c` |  | Helper of select:FUN_8010ea2c. |
| `0x8002A350` | 44 | `title:FUN_800df14c` |  | Helper of title:FUN_800df14c. |
| `0x8002BEC4` | 120 | `practice:FUN_800b3808` | `InputClear` | Helper of practice:FUN_800b3808. |
| `0x8002DFEC` | 140 | `practice:FUN_800b3520` |  | Helper of practice:FUN_800b3520. |
| `0x80035D7C` | 152 | `enbu:FUN_800d3d64` |  | Helper of enbu:FUN_800d3d64. |
| `0x800511CC` | 56 | `enbu:FUN_800d3028`, `title:FUN_800daf2c` |  | Helper of enbu:FUN_800d3028. |
| `0x80051498` | 72 | `arcade:FUN_800b134c` |  | Helper of arcade:FUN_800b134c. |
| `0x80051674` | 40 | `arcade:FUN_800b134c` |  | Helper of arcade:FUN_800b134c. |
| `0x80051C58` | 12 | `arcade:FUN_800b3708` |  | Helper of arcade:FUN_800b3708. |
| `0x80063364` | 92 | `practice:FUN_800b8d50` | `CameraReset` | Helper of practice:FUN_800b8d50. |
| `0x80069C34` | 348 | `enbu:FUN_800d47e4` |  | Camera: relocates a loaded camera data block (offsets to pointers, `0x800AE0E8`). |
| `0x8006B03C` | 92 | `ending:FUN_8010d474`, `title:FUN_800e1614` | `DsPosToInt` | Helper of ending:FUN_8010d474. |
| `0x8006B80C` | 28 | `ending:FUN_8010d7e0`, `title:FUN_800e1940` |  | Helper of ending:FUN_8010d7e0. |
| `0x8006B828` | 12 | `ending:FUN_8010d474`, `title:FUN_800e1614` |  | Helper of ending:FUN_8010d474. |
| `0x8006BC60` | 104 | `ending:FUN_8010d474`, `title:FUN_800e1614` |  | Helper of ending:FUN_8010d474. |

## Called through pointers or tables

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002942C` | 368 |  | `VibrationUpdate` | Pad vibration update, called from the vertical-blank callback. |
| `0x8002971C` | 240 |  | `ClearImage2`, `LoadImage`, `MoveImage` | VRAM copy/clear helper called from the vertical-blank callback. |
| `0x800299D8` | 272 |  | `GsSwapDispBuff`, `ResetGraph`, `SetRCnt`, `SsSeqCalledTbyT` | Vertical-blank callback registered by `FUN_80029AE8` (display swap, `ResetGraph`, root counter); calls the vibration update `0x8002942C` and `0x8002971C`. |
| `0x80029C34` | 72 |  | `SetRCnt`, `StartRCnt` | Root-counter callback registered by `FUN_80029AE8`. |
| `0x8002A37C` | 68 |  |  | Helper of the vibration update. |
| `0x8006C0DC` | 8 |  |  | Empty CD callback. |
| `0x8006C0E4` | 68 |  | `DsGetSector2`, `DsPosToInt` | CD read-ready callback registered by `MusicPlay`/`FUN_8006B47C`. |
| `0x8006C128` | 64 |  | `DsPosToInt` | CD data callback registered by the per-frame sound update. |
| `0x8006C588` | 464 |  | `DsEndReadySystem`, `DsGetSector` | CD sector callback registered by `FUN_8006C554`. |
| `0x8006EC84` | 396 |  | `ApplyRotMatrix`, `DynamicLightSet`, `FighterVibrate`, `SetRotMatrix` | Attack joint descriptor 0x18 spawner (from `FUN_8006F3DC` jump table `0x80025408`, active window only): fire breath, effect type 6, vibration 3, orange light. |
| `0x8006EE10` | 380 |  | `ApplyRotMatrix`, `DynamicLightSet`, `FighterVibrate`, `SetRotMatrix` | Descriptor 0x1A: Gon's long flame, effect type 8. |
| `0x8006EF8C` | 344 |  | `ApplyRotMatrix`, `SetRotMatrix` | Descriptors 0x19 (argument 0) and 0x1C (argument 1): breath cloud, effect type 10. |
| `0x8006F0E4` | 356 |  | `ApplyRotMatrix`, `SetRotMatrix` | Descriptor 0x1B: Gon's gas emitter, effect type 19. |
| `0x80081BEC` | 36 |  | `DrawOTag` | Helper of the library. |

## FightFrame

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002BC28` | 144 | `FightFrame`, `RoundFlow` |  | Helper of FightFrame. |
| `0x8002BDAC` | 24 | `FightFrame`, `RoundFlow` |  | Helper of FightFrame. |
| `0x80032828` | 16 | `FightFrame` |  | Helper of FightFrame. |
| `0x800339DC` | 24 | `FightFrame` |  | Helper of FightFrame. |
| `0x8004A8AC` | 100 | `FightFrame` |  | Helper of FightFrame. |
| `0x8004A954` | 384 | `FightFrame` | `EffectSpawn` | Replays recorded effect events (`0x8009EBE0`): EffectSpawn or landing dust (`FUN_8004AC28`). |
| `0x8004AD28` | 404 | `FightFrame` | `FlipbookSetup` | Landing-dust flipbooks (`0x8009EBF8` ring): starts and advances them. |
| `0x8004AEBC` | 64 | `FightFrame` |  | Helper of FightFrame. |
| `0x8004AF4C` | 60 | `FightFrame` |  | Helper of FightFrame. |
| `0x800695EC` | 272 | `FightFrame` |  | Demonstration/replay camera step counter (`0x800A0838`) and source update. |
| `0x800696FC` | 296 | `FightFrame` | `CameraFrameFighters`, `CameraUseSource` | Demonstration/replay camera: framing with `CameraFrameFighters` and the pitch/distance ramps. |
| `0x80077158` | 1516 | `FightFrame` |  | Per-frame particle list update (positions, clamped velocities) called from FightFrame. |
| `0x80077744` | 104 | `FightFrame` |  | Helper of FightFrame. |
| `0x8007780C` | 108 | `FightFrame` |  | Helper of FightFrame. |

## CameraDirector

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80046180` | 260 | `CameraDirector` | `Atan2Units4096`, `ISqrt` | Look angles (pitch from horizontal distance, yaw) of a segment; used for head look-at and the camera. |
| `0x80066420` | 16 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x800664A0` | 200 | `CameraDirector` | `Atan2Units4096` | Throw camera: yaw from the two fighters plus a random preset offset (`FUN_80067DE4`). |
| `0x800669B4` | 24 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x800669CC` | 12 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x80067C8C` | 344 | `CameraDirector` | `Atan2Units4096`, `CameraSourceCopy` | Camera choice: resolves the running camera id through table `0x800243DC`. |
| `0x80067DE4` | 232 | `CameraDirector` |  | Camera presets: random yaw/pitch offsets from table `0x80024184` (halved in some phases). |
| `0x800681F0` | 32 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x80068210` | 24 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x80068228` | 28 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x80068998` | 92 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x800689F4` | 80 | `CameraDirector` |  | Helper of CameraDirector. |
| `0x80068C44` | 588 | `CameraDirector` | `SquareRoot0` | Camera director: the eye point follows the target when farther than 0xE50 units (0x188A for bank type 11). |
| `0x800699F0` | 12 | `CameraDirector`, `FUN_800673E4`, `boot module FUN_800B0A10` |  | Helper of CameraDirector. |

## fight set-up FUN_8002A660

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002D430` | 40 | `fight set-up FUN_8002A660` |  | Helper of fight set-up FUN_8002A660. |
| `0x80036040` | 112 | `fight set-up FUN_8002A660` |  | Helper of fight set-up FUN_8002A660. |
| `0x8004EA84` | 280 | `fight set-up FUN_8002A660` |  | Name plate textures of both fighters (character records) for the HUD, colours 7 and 23. |
| `0x8004ED48` | 84 | `fight set-up FUN_8002A660` |  | Helper of fight set-up FUN_8002A660. |
| `0x8004F55C` | 104 | `fight set-up FUN_8002A660` |  | Helper of fight set-up FUN_8002A660. |
| `0x800519B4` | 228 | `fight set-up FUN_8002A660` |  | Maximum health per mode at fight set-up (`+0x3F8`; handicap table `0x80022858`, team battle 170). |
| `0x80069D90` | 844 | `fight set-up FUN_8002A660`, `fight set-up FUN_8002AB68` |  | Motion bank requests for the next fight (`0x800A08B8..0x800A08CC`): which banks must be loaded. |
| `0x8006A25C` | 484 | `fight set-up FUN_8002A660`, `fight set-up FUN_8002AB68` | `BnsIsLoading`, `BnsResetQueue`, `BnsStartQueuedLoads`, `DivmotLinkBank` | Loads the requested motion banks through the BNS queue (`LoadMotionBank`, `DivmotLinkBank`). |
| `0x8006A440` | 200 | `fight set-up FUN_8002A660`, `fight set-up FUN_8002AB68` | `DivmotLinkBank`, `DivmotMergeSharedSlots` | Links each fighter to its loaded motion bank slot. |
| `0x80076704` | 592 | `fight set-up FUN_8002A660` | `SetPolyFT4`, `SetSemiTrans`, `SetShadeTex` | Fight set-up: per-character hit-effect flipbook tables (`0x800A3970`; the demonstration uses fixed ones). |
| `0x8007A05C` | 28 | `fight set-up FUN_8002A660` |  | Helper of fight set-up FUN_8002A660. |

## RoundFlow

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002D4A8` | 16 | `RoundFlow` |  | Helper of RoundFlow. |
| `0x8002D844` | 124 | `RoundFlow` | `MoveLookup`, `MoveStartOrAdvance`, `TransitionRemap` | Helper of RoundFlow. |
| `0x8002D8C0` | 124 | `RoundFlow` | `MoveLookup`, `MoveStartOrAdvance`, `TransitionRemap` | Helper of RoundFlow. |
| `0x8003D7A8` | 184 | `RoundFlow` |  | Helper of RoundFlow. |
| `0x8003D860` | 164 | `RoundFlow` | `MoveLookup` | Helper of RoundFlow. |
| `0x8003E6D0` | 60 | `RoundFlow` |  | Helper of RoundFlow. |
| `0x8003E70C` | 136 | `RoundFlow` |  | Helper of RoundFlow. |
| `0x8003EBF4` | 96 | `RoundFlow` |  | Helper of RoundFlow. |
| `0x8003EC54` | 160 | `RoundFlow` |  | Helper of RoundFlow. |
| `0x80051AD4` | 388 | `RoundFlow` |  | Carries health between rounds per mode (team battle: remaining health as eighths, others copy `+0x3F4` to `+0x3FC`). |
| `0x8006F750` | 140 | `RoundFlow`, `EffectsUpdate` |  | Helper of RoundFlow. |

## FightMain

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80029848` | 24 | `FightMain` |  | Helper of FightMain. |
| `0x80029E64` | 432 | `FightMain` | `CONCAT11` | Pad state decode for one port (digital/analog type, DualShock capability via the library). |
| `0x8002A014` | 804 | `FightMain` |  | Per-frame pad read for both ports, the multitap/analog flags (`0x800A964C`) and button mapping (`0x80098290`). |
| `0x8004FB84` | 24 | `FightMain` |  | Helper of FightMain. |
| `0x800527D4` | 52 | `FightMain` |  | Helper of FightMain. |
| `0x80078940` | 52 | `FightMain` |  | Helper of FightMain. |
| `0x80092BA8` | 192 | `FightMain` |  | Helper of FightMain. |
| `0x80092C68` | 248 | `FightMain` |  | Pad library: reads a pad attribute (type, capability) from the driver. |
| `0x80092EDC` | 56 | `FightMain` |  | Helper of FightMain. |
| `0x800941A0` | 104 | `FightMain` |  | Helper of FightMain. |

## ReplayUpdate

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002C23C` | 92 | `ReplayUpdate`, `RoundFlow` |  | Helper of ReplayUpdate. |
| `0x80033838` | 168 | `ReplayUpdate` |  | Helper of ReplayUpdate. |
| `0x800338E0` | 252 | `ReplayUpdate` |  | Replay playback: plays recorded sound events on even half-frames. |
| `0x80040E58` | 64 | `ReplayUpdate` | `ReplayRecordSound` | Helper of ReplayUpdate. |
| `0x80040EB8` | 112 | `ReplayUpdate` | `FighterVoice`, `ReplayRecordSound` | Helper of ReplayUpdate. |
| `0x80041038` | 84 | `ReplayUpdate` | `FighterSoundById`, `ReplayRecordSound` | Helper of ReplayUpdate. |
| `0x80069824` | 460 | `ReplayUpdate`, `ReplayRootPosition` | `Atan2Units4096`, `CameraReset` | Replay camera set-up: resets the camera and starts a slow orbit around the fighters. |

## per-frame sound update FUN_8006B9E4

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8006BD2C` | 596 | `per-frame sound update FUN_8006B9E4` | `DsMix` | CD audio: waits for the drive to settle, then sets the XA/CD volume (`0x800A0A38`, mono option `0x800982E4`). |
| `0x8008F26C` | 580 | `per-frame sound update FUN_8006B9E4`, `DsControlF`, `DsControl` |  | libds: queues a CD command (up to 8 pending). |
| `0x8008F9F0` | 148 | `per-frame sound update FUN_8006B9E4` |  | Helper of per-frame sound update FUN_8006B9E4. |
| `0x8008FB70` | 32 | `per-frame sound update FUN_8006B9E4` |  | Helper of per-frame sound update FUN_8006B9E4. |
| `0x8009003C` | 16 | `per-frame sound update FUN_8006B9E4` |  | Helper of per-frame sound update FUN_8006B9E4. |
| `0x80090070` | 36 | `per-frame sound update FUN_8006B9E4` |  | Helper of per-frame sound update FUN_8006B9E4. |
| `0x80090D80` | 72 | `per-frame sound update FUN_8006B9E4`, `DsControl`, `DsControlB` |  | Helper of per-frame sound update FUN_8006B9E4. |

## FighterSounds

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002BDDC` | 64 | `FighterSounds` |  | Helper of FighterSounds. |
| `0x80041E08` | 208 | `FighterSounds` | `FighterSoundById`, `ReplayRecordSound` | Fighter sounds: hit/guard voice selection by damage (sound `0x705D` below 7, …), recorded for replays. |
| `0x80041ED8` | 116 | `FighterSounds` | `FighterSoundById`, `ReplayRecordSound` | Helper of FighterSounds. |
| `0x80041F4C` | 624 | `FighterSounds` | `FighterSoundById`, `ReplayRecordSound` | Fighter sounds: attack shouts for characters 5, 7, 10 and 18 by damage and `rand()` (table "Apdpep"). |
| `0x8004B9B8` | 80 | `FighterSounds` | `SpuInit` | Helper of FighterSounds. |
| `0x80075BFC` | 92 | `FighterSounds`, `FUN_80041C48` |  | Helper of FighterSounds. |

## FighterComposeJoints

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80033C54` | 780 | `FighterComposeJoints` |  | True Ogre's wing and tail sway: the local matrix of joints 5, 6, 18, 19 from the next slot of the cycle 5 → 18 → 19 → 6 ([animation.md](../formats/animation.md#true-ogres-wings-and-tail)). |
| `0x80037F10` | 1908 | `FighterComposeJoints` | `ApplyMatrix`, `ApplyRotMatrix`, `EulerToMatrix`, `MulMatrix0` | Places a fighter's extra part (joint 18 and up) from the part's rest data at `+0x129E` (Euler angles, matrix products). |
| `0x80038684` | 572 | `FighterComposeJoints` | `ApplyMatrixLV`, `SquareRoot0` | Joint helper: transforms a part's anchor offsets by the joint matrix (`+0x8F4 + 0x44·joint`). |
| `0x800388C0` | 348 | `FighterComposeJoints` | `ApplyMatrixLV`, `SquareRoot0` | Joint helper: direction between two joint positions (`+0xC7C`, `+0xD48`), normalised with SquareRoot0. |
| `0x8003B970` | 592 | `FighterComposeJoints` |  | GTE: rotates three packed vectors by a matrix (RTV0) and returns the products. |
| `0x8003BBC0` | 72 | `FighterComposeJoints` |  | Helper of FighterComposeJoints. |

## throw camera presets FUN_80066568

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8006312C` | 224 | `throw camera presets FUN_80066568` |  | Throw camera: starts a cinematic camera for the throw's camera id. |
| `0x8006320C` | 332 | `throw camera presets FUN_80066568` |  | Throw camera: as `0x8006312C`, with the thrower's heading added. |
| `0x800670AC` | 56 | `throw camera presets FUN_80066568` |  | Helper of throw camera presets FUN_80066568. |
| `0x800670E4` | 628 | `throw camera presets FUN_80066568` | `CameraReset` | Camera: starts the move's camera byte as a cinematic or preset when a new move begins (`+0x54`). |
| `0x800677C8` | 80 | `throw camera presets FUN_80066568` |  | Helper of throw camera presets FUN_80066568. |
| `0x80067B14` | 376 | `throw camera presets FUN_80066568` | `CameraChoose`, `CameraReset` | Camera: `CameraChoose` for a fighter's move camera byte, or CameraReset when none. |

## MusicPlay

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8008EA98` | 84 | `MusicPlay`, `FUN_8006B47C`, `per-frame sound update FUN_8006B9E4` |  | Helper of MusicPlay. |
| `0x8008ECDC` | 112 | `MusicPlay`, `FUN_8006B47C`, `per-frame sound update FUN_8006B9E4` |  | Helper of MusicPlay. |
| `0x8008F4B0` | 848 | `MusicPlay`, `FUN_8006B47C`, `per-frame sound update FUN_8006B9E4` | `DsPosToInt` | libds: CD read command with retries (music and streams). |
| `0x8008FF2C` | 124 | `MusicPlay`, `FUN_8006B47C`, `per-frame sound update FUN_8006B9E4` |  | Helper of MusicPlay. |
| `0x800900E4` | 296 | `MusicPlay`, `FUN_8006B47C`, `per-frame sound update FUN_8006B9E4` |  | libds: flushes the drive and issues a command with parameters. |
| `0x80090D38` | 72 | `MusicPlay`, `FUN_8006B47C`, `per-frame sound update FUN_8006B9E4` |  | Helper of MusicPlay. |

## FighterSetupParts

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8003161C` | 868 | `FighterSetupParts` | `GetTPage`, `SetPolyGT4` | FighterSetupParts: builds the `POLY_GT4` packets of a fighter's textured parts (texture pages per part). |
| `0x80034010` | 12 | `FighterSetupParts` |  | Helper of FighterSetupParts. |
| `0x80035008` | 96 | `FighterSetupParts` |  | Helper of FighterSetupParts. |
| `0x80035068` | 40 | `FighterSetupParts` |  | Helper of FighterSetupParts. |
| `0x80035090` | 28 | `FighterSetupParts` |  | Helper of FighterSetupParts. |

## StageLoad

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80048314` | 16 | `StageLoad`, `FUN_80036BC8` |  | Helper of StageLoad. |
| `0x8006A0DC` | 56 | `StageLoad` |  | Helper of StageLoad. |
| `0x8006CAE8` | 40 | `StageLoad`, `FUN_80036BC8` |  | Helper of StageLoad. |
| `0x800B4A68` | 32 | `StageLoad` |  | Helper of StageLoad. |
| `0x800B5CA4` | 32 | `StageLoad` |  | Helper of StageLoad. |

## FighterAnimate

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80031980` | 1232 | `FighterAnimate` |  | Bank type 4 (Yoshimitsu, or Mokujin as type 4): projects four points of the sword joint (`+0xB9C`) and sizes a trail by depth. |
| `0x80038B60` | 100 | `FighterAnimate` |  | Helper of FighterAnimate. |
| `0x8003B74C` | 192 | `FighterAnimate` | `FighterDrawParts`, `ShadowBuildPrims` | Helper of FighterAnimate. |
| `0x800797DC` | 1452 | `FighterAnimate` | `ApplyRotMatrixLV`, `CONCAT22`, `SetRotMatrix`, `SetTransMatrix` | Draws a primitive spanning two joint positions (`+0xCC0`, `+0xD8C`) through the view matrix. |

## camera streams FUN_800669D8

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80038F2C` | 12 | `camera streams FUN_800669D8`, `FUN_800673E4` |  | Helper of camera streams FUN_800669D8. |
| `0x800641D4` | 232 | `camera streams FUN_800669D8`, `FUN_80068244`, `FUN_8006879C` | `Atan2Units4096`, `ISqrt` | Camera source: position and look angles from an eye and a target point. |
| `0x80064308` | 96 | `camera streams FUN_800669D8`, `FUN_80068244`, `FUN_8006879C` |  | Helper of camera streams FUN_800669D8. |
| `0x800666E0` | 724 | `camera streams FUN_800669D8`, `FUN_800673E4` |  | Camera streams: fetches the next stream frame (`FUN_80038F38`) into the camera source. |

## ReplayStart

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8004A910` | 12 | `ReplayStart` |  | Helper of ReplayStart. |
| `0x8004A91C` | 56 | `ReplayStart` |  | Helper of ReplayStart. |
| `0x8004AAD4` | 340 | `ReplayStart`, `RoundFlow`, `FUN_8003EE94` | `FlipbookSetup`, `SetPolyFT4`, `SetSemiTrans`, `SetShadeTex` | Resets the landing-dust ring and its FT4 packets. |
| `0x80076954` | 72 | `ReplayStart`, `RoundFlow`, `FUN_8003EE94` |  | Helper of ReplayStart. |

## EffectSpawn

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8006E9A0` | 168 | `EffectSpawn`, `FUN_80076F10` |  | Helper of EffectSpawn. |
| `0x8006EA48` | 168 | `EffectSpawn`, `FUN_80076F10` |  | Helper of EffectSpawn. |
| `0x8006EAF0` | 168 | `EffectSpawn`, `FUN_80076F10` |  | Helper of EffectSpawn. |
| `0x8006EB98` | 168 | `EffectSpawn`, `FUN_80076F10` |  | Helper of EffectSpawn. |

## FUN_800B0D08

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8008135C` | 52 | `FUN_800B0D08` |  | Helper of FUN_800B0D08. |
| `0x8008148C` | 20 | `FUN_800B0D08` |  | Helper of FUN_800B0D08. |
| `0x800814AC` | 12 | `FUN_800B0D08`, `FUN_800B0DC0` |  | Helper of FUN_800B0D08. |
| `0x800814BC` | 12 | `FUN_800B0D08`, `FUN_800B0DC0` |  | Helper of FUN_800B0D08. |

## DSFILE_OBJ_904

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x800900A4` | 64 | `DSFILE_OBJ_904` |  | Helper of DSFILE_OBJ_904. |
| `0x8009139C` | 304 | `DSFILE_OBJ_904` | `DsDataCallback`, `DsLastPos`, `VSync` | libds file search helper. |
| `0x8009174C` | 112 | `DSFILE_OBJ_904` | `VSync` | Helper of DSFILE_OBJ_904. |
| `0x800917D0` | 140 | `DSFILE_OBJ_904` | `DsDataCallback` | Helper of DSFILE_OBJ_904. |

## main

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8002987C` | 16 | `main`, `caseD_0`, `caseD_1` |  | Helper of main. |
| `0x8004C96C` | 120 | `main`, `caseD_0`, `caseD_1` | `ClearOTag` | Helper of main. |
| `0x8008205C` | 12 | `main`, `caseD_0`, `caseD_1` |  | Helper of main. |

## per-frame input FUN_80029918

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x800298C8` | 80 | `per-frame input FUN_80029918` | `GetRCnt` | Helper of per-frame input FUN_80029918. |
| `0x80029B78` | 188 | `per-frame input FUN_80029918`, `boot module FUN_800B0A10` |  | Helper of per-frame input FUN_80029918. |
| `0x80029C7C` | 488 | `per-frame input FUN_80029918` |  | Moves the 2D OT buckets so HUD and text draw over the scene (skipped in modes 7 and 8). |

## FighterTransitionBlend

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x8003CB20` | 36 | `FighterTransitionBlend` |  | Helper of FighterTransitionBlend. |
| `0x8003CC84` | 44 | `FighterTransitionBlend` |  | Helper of FighterTransitionBlend. |
| `0x8003CCB0` | 64 | `FighterTransitionBlend` |  | Helper of FighterTransitionBlend. |

## PairwiseDistances

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80043C40` | 72 | `PairwiseDistances` |  | Helper of PairwiseDistances. |
| `0x80043CD8` | 84 | `PairwiseDistances` |  | Helper of PairwiseDistances. |
| `0x800B2EEC` | 68 | `PairwiseDistances` |  | Helper of PairwiseDistances. |

## FighterLoadCharacter

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80056488` | 16 | `FighterLoadCharacter`, `StageLoad`, `FUN_80036BC8` |  | Helper of FighterLoadCharacter. |
| `0x800754E8` | 64 | `FighterLoadCharacter` |  | Helper of FighterLoadCharacter. |
| `0x80075528` | 36 | `FighterLoadCharacter` |  | Helper of FighterLoadCharacter. |

## SoundInit

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80087F4C` | 48 | `SoundInit` | `ResetCallback` | Helper of SoundInit. |
| `0x8008AD7C` | 16 | `SoundInit` |  | Helper of SoundInit. |
| `0x8008B36C` | 32 | `SoundInit` |  | Helper of SoundInit. |

## Other documented callers (see the caller column)

| Routine | Bytes | Callers (documented) | Library calls | Note |
|---|---:|---|---|---|
| `0x80029084` | 144 | `PadVibrate` |  | Helper of PadVibrate. |
| `0x8002BBE0` | 72 | `FUN_8003ECF4` |  | Helper of FUN_8003ECF4. |
| `0x8002C384` | 36 | `MoveStartOrAdvance` |  | Helper of MoveStartOrAdvance. |
| `0x8002D3A8` | 36 | `AiInitRound` |  | Helper of AiInitRound. |
| `0x8002D458` | 8 | `MoveStep` |  | Helper of MoveStep. |
| `0x8002D460` | 8 | `MoveStep` |  | Helper of MoveStep. |
| `0x80031350` | 72 | `BlendDstFrame` |  | Helper of BlendDstFrame. |
| `0x800323C4` | 8 | `FUN_8003EE94` |  | Helper of FUN_8003EE94. |
| `0x8003401C` | 260 | `FighterSetupModel` | `MoveImage` | Gon (character 17): sets up his extra texture pages (eyes). |
| `0x80034950` | 72 | `FUN_8002BFCC`, `FighterMovePhysics` | `HandFaceCommand` | Helper of FUN_8002BFCC. |
| `0x80036CFC` | 44 | `FighterDrawParts` |  | Helper of FighterDrawParts. |
| `0x80037EAC` | 100 | `FighterSetupPart` |  | Helper of FighterSetupPart. |
| `0x8003A08C` | 12 | `FUN_80037A68`, `FighterDrawParts` |  | Helper of FUN_80037A68. |
| `0x8003A0C8` | 40 | `FighterSetupPart` |  | Helper of FighterSetupPart. |
| `0x8003A564` | 40 | `FUN_8003AA6C` | `SetBackColor` | Helper of FUN_8003AA6C. |
| `0x8003A810` | 44 | `MatrixOrthonormalize` | `VectorNormal` | Helper of MatrixOrthonormalize. |
| `0x8003BC08` | 116 | `GonEyesFollow`, `PoseBuildMatrices` |  | Helper of GonEyesFollow. |
| `0x8003CDC0` | 24 | `FighterMovePhysics` |  | Helper of FighterMovePhysics. |
| `0x8003E158` | 168 | `HudRoundUpdate` | `SoundPlayFighter` | Helper of HudRoundUpdate. |
| `0x8003EA98` | 200 | `FUN_8003E7C4` |  | Round result: decides the round winner by `+0x44` round wins and sets the match-over flag `0x800AFF71`. |
| `0x80040C80` | 36 | `FUN_8002BFCC` |  | Helper of FUN_8002BFCC. |
| `0x80040D50` | 24 | `InputClear` |  | Helper of InputClear. |
| `0x800421BC` | 40 | `HitTest` | `SoundPlayFighter` | Helper of HitTest. |
| `0x80046284` | 288 | `Gon's eyes FUN_800466F8`, `FUN_80046854`, `FUN_80046A38` | `Atan2Units4096`, `ISqrt` | Look angles of a segment (as `0x80046180`), used by Gon's eyes. |
| `0x800463A4` | 180 | `FUN_80046854`, `FUN_80046CB8` | `CameraBuildView` | Helper of FUN_80046854. |
| `0x80046508` | 496 | `Gon's eyes FUN_800466F8`, `FUN_80046854`, `FUN_80046A38` |  | Gon's eyes: eye direction towards a target point in the head frame. |
| `0x800484C8` | 16 | `StageSelectFloor`, `FUN_800489A4` |  | Helper of StageSelectFloor. |
| `0x8004878C` | 536 | `FUN_800489A4` | `DrawSync`, `GsMapModelingData`, `SetPolyGT4`, `SetSemiTrans` | Floor set-up: maps the floor model (`0x8001E36C`, mode 8 `0x8001E6C4`) and builds the `POLY_GT4` grid packets. |
| `0x80048C6C` | 1156 | `FloorDraw` | `SquareRoot0` | FloorDraw: finds the floor point under the camera's view when it looks steeply down (grid centre). |
| `0x8004A5FC` | 160 | `FloorDrawGrid`, `FUN_80049AE0` |  | Helper of FloorDrawGrid. |
| `0x8004A860` | 76 | `FUN_8004AF1C` |  | Helper of FUN_8004AF1C. |
| `0x8004B4B0` | 240 | `HeadLookAt` |  | Head look-at: GTE rotation of the head's axis vectors. |
| `0x8004C804` | 360 | `FUN_8004C420`, `FUN_8004C4B4`, `FUN_8004C528` | `TestEvent` | Memory card: waits for the card events and clears the card (`_card_clear`). |
| `0x8004CFDC` | 44 | `FUN_8004C1A8`, `FUN_8004C528`, `FUN_800532E8` |  | Helper of FUN_8004C1A8. |
| `0x80051220` | 36 | `TransitionScreen` |  | Helper of TransitionScreen. |
| `0x800513FC` | 56 | `FUN_800532E8` |  | Helper of FUN_800532E8. |
| `0x800514E0` | 12 | `ChallengerJoin` |  | Helper of ChallengerJoin. |
| `0x80052E64` | 12 | `TransitionScreen` |  | Helper of TransitionScreen. |
| `0x80052F18` | 148 | `ScreenOverlayLoad`, `RankingLoad`, `FightPrepare` |  | Helper of ScreenOverlayLoad. |
| `0x80061D2C` | 20 | `AiUpdate` |  | Helper of AiUpdate. |
| `0x80062DEC` | 112 | `StageBackgroundDraw` |  | Helper of StageBackgroundDraw. |
| `0x80063FA4` | 68 | `FUN_800661C0` |  | Helper of FUN_800661C0. |
| `0x80066430` | 112 | `FUN_80068244` | `Atan2Units4096` | Helper of FUN_80068244. |
| `0x80067FAC` | 40 | `CameraReset` |  | Helper of CameraReset. |
| `0x80068E90` | 424 | `demonstration camera FUN_800693E8` | `CameraFrameFighters` | Demonstration camera: random framing offsets from `0x80098930`. |
| `0x80069038` | 848 | `demonstration camera FUN_800693E8` | `Atan2Units4096` | Demonstration camera: the orbit and distance for the current shot. |
| `0x8006C4E4` | 64 | `BnsResetQueue` | `BnsIsLoading` | Helper of BnsResetQueue. |
| `0x8006C538` | 28 | `FUN_80052D1C` |  | Helper of FUN_80052D1C. |
| `0x8006CB10` | 48 | `StageBackgroundDraw` |  | Helper of StageBackgroundDraw. |
| `0x8006E194` | 92 | `FUN_8006DC44` |  | Helper of FUN_8006DC44. |
| `0x8006E21C` | 144 | `FUN_80076F10` | `Atan2Units4096` | Helper of FUN_80076F10. |
| `0x8006E2AC` | 188 | `FUN_80076F10` |  | Helper of FUN_80076F10. |
| `0x8006F4BC` | 52 | `FUN_8003E2F8` |  | Helper of FUN_8003E2F8. |
| `0x8006F584` | 84 | `FighterVoice`, `FighterSoundById` |  | Helper of FighterVoice. |
| `0x80075C58` | 100 | `SoundOpenCommonBanks`, `FUN_8007517C` | `SsVabOpenHeadSticky`, `SsVabTransBody`, `SsVabTransCompleted` | Helper of SoundOpenCommonBanks. |
| `0x800761D8` | 172 | `FUN_80075CBC`, `FighterVibrate` |  | Helper of FUN_80075CBC. |
| `0x80077878` | 48 | `FighterSetupModel` |  | Helper of FighterSetupModel. |
| `0x8007A078` | 28 | `FUN_80036140` |  | Helper of FUN_80036140. |
| `0x8007A27C` | 16 | `FUN_80052D58`, `LoadOverlaySync`, `_patch_pad` |  | Helper of FUN_80052D58. |
| `0x8007A28C` | 16 | `FUN_80052D58`, `LoadOverlaySync`, `_remove_ChgclrPAD` |  | Helper of FUN_80052D58. |
| `0x8007A83C` | 52 | `FUN_8003E408`, `FUN_80052650`, `FUN_8005497C` |  | Helper of FUN_8003E408. |
| `0x8008165C` | 32 | `CameraSetProjection`, `boot module FUN_800B0A10`, `FUN_800B0D08` |  | Helper of CameraSetProjection. |
| `0x80081F3C` | 76 | `GsInitGraph` | `InitGeom`, `SetFarColor` | Helper of GsInitGraph. |
| `0x80082B4C` | 24 | `GsSetDrawBuffOffset`, `FUN_800B0D08` |  | Helper of GsSetDrawBuffOffset. |
| `0x80082B6C` | 12 | `CameraSetProjection`, `boot module FUN_800B0A10`, `FUN_800B0D08` |  | Helper of CameraSetProjection. |
| `0x800851CC` | 28 | `StSetStream` |  | Helper of StSetStream. |
| `0x800866B4` | 12 | `INTR_OBJ_194` |  | Helper of INTR_OBJ_194. |
| `0x80086B50` | 16 | `SetDefDrawEnv`, `PutDispEnv`, `SYS_OBJ_CD0` |  | Helper of SetDefDrawEnv. |
| `0x80088FBC` | 12 | `_SsSndStop` |  | Helper of _SsSndStop. |
| `0x8008C03C` | 36 | `SpuStart` | `DMACallback` | Helper of SpuStart. |
| `0x8008C71C` | 36 | `_SsVmFlush` |  | Helper of _SsVmFlush. |
| `0x8008CC3C` | 32 | `SoundSelectBanks` |  | Helper of SoundSelectBanks. |
| `0x8008D6DC` | 36 | `FUN_8007517C`, `_SsVmFlush` |  | Helper of FUN_8007517C. |
| `0x8008DCAC` | 40 | `_SsVmInit`, `VS_VH_OBJ_90`, `VS_VH_OBJ_174` |  | Helper of _SsVmInit. |
| `0x8008DCD4` | 24 | `VS_VH_OBJ_90` |  | Helper of VS_VH_OBJ_90. |
| `0x8008F800` | 496 | `DsControl`, `DsControlB` |  | libds: returns the result of the last queued command. |
| `0x8008FA84` | 144 | `DsGetToc` | `DsEndReadySystem` | Helper of DsGetToc. |
| `0x8008FB60` | 16 | `FUN_8008FB14`, `DsGetToc`, `DSREADY_OBJ_FC` |  | Helper of FUN_8008FB14. |
| `0x8008FB90` | 32 | `DsSearchFile` |  | Helper of DsSearchFile. |
| `0x8008FFD8` | 24 | `FUN_8008FB14`, `DsGetDiskType` |  | Helper of FUN_8008FB14. |
| `0x80090000` | 16 | `DSREADY_OBJ_FC`, `DSREADY_OBJ_490` |  | Helper of DSREADY_OBJ_FC. |
| `0x80090010` | 12 | `DsLastPos`, `DSREADY_OBJ_FC`, `DSREADY_OBJ_490` |  | Helper of DsLastPos. |
| `0x8009002C` | 16 | `DSREADY_OBJ_490` |  | Helper of DSREADY_OBJ_490. |
| `0x8009004C` | 36 | `DsControl`, `DsControlB` |  | Helper of DsControl. |
| `0x80090094` | 16 | `DsSearchFile` |  | Helper of DsSearchFile. |
| `0x800B22D0` | 64 | `FUN_8004EFF8` |  | Helper of FUN_8004EFF8. |
| `0x800B2310` | 4 | `FUN_8004EFF8` |  | Helper of FUN_8004EFF8. |
| `0x800B2E90` | 20 | `HudRoundUpdate` |  | Helper of HudRoundUpdate. |
| `0x800B4800` | 68 | `CpuOrPadInput` |  | Helper of CpuOrPadInput. |
| `0x800B7AEC` | 68 | `CpuOrPadInput` |  | Helper of CpuOrPadInput. |
