/* Tekken 3 (PSX) data structures.
 * Field names reflect current understanding; see docs/research.
 * Offsets are verified against loader/renderer code unless marked "unk".
 */

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef signed char s8;
typedef short s16;
typedef int s32;

/* One 56-byte joint row of a .kmd model. Rows start at KMD+0x10. */
typedef struct KmdRow {
    u32 verts;         /* +00 vertex block (relocated pointer) */
    u32 vertVariants;  /* +04 pointer to 41 alternative vertex blocks (hand poses) or 0 */
    u32 normals;       /* +08 normal block */
    u32 faces;         /* +0C face block: FT3, FT4, GT3, GT4 groups */
    u32 texmap;        /* +10 material/UV block used to prebuild GPU primitives */
    s32 ofsX;          /* +14 joint offset from parent, model units */
    s32 ofsY;          /* +18 */
    s32 ofsZ;          /* +1C stored negated in the fighter matrix setup */
    s32 parent;        /* +20 parent part index or -1 */
    u32 unk24;
    u32 unk28;
    u32 unk2C;
    u32 active;        /* +30 1 when the row has geometry */
    u32 unk34;
} KmdRow;

typedef struct KmdHeader {
    u32 rowCount;      /* 27 */
    u32 scalePercent;  /* model scale in percent; fighter scale = value*4096/100 */
    char magic[4];     /* "3DMK" */
    u32 zero;
    KmdRow rows[27];
} KmdHeader;

/* Per-fighter drawable part, 22 per fighter at fighter+0x4F0. */
typedef struct FighterPart {
    u32 flags;         /* 2 = drawable */
    void *matrix;      /* joint matrix block (fighter+0x8F4+idx*0x44) */
    KmdRow *mesh;      /* primary mesh row */
    KmdRow *mesh2;     /* optional second mesh row */
    u32 unk10;
    u32 unk14;
    void *prims[2];    /* prebuilt GPU primitives, one per display buffer */
    void *prims2[2];
} FighterPart;

/* divmot*.bin header after relocation (pointers). */
typedef struct DivmotHeader {
    u8 zero;
    u8 type;
    u16 moveCount;
    void *branches;    /* +04 sec0: 12-byte rows */
    void *moves;       /* +08 sec1: 56-byte move rows */
    u32 *moveIndex;    /* +0C sec2: 4023 move-slot -> move row */
    u16 *sec3;         /* +10 */
    u32 *sec4;         /* +14 */
    u16 *ownMask;      /* +18 sec5: bit set = slot defined by this bank */
    u8 *animData;      /* +1C sec6 */
    void *sec7;
    void *sec8;
    void *sec9;        /* +28 */
    void *sec10;
    void *sec11;
    void *sec12;
    u32 end;           /* +3C */
} DivmotHeader;

typedef struct DivMove {
    u32 anim;          /* +00 animation stream (bank sec6 or divmot99 when >= 0x40000000) */
    u32 unk04;
    u32 unk08;
    u32 branches;      /* +0C first sec0 row of this move */
    u32 unk10;
    u16 unk14;         /* computed at load by FUN_8002d51c */
    u16 unk16;
    u8 animFirstByte;  /* +18 copy of anim[0] */
    u8 unk19;
    u16 unk1A;
    u32 sec3Ref;       /* +1C */
    u32 sec4Ref;       /* +20 */
    u32 unk24;
    u32 special;       /* +28 */
    u32 unk2C;
    u32 unk30;
    u32 unk34;
} DivMove;

