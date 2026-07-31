HUD & Main Interface Architecture

Target Audience: UI/UX Designer / Frontend Coder
Context: This document outlines the structural layout, accessibility requirements, and technical implementation of the main Heads Up Display (HUD) and system menus. The UI must expose critical ECS data clearly without obstructing the 3D viewport, scaling flawlessly across resolutions, and prioritizing keyboard navigation.

1. Resolution Independence & The Modular Canvas

The game operates on a single screen without full-page scrolling. To support resolutions from 1080p up to 4K Ultrawide, the UI layer is completely decoupled from the 3D render resolution.

Godot Anchor System: All HUD elements must be nested inside a root Control node set to Full Rect. Elements are bound via relative Anchors (Bottom-Left, Top-Right) rather than absolute pixel coordinates.

The "HUD Edit Mode":

Players can press a hotkey to unlock the UI.

HUD elements become draggable panels snapping to a grid.

CRITICAL - The Resolution Trap: The layout is saved to user://hud_layout.json strictly using Viewport Percentages (0.0 to 1.0), never pixel coordinates. This prevents panels from rendering off-screen when migrating from Ultrawide to a 1080p laptop.

A hardcoded "Reset HUD to Default" button exists in the Systems menu.

2. Primary On-Screen Elements (The Default Layout)

While the HUD is modular, the default layout must be highly ergonomic and instantly readable.

A. The Running Log (Bottom-Left)

The dungeon is systemic; the player needs a chronological ledger of events.

Visibility: Housed in a semi-transparent dark panel. It must be wide enough to prevent awkward text-wrapping and tall enough to show the last 6-8 actions.

Super Readability & Semantic Coloring: Uses a sans-serif font with a strict black outline. Text color is driven by ECS tags (Player damage is #FF4444, Alerts #FFD700).

CRITICAL - The Spam Aggregator: The UI must NEVER log 1:1 with the ECS Micro-Tick. It buffers events per frame. If 10 enemies take fire damage simultaneously, the log outputs a single combined string: [14:02] Corpse-Rat takes 5 Fire Damage (x10).

Mouseover Context: Hovering over a noun in the log (e.g., "Goblin") triggers a rich tooltip pulling data from the ECS.

B. Vitals & Core Stats (Top-Left)

Immediate physical status. Always visible.

Bars: Health (Red), Stamina (Green), Strain/Magic (Blue).

Delta Feedback: When health is lost, a white "ghost" bar lingers for 0.5 seconds before shrinking, ensuring the player visually registers the magnitude of the hit.

Condition Icons: Small square icons beneath the bars representing active ChemistryComponent tags (e.g., green for [Poisoned]). Mousing over reveals exact math.

C. The Quick-Belt & Action Bar (Bottom-Center)

The player's primary interaction with their inventory during active gameplay.

Configurable Slots: Number keys 1 through 9.

Organizational Buckets: A player can assign a "Tool Bucket" to slot 4. Pressing 4 cycles between Pickaxe, Torch, Rope.

CRITICAL - The Ghost Flash: Pressing a cycle key instantly flashes a semi-transparent icon of the newly equipped item in the center of the screen for 0.5s. The player must NEVER be forced to look down at the belt during combat to confirm what they are holding.

D. The Paper Doll / Equipped Gear (Bottom-Right)

At-a-glance confirmation of offensive and defensive capabilities.

Visual Representation: Abstract silhouettes of Head, Chest, Hands, Legs. Condition indicators show durability via colored borders.

Always-Visible Info: Total Armor Rating and Total Mass (kg) are displayed numerically. (Mass directly drives stamina drain and speed).

3. Keyboard-First Navigation & Modality

The player should never be forced to take their hand off the WASD/Combat keys to use the mouse unless doing deep inventory management.

Subscreen Hotkeys: I (Inventory), G (Grimoire), J (Lineage Journal), C (Character/Mutations), M (Map).

CRITICAL - The Focus Override: We explicitly forbid Godot's automated focus_neighbor system for grid inventories. The UI must use a custom GridFocusManager script that tracks the logical 2D array, ensuring arrow keys always snap to the correct geometric cell (even if empty), preventing the cursor from flying off to random screen elements.

The Escape Stack: Pressing ESC always closes the highest-Z-index UI panel. If no panels are open, it opens the System Menu.

The Combat Radial: Holding Q severely slows the Micro Tick and opens a contextual radial menu (potions/spells) navigable via a quick flick of the mouse or directional keys.

4. The Systems Menu (Settings Tabs)

The core configuration suite. Divided into distinct tabs.

Video: Resolution, V-Sync, Framerate Cap (Crucial for limiting physics calculations).

Audio: Master, Music, SFX, UI, and Ambient/Acoustic volumes. (Acoustic volume is vital since enemies react to noise).

Gameplay: Tooltip delay, Default tactical lens behavior (Toggle vs. Hold).

Controls (Keybinds): Full remapping, Primary/Alternate mapping.

Accessibility (CRITICAL):

Colorblind filters.

Master UI Font Scaling.

Disable Screen Shake.

Translation Cipher Toggle: Option to bypass noun?/verb? obfuscation and show raw English.

Save Management (The Lineage):

"Save & Quit" (Suspends current run).

"Abandon Run" (Force-kills Entity 0, initiating the Interregnum time-skip).

5. Integrated Corrections (ADR / Adversarial Review)

Redundant encoding rule (review G2): information the player must act on in real time MUST use
redundant channels, never color alone (or sound alone). Every state that has a tag color
(e.g., [Toxic]=purple) also carries a distinct ICON SHAPE and/or MOTION/PARTICLE pattern, and
a text label in the Tactical Lens. Acoustic mnemonics are an ADDITIONAL channel, never the
sole carrier of information (deaf/HoH accessibility). Colorblind filters remain, but do not
substitute for shape/text redundancy. This is a hard UI rule that Sprint 4 VFX and Sprint 5
acoustic data must honor.

Picking (ADR-2): HUD mouseover/log-noun tooltips and any world picking resolve targets via the
ECS PickSystem (camera ray marched through the SpatialHash + tile_map), NOT Godot physics
raycasts.

Time/versions: schedules and the running log use the GameClock (ADR-9); engine is Godot 4.7.1
(ADR-15).
