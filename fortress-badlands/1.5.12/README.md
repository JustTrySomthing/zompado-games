# Fortress Siege: Final Conquest — v1.5.5 (build 123)

Fortress is a turn-based game for Zompa using LÖVE 11.5. See [How to Play](how-to-play.txt) for the current stats and combat rules.

Choose one move or attack per turn. Soldiers, Ogres, and Barbarians attack neighboring hexes in any direction. Archers shoot up to three hexes in a straight line. Assassins strike up to two hexes in a straight line. Wizards can cast at any enemy within two hexes. An attacked Fortress can launch boulders into its forward three rings. Attacks leave the attacker in place. A standard attack uses one D12.

Press Roll to decide the first turn. In online matches, the inviter starts the roll. Local v0.5.18 matches keep their original opening order. Existing online matches keep their original build.

## Version 1.5.5

Skirmish and Wide Front walls span the full center row. Saved matches keep their original wall layout. Match summary and initiative dialogs put Back on the left and the primary action on the right.

## Version 1.5.4

New matches scatter Mystery Crates across Skirmish, The Narrows, Twin Bridges, and Four Corners. Classic and Wide Front keep crates in the center three rows. Existing matches keep their original placements. Four Corners uses continuous stonework with mitered joints and visible breaches.

## Version 1.5.3

The Narrows has fixed stone terrain, two open side gaps, and a two-hex center pass that the optional wall can seal. Four Corners starts both armies around two adjacent central Fortresses. Its optional eight-section wall surrounds both Fortresses. CPU armies plan around the terrain and use available breaches. Existing Narrows saves retain their original layout.

## Version 1.5.2

The optional Border Wall now seals both lanes of each crossing on Twin Bridges. Destroy a wall section to open a lane. Existing partial-wall saves keep their original layout.

## Version 1.5.1

Solo and Pass & Play resume confirmed match setup and the opening roll. Online lobbies recover when the host rolls back a start packet. The Narrows walls block only shots that pass through them, and the gaps require a playable path for teleportation and melee. Match Setup keeps its controls distinct in very short windows.

## Version 1.5.0

Start Game now opens Match Setup with an illustrated battlefield preview and optional rules. Classic remains the default. The alternate battlefields are Skirmish, The Narrows, Twin Bridges, and Wide Front. Border Wall placement follows the selected map, and Mystery Crates can be set to 1–6 with a board-specific default. Local saves and online invitations preserve the selected battlefield and rules.

## Version 1.4.11

Mystery Crate reveals use a translucent tile-shaped backdrop, smaller item icons, and a soft gold glow behind the bomb. The new reveal plays both when a warrior opens a crate and when an attack destroys it.

## Version 1.4.10

The Blue Archer matches the Red Archer’s character in blue team colors across the compact card, expanded card, and battle scenes.

## Version 1.4.9

The first-turn roll has one heading and a gently pulsing winner announcement that stays on screen longer. Full-size cards wrap their ability descriptions and leave a consistent gap after every entry.

## Version 1.4.8

Fortresses use the Final Siege artwork when attacking or defending in regular battles. Boulders launch from the same battlements in both scenes.

## Version 1.4.7

Fireballs launch from the Wizard’s staff crystal, arrows leave the Archer’s bow, and boulders launch from the Fortress battlements in combat and Final Siege.

## Version 1.4.6

Battle and Death Match buttons sit midway between the result panels and the arena border.

## Version 1.4.5

The first-turn roll groups both dice and the result in one panel. Board dialogs align with the board midpoint. The match summary aligns its icons and gives the bomb a clearer glow. Defeat skulls pulse gently, and a smaller skull remains over the fallen fortress on the Victory screen. Compact cards center the Mystery Crate and make the expand button easier to spot.

## Version 1.4.4

The low-profile Border Wall has a visible far face and a cast shadow on the board. Damage appears as a first crack, spreading cracks, chipped stone, and finally rubble.

## Version 1.4.3

The Assassin has a broader dagger and the Archer has a smaller, centered, notched arrowhead. Both pieces use the Red and Blue stone textures at the same scale as other pieces. On full bio cards and in battle, the Red Wizard has a warmer amethyst and the Blue Wizard has a cooler amethyst.

