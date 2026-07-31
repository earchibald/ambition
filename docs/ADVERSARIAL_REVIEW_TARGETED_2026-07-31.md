# Targeted Adversarial Review - Recent Spec-Hardening Work

**Status:** Addressed in the owning specs on 2026-07-31. This was a read-only adversarial review of the documentation work
just completed in this working tree. It is intentionally scoped to regressions,
contradictions, and unclear authority introduced by the recent spec-hardening pass.

**Resolution:** Findings below are retained as the pre-repair record. The repair pass applied
the recommended fixes to the owning docs and updated STATE.md.

**Review source:** Delegated read-only review of the current unstaged/untracked diff.

## Executive finding

The recent work materially improved the spec set, but it also introduced or left behind a few
high-confidence contradictions. Most are mechanical. One is structurally important: Entity 0
death handling now conflicts with the new persistence/identity contract.

No gameplay code was reviewed or changed.

## Findings

### 1. Root CLAUDE instructions conflict with the Sprint 0 scaffold

**Severity:** Medium

**Evidence:**
- `CLAUDE.md` is now root canonical.
- `docs/sprint_0_technical_scaffolding.md` still embeds a different "exact scaffolding" body
  for CLAUDE instructions.

**Problem:** Sprint 0 now says mirrors must point to root `CLAUDE.md` or be byte-equivalent,
but the embedded scaffold is not equivalent to the root canonical file. Future agents may
copy the embedded scaffold and reintroduce conflicting onboarding instructions.

**Recommended repair:** Remove the embedded CLAUDE body from Sprint 0 and point to root
`CLAUDE.md`, or update the scaffold block to exactly match root `CLAUDE.md`.

### 2. Sprint P is listed like a sprint but has no sprint files

**Severity:** Medium

**Evidence:**
- `README.md` says sprint work uses `docs/sprint_<N>_implementation_roadmap.md` and
  `docs/sprint_<N>_technical_scaffolding.md`.
- README now lists "Sprint P / Sprint 2.5".
- Only `docs/persistence_and_save_architecture.md` exists for that workstream.

**Problem:** The index creates a naming expectation and then violates it. A future agent may
search for nonexistent Sprint P roadmap/scaffold files and treat Persistence as incomplete or
unslotted again.

**Recommended repair:** Either add `sprint_p_implementation_roadmap.md` and
`sprint_p_technical_scaffolding.md`, or explicitly state that
`docs/persistence_and_save_architecture.md` is the complete roadmap/scaffold for Sprint P.

### 3. Entity 0 death handling conflicts with persistence identity rules

**Severity:** High

**Evidence:**
- `docs/persistence_and_save_architecture.md` reserves entity index `0` for the current
  player.
- `docs/invariants_and_test_strategy.md` requires a valid generation transition for the
  player slot.
- `docs/meta_progression_and_death_loop_architecture.md` still says the player entity is
  converted into a Corpse item.
- `docs/sprint_3_implementation_roadmap.md` still says to spawn a new Entity 0.

**Problem:** If Entity 0 becomes the corpse and a new Entity 0 is spawned, the corpse and new
player compete for the reserved player slot unless the old body is re-keyed. This breaks the
handle/generation model and save/load identity contract.

**Recommended repair:** Specify that death creates a separate corpse/remains entity or
manifest, then atomically destroys/bumps the old player handle and reuses index 0 with
generation + 1 for the new adventurer.

### 4. Some scaffolds still violate canonical handle/enum examples

**Severity:** Medium

**Evidence from delegated review:**
- Sprint 1 path request examples still use `entity_id` wording.
- Sprint 1 spatial hash comments mention entity ids rather than handles.
- Sprint 2 examples may still include string LoD states in some spots.
- ECS spec names MaterializationPolicy values as prose-style names rather than exact registry
  enum constants.

**Problem:** The registry requires EntityHandles and explicit enum constants. Remaining
example drift is a copy/paste trap for implementation agents.

**Recommended repair:** Rewrite remaining examples to use `EntityHandle`, `LoD.SIMULATED` /
`LoD.ACTIVE`, and exact `MaterializationPolicy.*` constants. If integer arrays are used for
hot storage, explicitly document that they store handle indices plus generation sidecars.

### 5. Guest status revocation remains omniscient in main bootstrap text

**Severity:** Medium

**Evidence:**
- `docs/world_bootstrapping_and_the_overworld_architecture.md` main text still says
  `[Guest_Status]` is permanently revoked if the player commits a `[Crime]`.
- Its correction section says revocation requires a PerceptionSystem WitnessEvent.

**Problem:** The main rule and correction rule still contradict. Future implementers can copy
the main text and reintroduce omniscient crime detection.

**Recommended repair:** Rewrite the main Guest Status section so witness-gated revocation is
the primary rule, not only an appended correction.

### 6. Content catalog entries do not fully validate against the new schema contract

**Severity:** Medium

**Evidence:**
- `docs/content_authoring_and_schema_validation.md` defines item IDs as `ITEM_*`.
- `docs/archetypal_content_catalog.md` includes `HAZARD_*` IDs.
- The catalog says every archetype must declare materialization policy, but many rows omit
  policy.
- `ITEM_STOCKPILE_CRATE` uses prose like "LEDGERIZE contents if fungible" rather than an exact
  policy value.

**Problem:** The catalog says it validates against the schema, but some entries cannot
validate as written.

**Recommended repair:** Add a Hazard schema/domain and exact policy fields, or rename hazards
into the item archetype namespace. Add a policy column/value for every archetype and model
stockpile crates as a valid container policy plus a separate contents-ledgerization rule.

### 7. Review documents still mix resolved and open language

**Severity:** Medium

**Evidence:**
- `docs/ADVERSARIAL_REVIEW_2026-07-31.md` status says addressed, but body sections still say
  "genuinely open items" and "Do not start implementation... First, repair..."
- `README.md` still points agents to the old adversarial review for "still-open engineering
  fixes" even though the historical review banner says the original findings are
  resolved/superseded.

**Problem:** New agents can interpret resolved findings as current blockers or reopen
settled decisions.

**Recommended repair:** Move the resolution log to the top of the dated review and clearly
mark the body as pre-repair findings, or rewrite "open" language to "found and repaired."
Update README so the historical review is described as rationale/resolution history, not as a
source of current open fixes.

## Recommended repair order

1. Fix Entity 0 death/handle semantics.
2. Fix the CLAUDE scaffold conflict.
3. Fix Guest Status main text.
4. Align Sprint P naming/roadmap expectations.
5. Align content catalog/schema validation.
6. Clean remaining handle/enum copy traps.
7. Reword review docs/README so resolved findings cannot be mistaken for open work.

## Resolution log - applied 2026-07-31

All findings above were applied to the owning docs:

- Sprint 0 now points to root `CLAUDE.md` instead of embedding a divergent scaffold body.
- README and the Persistence spec state that `docs/persistence_and_save_architecture.md` is
  the complete Sprint P / Sprint 2.5 roadmap/scaffold unless later split.
- Entity 0 death now creates a separate corpse/remains entity or manifest, retires the old
  player handle, bumps generation, and reuses index 0 for the next adventurer.
- Sprint 1/2 and ECS examples were aligned to EntityHandle / exact enum constants.
- Guest_Status revocation is witness-gated in the main bootstrap rule, not only in a
  correction appendix.
- Content validation now supports `HAZARD_*` archetypes, and every catalog archetype declares
  an exact `MaterializationPolicy.*` value.
- README and dated review wording now present earlier reviews as rationale/resolution logs,
  not current open blockers.