/* BEGIN generated Fighter */
typedef struct Fighter {
    s32 posX;                          /* +0x0000 anchor of the running move (root = anchor + rotated animation displacement) */
    s32 posY;                          /* +0x0004 */
    s32 posZ;                          /* +0x0008 */
    s16 tiltX;                         /* +0x000C root rotation x (root matrix uses -tiltX) */
    s16 facing;                        /* +0x000E 16-bit angle */
    s16 tiltZ;                         /* +0x0010 root rotation z (root matrix uses -tiltZ) */
    s16 playerIndex;                   /* +0x0012 0/1, VRAM/CLUT offsets */
    s16 costumeKey;                    /* +0x0014 charId*4 + costume: index into g_charRecords */
    s16 bankType;                      /* +0x0016 motion bank type (character record +9) */
    s16 charId;                        /* +0x0018 selection index 0-22 (20 = True Ogre, 21+ Tekken Force enemies) */
    s16 voiceSet;                      /* +0x001A character record +8: index into g_charVoices */
    s16 costumeSlot;                   /* +0x001C 0..51 */
    u8 index;                          /* +0x001E fighter index 0/1 (2 = third fighter in mode 8) */
    u8 curOppIndex;                    /* +0x001F the opponent currently faced (FightFrame, FUN_8002BFCC); in mode 8 it follows target changes (side flag, Force AI) */
    u8 oppIndex;                       /* +0x0020 default opponent index */
    u8 throwPartner;                   /* +0x0021 */
    u8 lastAttacker;                   /* +0x0022 index of the fighter whose hit was applied */
    u8 lastHitTarget;                  /* +0x0023 */
    s16 rootDx;                        /* +0x0024 root displacement from animation */
    s16 rootDy;                        /* +0x0026 */
    s16 rootDz;                        /* +0x0028 */
    s16 targetDir;                     /* +0x002A */
    s16 heading;                       /* +0x002C body heading (16-bit angle); facing follows it */
    s16 headingDelta;                  /* +0x002E heading - targetDir */
    s16 relAngle;                      /* +0x0030 abs(headingDelta): 0 facing the opponent, 0x8000 back turned */
    s16 facingQuadrant;                /* +0x0032 own heading vs opponent direction: 0 front, 1/3 sides, 2 back */
    s16 aimDir;                        /* +0x0034 targetDir or targetDir+0x8000, whichever is nearer the heading (updated beyond 0x200 units) */
    s16 trackAccum;                    /* +0x0036 */
    s16 oppToSelfDir;                  /* +0x0038 direction from opponent to self */
    s16 oppHeading;                    /* +0x003A */
    s16 oppHeadingDelta;               /* +0x003C */
    s16 oppRelAngle;                   /* +0x003E abs(oppHeadingDelta) */
    s16 oppQuadrant;                   /* +0x0040 opponent heading vs direction to self: 0 facing me, 1/3 sides, 2 back turned */
    s16 oppAimDir;                     /* +0x0042 */
    s16 roundWins;                     /* +0x0044 rounds won in the match; +1 per round won, both on a draw (FUN_8003E7C4); compared with the rounds to win 0x800AE2C4; saved and restored around a fighter reload (FUN_8002A5D8/FUN_8002A634) */
    s16 roundWon;                      /* +0x0046 round result (FUN_8003E7C4): 1 won, −1 lost; a draw gives both −1, or 1 to a side that reaches the rounds to win */
    s16 winPose;                       /* +0x0048 win-pose variant, 1 + frame parity (FUN_8003EB60); after a time-out the loser's −1 (both 0 when tied, FUN_8003EBF4); the round end waits until a positive variant's move has played */
    u8 unk004A[2];
    void* rootMove;                    /* +0x004C move row driving root motion */
    s16 rootFrame;                     /* +0x0050 */
    u8 unk0052[2];
    void* poseMove;                    /* +0x0054 move row driving the pose */
    s16 poseFrame;                     /* +0x0058 */
    s16 eventFrame;                    /* +0x005A the pose frame when the frame events last ran (MoveEvents runs the events after it up to the pose frame; blend source frame = value − 1) */
    s16 moveFrame;                     /* +0x005C frames since the move started (1 at start unless the frame counter is kept) */
    s16 damage;                        /* +0x005E damage of the running move (0 = not an attack) */
    u32 state;                         /* +0x0060 move +0x04: bits 0-2 posture (crouch/stand/down), 3-4 guard, 11-15 class */
    u16 attack;                        /* +0x0064 move +0x08: bits 0-2 postures hit, 3-4 guards that block, high byte level id */
    u16 guard;                         /* +0x0066 state bits 3-4 while guarding is possible, else 0 */
    u8 attackHi;                       /* +0x0068 attack >> 8: 1 low, 2 mid, 4 high, 6 unblockable/ground, 8 throw */
    u8 stateClass;                     /* +0x0069 state bits 11-15 (12 = jump) */
    s16 holdFrames;                    /* +0x006A frames to hold the last pose frame (-1 none) */
    s16 branchWindow;                  /* +0x006C remaining frames of the matched branch window */
    s16 frameStep;                     /* +0x006E +1 forward, -1 playing backwards */
    u8 unk0070[4];
    s16 throwState;                    /* +0x0074 0 idle; >0 thrower step count; <0 throw victim */
    s16 hitFreeze;                     /* +0x0076 freeze frames left (pose does not advance) */
    s32 slideStepX;                    /* +0x0078 */
    s32 slideStepZ;                    /* +0x007C */
    s16 reactChain;                    /* +0x0080 counts consecutive reaction moves (0x400 flag chains) */
    u8 slideState;                     /* +0x0082 1 armed, 2 sliding (transitions 0x10/0x12/0x13) */
    u8 hitDone0;                       /* +0x0083 this move already hit fighter 0 */
    u8 hitDone1;                       /* +0x0084 this move already hit fighter 1 */
    u8 hitDone2;                       /* +0x0085 this move already hit Tekken Force fighter 2 (HitTest, index - 2) */
    u8 hitDone3;                       /* +0x0086 the same for fighter 3; also set to 1 when a queued move starts */
    u8 wasHitThisMove;                 /* +0x0087 */
    u8 contactThisMove;                /* +0x0088 */
    u8 guardedPrev;                    /* +0x0089 copy of +0xCF at move start */
    u8 inReaction;                     /* +0x008A copy of +0xD0 at move start */
    u8 branchKind;                     /* +0x008B 1 reaction, 2 input branch, 3 look-ahead branch, 4 move end */
    u8 condFlagUsed;                   /* +0x008C set by branch conditions 0x3A-0x3C */
    u8 unk008D[1];
    s16 launchArmed;                   /* +0x008E */
    s16 airKind;                       /* +0x0090 0-5, row of 0x8001A630 (ground offset, air move slot) */
    s16 ballistic;                     /* +0x0092 1 while following a launch trajectory */
    s16 juggleCount;                   /* +0x0094 air hits taken during the current launch */
    s16 groundOffset;                  /* +0x0096 */
    s16 airSpeed;                      /* +0x0098 horizontal launch speed */
    s16 airVelX;                       /* +0x009A */
    s16 airVelY;                       /* +0x009C */
    s16 airVelZ;                       /* +0x009E */
    s16 curSlot;                       /* +0x00A0 move slot of the running move */
    s16 curTransition;                 /* +0x00A2 transition code that started the running move */
    s32 slideTargetX;                  /* +0x00A4 point reached in 16 frames when slideToPoint is 1 (no writer of slideToPoint=1 in the code) */
    s32 slideTargetZ;                  /* +0x00A8 */
    s32 oppStartX;                     /* +0x00AC opponent root at move start */
    s32 oppStartZ;                     /* +0x00B0 */
    u8 attackSegCount;                 /* +0x00B4 1 or 2 joint pairs in the move attack descriptor, 0 without an active window */
    u8 crouchMove;                     /* +0x00B5 move flag 0x2000 */
    u8 stepKind;                       /* +0x00B6 1/2 from transitions 0x1A/0x1B */
    u8 attackClass;                    /* +0x00B7 move +0x14 bits 14-15 */
    u8 airPhase;                       /* +0x00B8 root follows animation: 0 xyz, 1 none (launched), 2 y only (slide) */
    u8 trackMode;                      /* +0x00B9 0..12, see transitions */
    u8 moveFlagBA;                     /* +0x00BA cleared at move start and at reset */
    u8 moveFlagBB;                     /* +0x00BB cleared at reset */
    u8 skipStepPhysics;                /* +0x00BC cleared at move start; FighterMovePhysics skips its step handling while set */
    u8 attackPending;                  /* +0x00BD 1 while the running move's damage is still to come or the opponent's power timer runs */
    u8 anchorDirty;                    /* +0x00BE */
    u8 slideToPoint;                   /* +0x00BF */
    u8 resetFlagC0;                    /* +0x00C0 cleared at reset; no reader found */
    u8 applyEndTurn;                   /* +0x00C1 add move +0x12 to heading at next move start */
    u8 invulnerable;                   /* +0x00C2 */
    u8 active;                         /* +0x00C3 */
    u8 inThrow;                        /* +0x00C4 */
    u8 isCpu;                          /* +0x00C5 fighter is driven by the CPU AI (InputSource) */
    u8 sideFlag;                       /* +0x00C6 mirrors stick left/right */
    u8 fixedFacing;                    /* +0x00C7 */
    u8 fixedFacingSide;                /* +0x00C8 */
    u8 noLookAt;                       /* +0x00C9 disables the head look-at (and Gon's eyes); in mode 8 set for CPU and fixed-facing fighters */
    u8 humanGuard;                     /* +0x00CA set for human fighters outside mode 5; moves with state bit 8 keep their guard only when set */
    u8 unk00CB[1];
    s16 lastExtraDamage;               /* +0x00CC HitExtraDamage of the last HitApply */
    u8 gotHit;                         /* +0x00CE hit (or guarded) this frame */
    u8 guarded;                        /* +0x00CF last applied hit was guarded */
    u8 hitClean;                       /* +0x00D0 last applied hit connected */
    u8 contact;                        /* +0x00D1 own attack made contact this move */
    u8 whiffed;                        /* +0x00D2 active window ended without contact */
    u8 counterHit;                     /* +0x00D3 last applied hit was a counter hit */
    u8 closeHit;                       /* +0x00D4 last applied hit used the close-range entry (+0x34) */
    u8 bodyContact;                    /* +0x00D5 pushed apart by BodySeparate this frame (conditions 0x33/0x34); cleared by FUN_80043F40 */
    u8 bodyContactWith[3];             /* +0x00D6 per other fighter index */
    u8 noBodyPush;                     /* +0x00D9 set by ArenaBounds when crossing the Tekken Ball court; body separation skipped when both are set */
    u8 moveChanged;                    /* +0x00DA new move differs from the previous one */
    u8 inAir;                          /* +0x00DB move air window [+0x19,+0x1A] or juggled (+0x94) */
    u8 landedA;                        /* +0x00DC */
    u8 landedB;                        /* +0x00DD */
    u8 ko;                             /* +0x00DE */
    u8 aboutToHit;                     /* +0x00DF damage move within 3 frames of its first active frame */
    u8 tapLP;                          /* +0x00E0 LatchButtonTaps: LP newly pressed; all three cleared once no punch button is newly pressed (conditions 0x3A-0x3C) */
    u8 tapRP;                          /* +0x00E1 */
    u8 tapBoth;                        /* +0x00E2 LP and RP held with one of them newly pressed */
    u8 activeSegs;                     /* +0x00E3 attack segments live this frame (0 outside [+0x2D,+0x2E]) */
    u8 extraKind;                      /* +0x00E4 HitExtraDamage mode */
    u8 blendActive;                    /* +0x00E5 */
    u8 forcedHit;                      /* +0x00E6 */
    u8 forcedHitIn;                    /* +0x00E7 */
    s16 lastDamage;                    /* +0x00E8 abs(damage) of the last applied hit */
    s16 damageOverride;                /* +0x00EA used instead of move damage (reversals) */
    s16 extraDamage;                   /* +0x00EC */
    s16 hitFreezeIn;                   /* +0x00EE freeze frames received from the attacker move byte +0x2C */
    u8 unk00F0[4];
    u32 distAdj;                       /* +0x00F4 distance to opponent minus size adjustment */
    u32 dist;                          /* +0x00F8 distance to opponent */
    s32 dirX;                          /* +0x00FC x offset to the opponent (PairwiseDistances; ×10 on the fallback path) */
    s32 dirZ;                          /* +0x0100 z offset to the opponent (0 on the fallback path) */
    s16 hitCooldown;                   /* +0x0104 no hit tests while > 0 */
    s16 pushFrames;                    /* +0x0106 */
    s16 pushSpeed;                     /* +0x0108 */
    s16 pushTableFrames;               /* +0x010A */
    s16 pushDir;                       /* +0x010C */
    u8 unk010E[2];
    void* pushTable;                   /* +0x0110 */
    s16 turnFrames;                    /* +0x0114 */
    s16 turnStep;                      /* +0x0116 */
    s16 recoverMash;                   /* +0x0118 decreased by button presses */
    s16 recoverFrames;                 /* +0x011A */
    s16 attackAlert;                   /* +0x011C 9 frames after a move with flag 0x800 starts */
    u8 unk011E[4];
    s16 powerTimer;                    /* +0x0122 120 after move flag 0x10000; disables guard, forces counter hits */
    s16 pushRepeat;                    /* +0x0124 */
    s16 pushRepeatTimer;               /* +0x0126 */
    s16 stepCooldown;                  /* +0x0128 blocks branch rows with flag 0x1C */
    u8 unk012A[2];
    s32 placedX;                       /* +0x012C anchor saved by FUN_800431B4 when the fighter is placed for a round (ArenaBounds pull-back target) */
    s32 placedZ;                       /* +0x0130 */
    s16 prevPoseFrame;                 /* +0x0134 */
    s16 prevSlot;                      /* +0x0136 */
    s16 prevMoveUnk10;                 /* +0x0138 */
    s16 pushRepeatTrans;               /* +0x013A */
    u8 hitSlots[88];                   /* +0x013C 2 x 0x2C hit records (fields from +0x1C) */
    void* bestHitSlot;                 /* +0x0194 */
    s16 entryFrame;                    /* +0x0198 */
    s16 transition;                    /* +0x019A */
    s16 transBit7;                     /* +0x019C */
    s16 transBit6;                     /* +0x019E */
    s16 moveSlot;                      /* +0x01A0 current move slot */
    u8 unk01A2[2];
    void* moveRow;                     /* +0x01A4 current move row */
    void* reaction;                    /* +0x01A8 reaction record */
    u8 attackSegs[96];                 /* +0x01AC 4 x 24-byte segments */
    u8 hurtZones[280];                 /* +0x020C 14 x 20-byte cylinders */
    u8 bodyPoints[128];                /* +0x0324 8 x 16-byte points */
    s32 prevHurtZone[3];               /* +0x03A4 copy of the first hurt-zone words from the previous CollisionShapesUpdate */
    u8 unk03B0[8];
    s32 prevRootX;                     /* +0x03B8 root of the previous frame (FighterVelocity) */
    s32 prevRootY;                     /* +0x03BC */
    s32 prevRootZ;                     /* +0x03C0 */
    s32 velX;                          /* +0x03C4 */
    s32 velY;                          /* +0x03C8 */
    s32 velZ;                          /* +0x03CC */
    s32 atkDirX;                       /* +0x03D0 direction of first attack segment */
    s32 atkDirY;                       /* +0x03D4 */
    s32 atkDirZ;                       /* +0x03D8 */
    s32 hitDirX;                       /* +0x03DC attacker atkDir copied on hit */
    s32 hitDirY;                       /* +0x03E0 */
    s32 hitDirZ;                       /* +0x03E4 */
    s32 bodyPushX;                     /* +0x03E8 BodySeparate correction added to anchor and root */
    s32 bodyPushY;                     /* +0x03EC */
    s32 bodyPushZ;                     /* +0x03F0 */
    s32 health;                        /* +0x03F4 16.16 fixed */
    s32 healthMax;                     /* +0x03F8 */
    s32 carriedHealth;                 /* +0x03FC health carried into the next round when 0x800AFF59 is set (FUN_8002BFCC) */
    s16 healthLeft;                    /* +0x0400 health in 1/4096 of the maximum at the round result (FUN_8003E6D0); cleared at reset */
    u16 inDir;                         /* +0x0402 one-hot direction 1 << (d + 4) */
    u16 inPressed;                     /* +0x0404 buttons pressed this frame */
    u16 inHeld;                        /* +0x0406 buttons held */
    u16 scriptInput;                   /* +0x0408 scripted input word (input mode 2: demo, practice dummy) */
    u8 unk040A[2];
    s32 inHistIndex;                   /* +0x040C */
    s32 cmdCount;                      /* +0x0410 command-buffer entries (at most 9) */
    s32 cmdRead;                       /* +0x0414 command-buffer read count */
    s32 cmdMergeTimer;                 /* +0x0418 presses within 3 frames merge into the last entry */
    u8 inHistory[60];                  /* +0x041C pressed << 4 | direction */
    u8 cmdBuffer[10];                  /* +0x0458 entries 1-9: held << 4 | direction while a move with flag 0x2000 runs */
    u16 inPressedHist[60];             /* +0x0462 raw pressed pad words of the last 60 frames (ring, index +0x40C) */
    u8 unk04DA[2];
    s32 pressCount[4];                 /* +0x04DC presses of LP, RP, LK, RK within the 60-frame window */
    s16 scaleBase;                     /* +0x04EC model scale, 4096 = 100% */
    s16 scale;                         /* +0x04EE */
    FighterPart parts[22];             /* +0x04F0 */
    u8 unk0860[80];
    u8 rootJoint[68];                  /* +0x08B0 */
    u8 joints[1632];                   /* +0x08F4 24 x 0x44 joint blocks */
    u8 rootMat[20];                    /* +0x0F54 root rotation (MATRIX rotation part) from tilt and facing */
    s32 rootX;                         /* +0x0F68 world root position */
    s32 rootY;                         /* +0x0F6C */
    s32 rootZ;                         /* +0x0F70 */
    u8 localMats[576];                 /* +0x0F74 18 x 32-byte local joint matrices */
    u8 attachLocal[32];                /* +0x11B4 local joint rotation of the first attached part (parts 18+, FighterComposeJoints) */
    u8 unk11D4[160];
    void* pssdw;                       /* +0x1274 */
    s16 screenX;                       /* +0x1278 */
    s16 screenXCopy;                   /* +0x127A screen x stored by FighterDrawParts for bank-type 11 fighters */
    u8 unk127C[14];
    u8 airFree;                        /* +0x128A airborne and not in a reaction (FighterMovePhysics) */
    u8 setupFlag128B;                  /* +0x128B cleared by FighterSetupParts */
    u8 unk128C[68];
    u8 ogreFreezeFlags[4];             /* +0x12D0 set while in hit freeze against bank 14 (Ogre), else cleared (FighterMovePhysics) */
    u8 composeFlags[4];                /* +0x12D4 cleared by FighterComposeJoints each frame */
    u8 unk12D8[216];
    u8 prevLocalMats[544];             /* +0x13B0 17 x 32-byte local matrices of the previous frame (slots 1-17) */
    u8 unk15D0[32];
    u8 blendDelta[544];                /* +0x15F0 17 x 32-byte rotation deltas (9 s16 each) for motion blending */
    s16 prevRootDx;                    /* +0x1810 */
    s16 rootDyBlended;                 /* +0x1812 */
    u8 unk1814[8];
    s32 blendMode;                     /* +0x181C 0 none, 1 decay from previous pose, 2 blend into pending branch, 3 blend into stance */
    s32 blendModeB;                    /* +0x1820 cleared together with the blend mode (FUN_8003C4AC) */
    void* lastPoseMove;                /* +0x1824 pose move of the previous displayed frame (blending) */
    u8 unk1828[4];
    s32 lastPoseFrame;                 /* +0x182C pose frame of the previous displayed frame (blending) */
    u8 unk1830[56];
    s16 blendRootDelta[3];             /* +0x1868 */
    s16 blendWeight;                   /* +0x186E 4096 * counter / frames */
    s32 blendFrames;                   /* +0x1870 */
    u8 unk1874[4];
    s32 blendCounter;                  /* +0x1878 */
    void* blendSrcMove;                /* +0x187C */
    void* blendDstMove;                /* +0x1880 */
    u8 blendSrcFrame;                  /* +0x1884 */
    u8 blendDstFrame;                  /* +0x1885 */
    s8 aiSlot;                         /* +0x1886 AI record slot, -1 without one (AiInitRound) */
    s8 aiTarget;                       /* +0x1887 index of the fighter the AI targets (AiInitRound) */
    u8 keepLight;                      /* +0x1888 set while the body burns: back colour black (FUN_8003A564), FUN_8003A3B8 skipped */
    u8 unk1889[3];
} Fighter;
/* END generated Fighter */