## Version 1.4.2

The finale adds logo-inspired Victory and Defeat reveals and a fortress collapse that shakes in place after impact. The shared pass-and-play screen names the winning kingdom.

## Version 1.4.1

Online matches rebuild their board if a delivered history changes and apply new turns without replaying the entire match. The SDK reuses unchanged history pages on Zompa 0.5.54 or later.

## Version 1.4.0

New online matches use Zompa SDK 5 and paged turn history on Android build 62 or later. Match length no longer decides the result. Earlier invitations keep their original game build.

## Version 1.3.7

Online matches show the draw when Zompa reaches its turn-message limit. Compact action buttons fit narrow screens, and malformed save histories are rejected.

## Version 1.3.6

Gold move outlines remain visible around Mystery Crates, and the pre-match feature summary fits shorter viewports.

## Version 1.3.5

The pre-match summary uses larger descriptions, aligned Mystery Crate details, and larger potion and bomb icons.

## Version 1.3.4

Mystery Crates use a larger, muted wood design that matches the board’s hexagon and leaves an even gap around the tile.

## Version 1.3.3

The Mystery Crate card and match summary clarify that each crate contains either a potion or a bomb.

## Version 1.3.2

Destroyed Mystery Crates show the revealed item in the result popup. Scorch marks are lighter so the stone texture shows through.

## Version 1.3.1

Mystery Crates spawn apart, contain both outcomes when at least two are present, and can be struck by any troop within its normal attack range when crate destruction is enabled. The match summary groups the two outcomes under the crate.

## Version 1.3.0

Mystery Crates replace the separate trap and potion options for new matches. An optional pre-match summary introduces the crates and Border Wall. Older saves retain their original rules.

## Version 1.2.2

The CPU routes troops through reachable wall gaps and weighs safe advances before opening another section. Soldiers advance one hex forward and can move one hex sideways along the enemy back row. The CPU accounts for both moves.

## Version 1.2.1

The CPU weighs expected potion healing and whether an opponent can actually reach a potion. It favors wall breaches that open useful movement or attacks, weighs the reply those breaches give the opponent, and estimates trap risk only from public match information.

## Version 1.2.0

Advanced Settings adds visible Health Potions with a 1–3 count and optional destruction by a single attack. Potions restore 3–8 Health, capped at full Health, and never share a starting hex with a trap or wall.

## Version 1.1.2

The starting board previews the Border Wall before play. Advanced Settings explains when its controls lock.

## Version 1.1.1

One-brick limestone wall sections crack, chip, and fall to rubble. Trap hits flash the affected troop and show a single centered damage notice.

## Version 1.1.0

Zompa's Game Settings gear opens Advanced Settings before a new match. Booby Traps and Border Wall are both off by default. The inviter sets the rules for both players online. Save and resume keep the rules chosen for the match.

## Version 1.0.1

An armed Fortress can fire at enemies directly beside it. Its forward range stays at three hexes. A turn handoff explains a forced pass.

## Version 1.0.0

First stable release, based on the playable 0.5.72 build.

## Version 0.5.72

The expand button on character and Fortress cards gently pulses with a warm gold glow.

## Version 0.5.71

The inviter starts online play. Both players see battle and reward results as the attacker advances the battle. The board fits the space below the online turn banner.

## Version 0.5.70

The seven-image gallery ends with Final Siege.

## Version 0.5.69

The catalog gallery features eight current game scenes, from the opening to Final Siege.

## Version 0.5.68

The top-bar guide is organized for phone reading. Practice now teaches the expandable Fortress card before the opening roll.

## Version 0.5.67

Fortress cards label their live status and give the Boulder ability more space.

## Version 0.5.66

Both Fortress cards lead with the victory objective and show whether their boulders are armed.

## Version 0.5.65

Every troop and Fortress has an expanded inspection card for both kingdoms. The compact expand control gently pulses.

## Version 0.5.64

The Red Archer card softens the lower portrait edge and insets its expand control.

## Version 0.5.63

Tap the down arrow on a Red Archer’s inspection card for his live stats and abilities.

## Version 0.5.62

The game prepares the tile surface at launch and the menu preview before the dissolve begins.

## Version 0.5.61

