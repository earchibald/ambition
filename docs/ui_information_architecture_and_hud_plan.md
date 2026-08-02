# UI Information Architecture and the HUD Plan

Written 2026-08-02, on the Sprints 1-4 remediation branch. This document is the requested
UI/UX exercise: what the player should see, what they see today, and the plan that closes the
gap. It reconciles three authorities:

- `ui_ux_architecture_and_player_interactivity.md` — the Tactical Lens, ergonomics, mnemonics.
- `hud_and_main_interface_architecture.md` — the HUD layout, keyboard-first navigation.
- A genre beauty brief (Appendix A) — researched against Diablo IV, Hades, Darkest Dungeon,
  Caves of Qud, Dwarf Fortress (Steam), Noita, BG3, RimWorld. Palette contrast is verified.

Where this document deviates from a spec, the deviation is in the decisions table (§6), with
the reason. Nothing is silently dropped.

## 1. The audit: what the screen shows today

| Surface | Layer | Default | What it shows |
|---|---|---|---|
| Hover card (point at anything) | player | on | Name, kind, standing, health, conditions, facts |
| Debug overlay, LIVE page | developer | **on** | Clock, fps, player vitals, cursor, perf, counters, event feed, Tab inspector |
| Debug overlay, CHRONICLE / FACTIONS / MAP | developer | via `F1` | History, faction moods, chunk map |
| `Tab` inspector | developer | — | Raw component dump of one entity |
| Grimoire (`B`) | player, debug fidelity | closed | Rune list, live spell preview, bind |
| Gizmos (`G`) | mixed | **on** | Facing arrow, melee wedge, interact ring, sight ring |

**The central finding.** Hide the debug overlay and the player has *no* health bar, no stamina,
no event feedback, no bound-spell indicator, no clock, and no inventory view. Every player-facing
fact lives inside a developer tool. That is why the debug info "drowns": it cannot be dismissed,
because it is also the only HUD. The fix is not to trim the debug panel. The fix is to build the
player layer it has been standing in for, and then let the debug panel be a debug panel.

## 2. The attention-ring model

Information is placed by what it costs the player to read, in three rings:

- **Ring 0 — always on screen.** What you need to act moment to moment. Read at a glance,
  never summoned, never in the way. The HUD.
- **Ring 1 — point at it.** What one specific thing is. The hover card, and later the Tactical
  Lens. Costs a cursor movement, nothing else.
- **Ring 2 — summon it.** What you consult between moments: the pack, the Grimoire, later the
  journal, character sheet, and map. Costs a keypress and your attention; dismissed the same way.

The debug overlay sits outside all three rings. It is for developers, it boots hidden, and `F1`
summons it. A play-tester who never presses `F1` gets a complete game readout without it.

## 3. The answers, question by question

### On mouseover?

The hover card (built 2026-08-01) is Ring 1 tier one: name, kind, faction standing, health bar,
plain-word conditions, one or two facts. It follows the genre convention exactly (Noita's
material hover: "what is it, what state, what do I do *right now*"). It stays under six lines.

What hover deliberately does NOT show: exact chemistry numbers, insight-gated detail,
comparison stats. Those belong to the examine tier (below) and to the Lens.

### The player path for examination — how far can it go?

`Tab` today is a developer tool (raw component dump). The player examination ladder, per the
ui_ux spec §2, is:

| Tier | Cost | Shows | Status |
|---|---|---|---|
| Glance | free | Silhouette, size, colour, motion | Partial — boxes with size+colour; shape language not built |
| Hover | point | The card: identity, state, standing | **Built** |
| Examine | keypress | The dossier: composition, ownership, history hooks — gated by insight, "detail never presence" | Not built; `Tab` stands in for developers |
| Lens (passive) | mastery | Colour/particle bleed into the world view | Not built (Sprint 5+ VFX) |

The examine tier is the next UI increment after this pass: a pinned card in a fixed screen
position (right third, per the genre brief) that reads `MindComponent.insight` and surfaces
what the player has earned. It must obey the corrected gate: **never hide THAT something is
dangerous, only WHY.**

### Do players have an inventory? Where do things go?

They do, and it is real: `E` pushes a TAKE intent, `InventorySystem` enforces volume
(50 L capacity, 115% overstuff), merges stacks, takes partial handfuls off big piles, and
encumbrance divides movement speed past half of carry capacity (`10 + 2×strength` kg). Items
leave the world (the visual despawns; the entity lives on in `InventoryComponent.held_items`).

