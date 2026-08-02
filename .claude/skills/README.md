# Vendored agent skills

From [gd-agentic-skills](https://github.com/thedivergentai/gd-agentic-skills) (LGPL-3.0), a
97-skill Godot 4.7 expert library. Vendored rather than linked so an ephemeral agent gets them
without a network fetch, and so the exact revision is pinned by our own history.

## Only seven of the ninety-seven are installed, on purpose

The upstream README is explicit that installing all of them causes a "metadata flood": roughly
15,000 tokens spent just listing what exists, plus conflicting expert instructions.

**The bigger reason is this project's Prime Directive.** Most of that library teaches idiomatic
Godot — `CharacterBody3D`, `Area3D`, physics raycasts, `move_and_slide()`, one node per entity.
Every one of those is BANNED here (CLAUDE.md §1, ADR-2). Installing the combat, physics,
raycasting, or genre-blueprint skills would put confident, well-written, thoroughly wrong advice
in front of every agent that opens this repo, and the advice would look authoritative.

Installed, because they are orthogonal to the node/ECS question:

| Skill | Why it earns its place here |
|---|---|
| `godot-performance-optimization` | The open ADR-10 gap: 13.7 ms at 1,500 entities against an 8 ms budget. MultiMesh and pooling advice applies directly to the viewer. |
| `godot-debugging-profiling` | The overlay, counters, and the ADR-20 soak harness. |
| `godot-testing-patterns` | GUT idiom. 240 tests and counting. |
| `godot-gdscript-mastery` | Language-level correctness. The lambda-captures-primitives-by-value trap that nearly produced a vacuous test this session is exactly this category. |
| `godot-resource-data-patterns` | Data-oriented storage, which is what the ECS is. |
| `godot-save-load-systems` | Sprint P / ADR-6 persistence, with ADR-21's 64-bit-int hazard. |
| `godot-procedural-generation` | Sprint 2 world generation, and the lazy floors still to come. |

## Deliberately NOT installed

`godot-combat-system`, `godot-physics-3d`, `godot-2d-physics`, `godot-characterbody-2d`,
`godot-raycasting-queries`, `godot-ai-navigation`, and every `godot-genre-*` blueprint.

They are not bad skills. They are correct advice for a different architecture, and this codebase
resolves collision, picking, and pathfinding in pure ECS maths precisely so it can simulate more
entities than a node-per-entity design can carry.

If you want one of them, read it deliberately and translate it — do not install it where an
agent will absorb it as ambient truth.

## Precedence

These are REFERENCE, not authority. Where any of them disagrees with
`docs/architecture_decisions.md` or `docs/component_and_field_registry.md`, those win. Where one
of them disagrees with the Prime Directive, the Prime Directive wins and the skill is wrong for
this project.