The intro skips hidden board rendering and reuses a phone-sized menu snapshot during the dissolve. The logo descends gently.

## Version 0.5.60

The launch scene gives the fighters more space and dissolves into the board over a longer handoff.

## Version 0.5.59

A short layered fortress prologue opens new games. The opening of the march reaches its playing level sooner.

## Version 0.5.58

The streamed score has twice its former mix ceiling and starts at 80% of that level. A smaller stereo Ogg and playback recovery support uninterrupted listening.

## Version 0.5.57

Standard of the Two Kingdoms is an original looping orchestral march. Adjust its level with Zompa’s Music control.

## Version 0.5.56

Dice tumble in a wooden tray with a deeper, quieter roll.

## Version 0.5.55

The sound mix covers board selection, movement, initiative, combat, rewards, Death Match and Final Siege. Weapon impacts, shields, dice and footsteps use distinct sounds, with subtle playback variations. Landed hits on fighters mix in one of four quiet exertion recordings. The Zompa effects volume controls the entire mix.

Impact exertion recordings adapted from [Hurt Sound Effects](https://opengameart.org/content/hurt-sound-effects) by EZduzziteh, [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## Version 0.5.54

The combat die sits higher above the fighters and adjusts to the available portrait height. Roll instructions sit closer to the heading, and the compact Power and Shield panel opens to reveal the result.

## Version 0.5.53

The battlefield uses the approved Weathered Flagstone treatment, with subtle warm and cool tones and fine stone grain. Hex geometry and piece positions are unchanged.

## Version 0.5.52

- Attack announcements stay readable longer and fade in and out. Combat dice settle before moving into the results panel, and the Health reward entrance, roll, and amount have distinct transitions.
- Unit cards keep stat values beside their labels. The Ogre card explains that it attacks adjacent enemies.

## Version 0.5.51

- The Death Match winner delivers the finishing strike using their class animation. The loser falls and the same rising skull marks troop defeats in regular battles.
- The losing keep shatters and leaves a rising skull. Fireworks launch upward from the winning keep.
- Combat rolls and messages sit in a centered results panel. The full-Health reward message is grouped above Continue, and the arena extends farther down the screen.

## Version 0.5.50

The Death Match skull pulse and battle sequence play at half speed, along with Final Siege and its ending. Ordinary moves and battles run at their original pace.

## Version 0.5.49

Gameplay animations return to their original pacing.

## Version 0.5.48

- Visual animations play at half speed, including movement, the Death Match, reward rolls, and Final Siege.
- A single skull pulses over a Death Match target. The skull and its paired crossbones use the same design on the board and in the battle.
- Rounded, faceted boulders arc through Final Siege. The entire scene shakes when a keep shatters, and a large animated victory title names the winning kingdom.

## Version 0.5.47

- Death Match targets send out fading skull-and-crossbones pulses. Defeated fighters fall back and fade as the skull rises.
- Final Siege keeps sit directly on the cliffs, and the losing keep breaks into pieces at the collapse.
- Wizards leave an arcane trail, Ogre landings briefly shake the board, and a subdued sky has more visible stars and faction-colored auroras.
- The board has more space beneath the inspector. Damage is larger and centered, and victory has a separate announcement before rolling for Health or acknowledging full Health.

## Version 0.5.46

Smoothed the lighting behind Final Siege and victory text.

## Version 0.5.45

The board is larger and uses a raised stone rim. The inspector stays docked, confirmed targets get corner marks, and the game shares a consistent frame across the inspector, menus, controls, and combat. Final Siege shows the two keeps across a smoky ravine and continues on the same battlefield through the collapse and victory.

## Version 0.5.44

Both teams now use the High Keep with a closed iron portcullis. The stone backgrounds are taken from the matching troops. The board, inspector, battle views, and finale use the same fortress art.

## Version 0.5.43

Each class has its own movement timing, landing effect, and sound. Wizards dissolve and reappear at the destination. A skull seal identifies selected Death Match targets on the board, and the Target card names the duel before confirmation.

## Version 0.5.42

Barbarians attack one hex in any of the six directions. The CPU looks for opportunities to move adjacent to enemies while accounting for retaliation. Shield remains 4.

## Version 0.5.41

Barbarians attack up to two hexes in a straight line and have 4 Shield. The CPU looks for straight attack lines while weighing the chance of a retaliatory hit.

## Version 0.5.40

The CPU makes better use of the Barbarian’s two-hex reach. It values attacking short-range enemies from outside their reach and moving into position to open a new attack.

## Version 0.5.39

A legal attack between two critical pieces triggers Death Match. Each combatant automatically rolls a D12. The higher roll eliminates the other piece instantly. On a tie, both roll again. Power and Shield are bypassed and the survivor keeps their current Health. A defeated Fortress ends the game.

## Version 0.5.38

Barbarians can attack targets up to two hexes away in any direction.

## Version 0.5.37

The board clears last-action trails and endpoint markers at turn handoff. Live movement, attack, and selection effects remain available during play.

## Version 0.5.36

A steady icy-blue rim marks available attack targets. Selecting a target sends out three expanding hexes, then leaves a brighter ring around the piece. Critical Health keeps its separate pulsing red corners. The tutorial uses the same target markers as matches.

## Version 0.5.35

The die uses bevel lighting, recessed numerals, and a supersampled silhouette on supported renderers. The roll geometry, positions, and outcomes are shared with the previous renderer. To restore the earlier look in a future build, change the one renderer import in `main.lua` from `d12_polished` to `d12`.

## Version 0.5.34

- Archer board pieces show a close-up of the broadhead. Available targets display a crossed-swords badge, and a larger gold crosshair marks the chosen attack target.
- Tutorial instructions and callouts are larger. The opening mission sits higher without a divider, and player and team labels are larger.

## Version 0.5.33

- Combat uses a stone arena with team-colored lighting, a centered die, and a Health bar below each fighter. The defending bar drains on impact, and earned Health has a separate reward panel.
- Board tiles use subdued stone colors and subtle team tints near the fortresses. Contact shadows anchor the pieces, and the action controls have more space below the board.
- Stat cards keep the full-height art and use brighter values, a Health meter, and a highlighted Shield when previewing a target.

## Version 0.5.32

- A lifted piece with a gold rim shows selection. Gold dots show legal moves, a check mark shows the chosen destination, and crossed swords mark attacks. Separate pulsing corners identify critical Health.
- The last move or attack leaves a faint trail until the next piece selection. The tutorial uses the same move and attack markers.
- Fortress towers show their first cracks after taking damage. At 20 Health or less they show a more damaged tower and light smoke. Both sides use the same thresholds.

## Version 0.5.31

- Selected units lift above their hex. Confirmable moves preview the legal route, and pieces settle into place with a soft landing cue.
- Attack sounds and impact effects vary by unit. Damage text and the Health bar update at impact. The first battle has the full introduction, with a shorter lead-in for later attacks.
- A fortress’s first hit, critical Health, and the final collapse have distinct feedback. All cues use the Zompa effects volume.
- The practice shot shows the Archer’s Power, the defender’s Shield, the die result, and the exact Health lost.

## Version 0.5.30

The tutorial introduces one piece or target at a time. Players inspect a labeled Soldier and learn all five stats on its card before practicing movement, an Archer attack, and the reward roll. The final lesson identifies the enemy Fortress and explains how to win. Attack Now uses a plain label during training and live play.

## Version 0.5.29

- **How to Play** opens an interactive practice board. Move a Soldier, target an enemy with an Archer, watch the automatic attack roll, and claim a health reward. Training uses its own board and leaves match progress untouched.
- All unit cards and portraits share the same dimensions. At or below one-quarter Health, units and Fortresses keep pulsing across turns until healed or defeated.
- The package requests portrait on supported Zompa Android builds starting with build 57.

## Earlier releases

## Release v0.5.0 — approved 15-piece symmetrical redesign

- Larger balanced board based on the approved mockup; weathered edge-to-edge hex art and both two-tower forts retained.
- 15 troops per side, not 14; 30 total troopers plus two forts, with exactly the approved class distribution.
- Two fourth-rank flanks intentionally empty to make space for early maneuvers.
- Six truly adjacent hex movement directions replace the old square-index eight directions to match the tessellation.
- Dynamic unit indexing (1–30), formation, AI action search, six-sided tap detection, animations, autoplay, and deterministic replay updated together.
- All three Zompa game modes are supported; online save tokens still travel through SDK v4's turns-v1.
- New v6 save format prevents old-match contamination; all original values for damage, dice, healing and classes stay unchanged.

## Zompa SDK / verification

Unmodified SDK 5 `zompa.lua` and the official LÖVE runtime. The host provides solo, pass-and-play and turns-v2 online modes, local session saving, toolbar controls and safe area. The online suite checks reconnecting and continuing past 512 and 4,096 messages. No custom chat/networking code. Existing in-progress matches remain pinned to their build by the host.

Automated tests in `tests/` include square-mask, movement, battle determinism, 24 whole-match simulations, readable touch controls, animation sequencing, CPU move visibility, and resizing across multiple portrait canvases. These do not replace Android device and real online two-device testing.


## Version 0.4.3: alignment and true octahedral dice

- Source-art pixel calibration changed to x=97, y=107 (same transformation for tapping, move markers, units and fortresses). The former y=94 placed overlays roughly 13 artwork pixels above the painted hex centers.
- Every character crop uses its actual badge center (x=77,y=82), instead of the midpoint of the 144×144 tile crop. On inspection cards and during battles, the surrounding stone square is hidden with an accurate hexagonal stencil; full pieces stay within their own frames.
- Each D8 now renders as a rotating octahedron made from 8 triangular faces, projected in perspective with front/back shading, visible edges, a ground shadow, and the resolved result printed on the landing face.
- The animation consumes no gameplay random numbers, so online deterministic replay and battle balance remain unchanged.
- Existing graphics, class balance, starting formation and Zompa SDK interfaces are otherwise unchanged. Tests check actual artwork-center alignment and badge masking in addition to the prior combat and UI tests.


## Version 0.4.4 — battle readability and more strategic recovery

- Battle results emphasize the actual factions and combatants (for example, "RED BARBARIAN WINS"), rather than generic attacker/defender statements. The die and HP bars remain visible.
- Replace repeated explanatory text with compact round status and animated red "-5" style floating damage bubbles beside the character being struck.
- The victorious surviving troop's healing is now **D8 = 1 to 8 HP**, never beyond its class maximum. The battle outcome and healing die are determined by the shared game RNG at action resolution; the **Roll D8 to Heal** button reveals that deterministic reward without changing the result. This is visual interaction only and introduces no online network move.
- In single-player, CPU healing is revealed automatically. In pass-and-play and online, participants can watch the same established reward without changing gameplay.
- New save format \`v5\`: pre-v0.4.4 in-progress local matches use an incompatible RNG sequence and must start a fresh game. Older online matches remain pinned to their original exact game build by Zompa.
- Character card text is larger, full width is better used, selected destinations glow in high-contrast gold with a dark underlay. Small art borders are trimmed without stretching the board. Moving character badges and the numbers on the dice faces are centered more precisely.

## Version 0.4.5 — premium presentation and CPU polish

- Selected soldier gets a restrained gold double-ring pulse; the *chosen* landing hex gets a distinct white/gold center to distinguish it from all available destinations.
- Per-cell movement has a slight arrival/settle animation; no rules or online messages are changed.
- The battle's ordinary D8 exchanges are brisker, with small deterministic sword-impact sparks and floating damage. The final blow holds for a moment before the winner/reward confirmation.
- The inspection card now chooses the clearer top or bottom free margin, or the opposite side of the board on small devices. Stats are grouped visually and remain large.
- On match completion a short visual effect shows a squat Fortress collapsing, followed by an unmistakable victory, defeat, or mutual-destruction banner.
- CPU decision scoring now considers enemy strike strength, expected exchanges before defeat, immediate threats and home-Fortress defense; existing gameplay statistics remain unchanged.
- Mobile portrait layouts and touch-control handling remain responsive under the same Zompa SDK. The board artwork is deliberately unchanged.

**Compatibility:** Same rules/save version as v0.4.4; game identity is unchanged. No additional piece abilities or controls were added. Check the polished UI on an Android phone after installation.

## Version 0.4.6 — immersive arcade-style battle polish

- Every battle die is permanently tinted to its kingdom: muted burgundy red for Red, muted royal blue for Blue, including Final Siege and healing rewards. Winning rolls are distinguished by the outcome, not an unrelated die color. The decorative bars above combatant portraits are removed.
- A bold angled winner splash identifies the kingdom and class. After the win, an equally prominent Health Bonus splash and large reward die show the already-determined 1–8 HP result; the player taps **Roll for +1 to +8 HP**, while the CPU starts its roll automatically *after* the battle.
- The board image only trims non-playable painted margins to fill more of its canvas. Gameplay coordinates, the 7×10 grid, and piece aspect ratios remain identical.
- The card is docked in a reserved top band, not allowed to overlap the playing field. Fonts and stat rows fit within its responsive height.
- One continuous stone-charcoal stage replaces the previous multiple horizontal backdrop bands.
- No new combat rules, character stats, or transport protocol; Zompa SDK v4 and saved event format v5 remain unchanged.
- The updated UI tests check responsive layout and that the battle healing reward is still explicit and modal. Visual polish must be reviewed on Android.

## v0.4.7 — approved Fortress UI handoff implementation (November 24, 2026)

This version is based on all four **Approved_Mockups** and four **Original_Screenshots** supplied in the handoff ZIP, not another proposal or mockup. It uses the same Fortress identity and Zompa SDK v4.

- **Board:** replaced the painted square grid / inset-hex texture with close-packed six-sided flagstones, each textured from the source board's blank stone interior; visible square tile outlines are removed. Source center calibration, narrowed corner mask, 58 playable square-logical positions and all 8 movement directions remain unchanged. A true regular hex tessellation on an orthogonal 7×10 lattice would change hit testing and movement topology, so the approved mockup's staggered rows are *not* copied literally. This is the explicit visual/mechanics trade-off.
- **Artwork:** added continuous dark-and-gold hex strokes to all ten original class sprites in both team colors; shared renderer is used on the board, on the inspection card, and in combat. The source token artwork and the fortress remain the same.
- **Battle dialog:** near-full-canvas navy panel, double gold trim, bold team-tinted labels above their respective tokens, responsive HP bars, and correct red/blue D8 models. Round indicator and minimal hits/tie feedback remain.
- **Winner:** slanted team-color banner, geometry *and lettering* rotated together, measured single-line text and readable fallback. Dynamic unit and fortress wording is retained.
- **Victory reward:** exactly `RED ROLLS FOR VICTORY BONUS` or `BLUE ROLLS FOR VICTORY BONUS` and `ROLL`. Until tapped, both last combat dice remain visible; afterward, only the center bonus die tumbles and settles on the actual D8 result. The winner's displayed HP rises to the capped health already committed by deterministic rules. The result banner reads `HEALTH BONUS +N` without appended HP, or `HEALTH FULL` if no actual recovery, then `CONTINUE`.
- **Authority:** solo CPU and online non-winner sides show an automatic presentation roll; solo human, local pass-and-play participant and online winner initiate visually. Rolling does not add a token or network event, and is idempotent.
- **Controls / background:** approved red ATTACK NOW, gray CANCEL, gold trim, unified dark-purple stage, docked stat card above playing cells and no duplicate Zompa navigation.
- **Performance:** static board flagstones are cached in a stencil-enabled canvas where supported; fallback vector painting is available. Everything else is drawn dynamically; no new outside image packs or font dependencies.

### Verification

The official GitHub workflow runs deterministic combat/HP/replay rules, board-mask tests, touch/UX/CPU movement, responsive portrait smoke tests and full automated matches. Approved mockups are visual targets, not executable source artwork. Final actual-device screenshot comparison and two-device online interaction remain necessary after publication.

## Version 0.4.8 — Fortress visibility, seamless stones, combat polish

- Remove the repeating dark vertical seam from the stone image crop: all hexagonal flagstones now use continuous warm stone fills and light, off-center grain accents. No changes to the 58 cell centers, controls, or legal moves.
- Restore the original painted **Red and Blue Fortress** at both ends by clipping each fortress from the approved board art directly to the corresponding six-sided hex, even when the board is rendered procedurally. A crenellated vector fallback works without stencil support. The fortress disappears when reduced to zero HP.
- Draw only one centered gold contour on each character badge and eliminate the extraneous backing hex in the battle panel.
- Damage pop-ups originate just above the wounded unit's **HP bar**, float upward toward the character and fade. The fixed class damage and health calculations stay unchanged.
- Replace the plain diagonal result strip with a layered, beveled gold victory plaque, team-color enamel, copper end cuts, inset highlights and ornamental rivets. The whole plaque, including the text, rotates together.
- Extended UX regression test checks for both visible Fortress crests on the actual artwork path in addition to all previous UI, battle, deterministic healing, save/replay and full-match tests.

**Gameplay/SDK compatibility:** No change to classes, combat RNG, healing range, save version, online turns or the three Zompa modes. Android device screenshot review is still required for final aesthetic comparison.

## Version 0.4.9 — seamless weathered hexes, twin-tower fortresses and single-rim tokens

- The **visual board** now uses a real staggered tessellation of point-up hexes that share each edge. Thin charcoal grout is visible only along tile boundaries; there are no open voids between adjacent cells. Each stone has hand-drawn deterministic variation, shallow patches, small chips, moss coloration and fine cracks. Board artwork uses a cached static canvas for performance.
- The original **7×10 logical grid of 58 playable positions** and its eight-direction movement/attacks remain exactly as before, including all online and saved actions. To achieve true geometric adjacency, the **displayed hex centers are staggered**. The game performs exact six-sided hit-testing against the new visible geometry. This deliberate visual geometry change does not change the game rules.
- Both Fortresses are explicitly drawn in the **center hex** of the top (Blue, row 0 col 3) and bottom (Red, row 9 col 3) rows. A substantial stone fort has **two crenellated towers**, a connecting wall, a gate, masonry texture and a color-coded pennant. It is drawn without depending on the board background PNG, so it cannot disappear when that background changes. The same drawing appears in inspection cards and Fortress battles.
- Original character crops are clipped inward to remove their old off-center painted lip and rendered with **one** clean, centered gold outline. Selection uses a low-key *round* glow instead of a second hex; movement and battle share the same token renderer.
- Red/Blue `ROLLS FOR VICTORY BONUS` now sits immediately above the ROLL button, avoiding the former blank region. Result dice and bonus values stay deterministic.
- Adds a dedicated `hex_geometry_smoke.lua` regression test for exact edge-sharing geometry, touch centers, both visible twin-tower Fortresses, and responsive layout. All original Zompa SDK v4 and multiplayer behavior are retained.

**Note:** visual hex adjacency follows hex geometry, but movement still follows the same original eight directions on row/column indexes. This is intentional to preserve the approved game's rules and online compatibility. Actual-device visual verification is still recommended.

## v0.5.2 movement changes

- Soldier: HIT **4**, MARCH up to **2 hexes in one straight direction** without changing direction; intermediate hex must be empty.
- Ogre: HIT **7**, unchanged MOVE 1.
- Wizard: HIT 8 unchanged; TELEPORT **2 hexes**, can cross occupied hexes but cannot finish on an ally. Enemy endpoint starts a normal D8 fight.
- During any attack-approach animation the target remains visible, including if the rules have already marked it defeated; the attacker travels on top of the target before battle begins. Applies to troops and Fortresses, in solo, local and online presentation.

## v0.5.2 artwork and character cards

- **New separately packaged art**: Ogre's spiked wooden club (both Red and Blue);
  Wizard's crystal-tipped magical staff (Red and Blue); twin-tower stone Fortress
  with gate and banners (Red and Blue). The live board, battle panel and Fortress
  detail card load these individual sprite assets, not a static whole-screen banner.
- **New individual portrait assets**: five character classes, each with Red and Blue
  variants, showing a right-facing head-and-shoulders pose and their class weapon.
  Soldiers carry a pike/spear, not the Assassin's dagger; Ogre uses a spiked club;
  Barbarian an axe; Wizard a magic staff.
- **Live character info card**: restrained navy, muted red/blue and thin gold lines,
  compact gold-edged hex portrait; the entire title is RED/BLUE + class (no P1/P2);
  current/max HP, MOVE and HIT are always read from the current rules state.
  No static card art, die stat, class flavor text or duplicated secondary banner.
  All classes show MOVE as the heading, including Soldiers and Wizards.