What was missing is any way to SEE it. This pass adds the **Pack panel** (`I`): an auto-sorted
list — never a Tetris grid, per ui_ux spec §5 — of held stacks in the player's words, with
volume and load bars and the current speed penalty. It is read-only in v1: no DROP intent
exists in the ECS yet, and the panel says so rather than hiding it. The spec's body-plan slots
(Head/Chest/Back/Belt), fluid containers, and the bucket quick-belt arrive with equipment
itself; the UI concept already reserves their places (§4 below).

### What is always on screen, what is popup, where do the core keys live?

Per the HUD spec §2, with the pieces we can honestly fill today:

| Position | Element | Ring | Notes |
|---|---|---|---|
| Top-left | **Vitals**: health bar, stamina bar with the strain dent, condition words | 0 | Ghost bars on damage; words not icons until an icon language exists |
| Bottom-left | **Running log**: last 6 player-relevant events, clock-stamped, spam-aggregated | 0 | THE feedback channel: refusals, pickups, damage, learned runes |
| Bottom-center | **Keybar**: the core keys as slots — `E` take/use, `B` grimoire, `Q` cast (shows the bound spell by name), `I` pack, `Shift` careful | 0 | This is where the spec's Quick-Belt (slots 1-9) will grow |
| Bottom-right | **Load chip**: carried kg vs capacity, and the slow-down when it bites | 0 | The spec's paper-doll corner; gear goes here when gear exists |
| Top-right | **Clock and floor** | 0 | "Spring 1 06:00 · surface" |
| Cursor | Hover card | 1 | Unchanged |
| Center | Grimoire (`B`), Pack (`I`) | 2 | Modal-ish; `Esc` closes |
| — | Debug overlay (`F1`), gizmos (`G`) | dev | Boot hidden / off |

The keybar answers "core keys somewhere on screen" with the genre's convention (Diablo's bar,
DF Steam's bottom toolbar): keycap labels in slots, one line, ≤ 8 slots, no permanent tutorial
text. `F1` and the full table live in RUNNING.md and the future settings screen, not on screen.

### Radial menus?

Deferred, not rejected — and the eventual shape is already specified. The ui_ux spec §3 calls
for a hold-`Q` radial *paired with bullet-time*, which answers the genre's objection to PC
radials (precision cost) the same way Hades does: the world slows while you flick. But today
there is exactly one bound spell and zero quick-slot items, so a radial would be a wheel with
one spoke. The trigger to build it is the Blueprint Library (multiple bound spells) or the
Quick-Belt buckets, whichever lands first. If play-testing then rejects the wheel, the genre's
proven PC fallback is an anchored context list at the cursor (Project Zomboid pattern), max 7
items, keyboard-navigable. Plain click-and-submenu chains are rejected outright: every layer of
submenu is a real-time game asking you to stop playing it.

### The debug info is drowning

Three moves, all in this pass:

1. **The HUD is the default layer.** Player information no longer requires the firehose.
2. **The debug overlay boots hidden.** `F1` summons it exactly as before; nothing is removed.
   `debug_config.json` can restore always-on for CI captures and soak runs.
