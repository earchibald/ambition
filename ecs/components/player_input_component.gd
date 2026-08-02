## Marker attached ONLY to Entity 0 while alive (registry section 2).
##
## Detached on death, before the player handle is retired and index 0 is reused.
class_name PlayerInputComponent
extends RefCounted

## Latest movement intent in world space, written by the input bridge each frame.
# DELIBERATELY EMPTY. This component is a presence marker: its bit on row 0 is what says "this
# body is player-controlled", and the death loop severs control by removing it. It once
# declared move_vector/wants_attack/wants_interact "written by the input bridge each frame" —
# the bridge never wrote them (intents go through the action queue), so the fields were the
# signature defect and were removed in the 2026-08-01 cull.