3. **Gizmos default off.** The heading nose is part of the body and stays; the wedge and rings
   return on `G` when you need to check a rule. (The melee arc will eventually be readable from
   the world itself — a swing VFX — but that is the VFX sprint's problem.)

The event feed splits by audience: the HUD log shows what happened *to you and near you*, in
the player's words; the debug feed keeps everything, including faction deliberations, in the
machine's words. Both are fed by the same signals; neither invents its own naming
(`EntityCard` remains the one naming truth).

### What goes in submenus, and how

Ring 2 today: Grimoire (`B`), Pack (`I`). Ring 2 next, reserving the spec's keys: Journal
(`J` — the CHRONICLE page's player form), Character/Mutations (`C` — mutations, exposure,
skills, insight), Map (`M` — the MAP page's player form), and the System/Settings menu (`Esc`
at top level). One panel at a time; `Esc` closes the topmost; opening one closes the hover card.
The debug overlay's FACTIONS page stays a developer tool until reputation is meant to be
readable as numbers — the player-facing form of that information is the standing line on the
hover card, gossip barks (Sprint 5), and consequences.

### Accessible

Shipping in this pass:

- **One text-size knob for every UI layer** — `=`/`-` now scale the HUD, hover card, Grimoire,
  and Pack alongside the debug overlay. Persisted, as before.
- **Contrast-verified palette** — body text ≥ 4.5:1 (AA) on the panel colour *composited over
  the brightest world pixel*, math in Appendix A and asserted by a unit test.
- **No hue-only encoding** — bars pair colour with position, ticks, and numerals; conditions
  and standings are words; health/stamina are red vs **teal** (survives deuteranopia and
  protanopia; red/green does not).
- **No flashing, no shake** — the HUD adds none.

Declared gaps, owned by the settings screen when it is built (HUD spec §4): key remapping UI
(the InputMap actions all exist), colourblind filters, motion/shake sliders, hold-vs-toggle
options, cipher bypass, UI scale slider beyond text size.

### Attractive, and fast under the hands

The beauty standard is Appendix A, applied as one theme module (`ui/ui_theme.gd`) so every
player panel inherits it — warm near-black parchment-on-charcoal, 3 px radius, 1 px border,
4/8/12 px spacing grid, ALL-CAPS letter-spaced titles, ghosted vital bars. Two visual voices
are deliberate: **warm proportional = the game talking; cool monospace = the machine talking.**
A player always knows which layer they are reading. The Grimoire keeps its monospace columns
(they are data) but adopts the player anatomy and title style.

Ergonomics: every core action sits on the WASD hand — `E`, `B`, `Q`, `I`, `Shift`, `Tab` — with
the mouse doing aim/attack/point only. No chords, no holds except `Shift`, toggles everywhere,
and forgiving picking (nearest-to-ray, not pixel-perfect). The radial, when it comes, must keep
the "or directional keys" clause from the spec.

## 4. What ships in this pass

1. `ui/ui_theme.gd` — the palette, panel anatomy, and font ladder (Appendix A), with a
   contrast test.
2. `ui/vital_bar.gd` — drawn bars: well, fill, ticks every 25, damage ghosting, strain dent.
3. `ui/player_hud.gd` — vitals top-left, running log bottom-left (aggregated, clock-stamped),
   keybar bottom-center with the bound spell named, load chip bottom-right, clock top-right.
4. `ui/pack_panel.gd` + the `inventory` action (`I`) — the read-only pack.
5. Debug segregation — overlay boots hidden, gizmos boot off, both restorable per run.
6. Re-theme of the hover card and Grimoire panel; mouse-claim fix so clicks on any open panel
   never swing at the world behind it.
7. A player-word namer for compiled spells (`On_Cast+Projectile+Apply_Burning` is not a name).

## 5. Not in this pass, and where each is owed

The examine/Lens tier (ui_ux §2), quick-belt slots 1-9 and buckets (hud §2C), paper-doll gear
(hud §2D), HUD edit mode (hud §1), settings screen with remapping and accessibility toggles
(hud §4), journal/character/map subscreens (hud §3), DROP/consume intents and body slots
(ui_ux §5), the node-graph Grimoire (ui_ux §6), barks and the cipher (ui_ux §7), icons,
audio, and all VFX bleed. RUNNING.md §3a carries the play-facing subset of this list, as ever.

## 6. Ambiguities resolved by choosing

| # | Question | Choice | Why |
|---|---|---|---|
| 1 | Vitals corner: spec says top-left, genre brief argued bottom-center | **Top-left (spec)** | The spec is the committed design; top-left has solid genre precedent (Hades); the brief's objection (four resources) is softened because we draw two bars + a dent, not four bars |
| 2 | Three bars (health/stamina/strain) per spec §2B | **Two bars; strain draws as a dent in stamina's max** | Magic costs stamina, not mana (Sprint 4); strain is temporary damage to max stamina, so a third bar would depict a resource that does not exist |
| 3 | Stamina colour: spec says green | **Teal `#2E9E8F`** | Red/green collapses under deuteranopia; red/teal survives; spec's own correction §5 demands colourblind-safe encoding |
| 4 | Grimoire key: spec §3 says `G` | **Stays `B` this pass** | `G` is gizmos today; one keybinding churn per sprint; reconcile when the node-graph Grimoire lands (gizmos move to a debug F-key) |
| 5 | Radial menu now? | **Deferred until >1 bound spell / quick-slots exist** | A wheel with one spoke; spec's hold-`Q`+bullet-time design stands as the plan of record |
| 6 | Condition icons (hud §2B) | **Words, not icons, for now** | No icon language exists; inventing one ad hoc would fight the mnemonic spec (ui_ux §4); words are the accessible channel anyway |
| 7 | Debug overlay default | **Boots hidden** | The HUD replaces its player duties; `F1` unchanged; config restores |
| 8 | Gizmos default | **Boot off** | Debug drawing on a player screen; `G` unchanged |
| 9 | Feed duplication HUD vs debug | **Two feeds, one naming truth, player feed filtered + aggregated** | Different audiences; hud spec §2A demands the aggregator on the player side |
| 10 | Retheme the debug overlay too? | **No — two visual voices on purpose** | The player must always know whether the game or the machine is talking |
| 11 | Pack panel interactivity | **Read-only v1, says so on its face** | No DROP intent in the ECS; a button that cannot work is worse than a stated limit |
| 12 | Spell display name | **Derived from shape + payload ("fire bolt"), namer lives beside `EntityCard`** | The id is `runes joined by +`; the player's words are the UI's words |

## 7. The beauty reviews, and what they changed (2026-08-02)

Two independent subagent reviews ran against RENDERED FRAMES of both scenarios plus the UI
source — one judging genre beauty standards, one auditing accessibility, contrast maths, and
theme drift. Eighteen findings between them; every one was applied, rejected with a reason, or
declared. Applied:

- **Grimoire geometry**: the title line carried five key hints and set a ~1700 px panel width;
  hints moved to the panel's foot, and the panel centers like the pack.
- **Hover card bars**: `=`/`.` typewriter glyphs (the loudest programmer-art tell in the set)
  became solid block cells in a mono span.
- **The log no longer shouts**: caption size like its peers, and lines older than ten seconds
  trade their event colour for the muted tier — the log reports, it does not alarm.
- **Vital bar execution**: numerals wear the same 4 px outline as every other HUD label
  (a 1 px shadow left "100/100" at ~2.6:1 over full teal); ticks draw dark over fill and pale
  over the empty well, so they are countable at any value.
- **The pack speaks two voices correctly**: prose proportional, columns mono via `[code]`.
- **Raw ids off the player panels**: `Apply_Water` displays as `Apply Water`;
  `Rune_Stability` as `rune stability`.
- **Modal input**: while a summoned panel is open, a click outside it DISMISSES rather than
  swinging a weapon at the world, and `Q` does not cast at things the pointer cannot even name.
- **`[O] overclock` read as `[0]`** beside `[1-9]` — zero is now an alias.
- **The log-panel alpha escaped the contrast guarantee**: raised to 0.82, where the worst event
  colour keeps WCAG AA over a fire pixel, and a test now asserts exactly that surface. The
  muted stamps there are carried by their 4 px outline — recorded in the theme, not implied.
- **Corner symmetry**: the clock joined its diagonal twin in a pill; collision guards make the
  log and load chip yield upward on narrow windows; bar width scales with the text knob.
- **Drift cull**: one mono-stack definition, one bar-cell count, edge margins on the theme
  constant, a stale contrast figure in the theme header corrected (13.4:1, not 14.6:1).

Confirmed meeting the bar without change: the palette and its discipline, the keybar pattern,
the hover card's information order, the strain-dent and ghost decisions, the tracked caps
titles, and the contrast mathematics (independently re-derived by the reviewer).

Declared, not fixed: three bold-size conventions coexist (card +2, grimoire body, HUD caption)
— deliberate emphasis differences; the vital-bar well colour is bar-local by design; `Shift`
careful-mode has no toggle alternative until the settings screen exists.

## Appendix A — the beauty standard (the UITheme contract)

Palette, verified worst-case (panel at α 0.94 composited over a bright fire pixel `#E8A050`,
effective background `#231B12`):

| Role | Hex | Contrast (worst case) |
|---|---|---|
| Panel background | `#16120E` @ α 0.94 | — |
| Panel border | `#3A322A`, 1 px | — |
| Text primary (titles, values) | `#EDE3CE` | 14.6:1 → AAA |
| Text body | `#C9BFA9` | 9.3:1 → AAA |
| Text muted (captions) | `#968C7A` | 5.1:1 → AA |
| Health | `#C4453C` | non-text, ≥3:1 ✓ |
| Stamina | `#2E9E8F` | non-text ✓ |
| Strain | `#C99A4B` | non-text ✓ |
| Magic (future) | `#7B8CE0` | — |
| Danger | `#FF6B4A` | 6.6:1 |
| Warning | `#E8B44C` | 9.8:1 |
| Good | `#8FBC5C` | 8.4:1 |

Anatomy: corner radius 3 px everywhere; border 1 px; padding 12 px; 8 px between elements;
margins on the 4/8/12 grid; shadows on summoned panels only (`shadow_size 8`, black α 0.4,
offset (0,2)); a 1 px top-edge highlight at 5% white on player panels. Bars: continuous fill,
ticks every 25 units, 0.6 s damage ghosting, numerals beside every bar. Typography: proportional
body (default font); titles ALL-CAPS with widened glyph spacing in the muted-to-primary tiers;
monospace reserved for columnar data (Grimoire list, debug). Never below 12 px at reference
resolution. Nothing is coloured for decoration.
