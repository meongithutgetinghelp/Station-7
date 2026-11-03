> Update, 1 November 2026: four-player LAN/direct-IP co-op is now implemented as a tested prototype. See COOP.md and the latest PROGRESS.md section; local-only statements below describe the older 31 October revision.

# Station 7 — current checklist

Updated 31 October 2026. Checked items mean implemented in this playable prototype, not production polished or externally playtested. This replaces the historical review's status; it does not claim its reported source files were recovered.

## User decisions that supersede the original review

- Start every shift powered normally. Only actual entity sabotage causes an outage; 02:17 is the first train, not a forced blackout.
- Retain original wooden benches, warm white station finishes, clear framed glazing and editable personal noticeboard notes.
- Keep the removed west empty space closed. The janitor/storage room is in the east wing.

## Foundations and fixes

- [x] Shared interactable component with enabled state, prompts and cancellable holds.
- [x] Locked, jammed and power-dependent doors; actor obstruction query when closing.
- [x] Runtime baked navigation and common collision layer constants.
- [x] Assertion-based tests with failure exit codes.
- [x] Stairs, enclosed entrance, fare barrier, track guard, wall/frame/prop fit fixes.
- [x] Repeated sleepers consolidated into a MultiMesh and one collision body.
- [x] Author the Restroom, Security, Electrical, and Storage shells as editable room scenes. Walls, floor sections, frames, and restroom stall partitions have scene-owned collision. Shared station geometry and gameplay devices still initialize at runtime.
- [x] Ignore generated .godot, .freebuff, .serena and builds directories when sharing source.

## Phase 1 — core systems

- [x] GameManager clock, night, power state and objective HUD.
- [x] 02:17 train approach, coaches, doors, boarding and departure.
- [x] Event-driven power faults, repair puzzle, light/gate power response.
- [x] Staff ID, maintenance key, mop and spare battery inventory.
- [x] Positional ambience, footsteps, mechanical effects and separate audio buses.
- [x] Pause, settings and save/load.
- [ ] Replace prototype synthesis with an authored ambience/music mix; dedicated flicker presentation remains limited.

## Phase 2 — the four jobs

- [x] NPC spawning, queue movement and booth interaction.
- [x] Three rounds of ticket checks, draggable documents, rules and accept/deny.
- [x] Verdict-linked gate access, platform seats and train boarding.
- [x] Trash spawning, mop pickup, hold cleaning and cleanliness consequence.
- [x] Wire matching and main switch after damage.
- [x] Repairable light, door and gate faults.
- [x] Three live Security camera monitors.
- [x] Restroom stalls, sinks, toilets and hiding.
- [x] Passenger danger timer, follow-to-safety rescue and per-night loss quota.
- [ ] Tune queue timing, passenger rescue and fault frequency through full play sessions.

## Phase 3 — The Passenger

- [x] Rules and tells documented in ENTITY_DESIGN.md.
- [x] Navigation; dormant, stalk, hunt, retreat and banished states.
- [x] Sight cone, obstruction checks, hearing, flashlight response and crouch hiding.
- [x] Attack, death, retry and saved-shift recovery flow.
- [x] Three clues, journal, Security identification and sustained-light counter.
- [ ] Authored entity model, animation, scare sequence and finished sound design. The current entity and death screen are functional placeholders.

## Phase 4 — look and feel

- [x] Bright debug off by default; warm-white station palette and optional fog/retro treatment.
- [x] Optional pixel/color/dither screen effect in Settings.
- [ ] Vertex snapping, final volumetric-light treatment and complete PS2 art pass.
- [x] Furnished booth, steel Electrical door, original wooden seating and framed glazing.
- [ ] Replace remaining primitive people, train and props with finished low-poly assets.
- [x] Room signs, noticeboard, moving wall clock and text PA announcements.
- [x] Female neural PA announcements, an authored false call and original weathered station posters.
- [ ] Final headphone/speaker audio mix and human listening review.
- [x] East janitor/storage room is now available on every night, per the newer request.
- [ ] Broader authored layout changes between nights. The janitor room now stays accessible throughout the campaign.

## Phase 5 — content and shipping

- [x] Night 1 objective prompts introduce sign-in, tickets, patrol, cleaning and containment.
- [x] Nights 1–7 progress with changing document cases, anomalies, faults, locks and stricter loss rules.
- [x] One distinct authored incident on each of seven nights, with saved progression and co-op support.
- [ ] Human playthrough and pacing review of the complete seven-night campaign.
- [x] 06:00 report, successful-night progression, campaign totals and four outcome screens.
- [ ] Narrative ending scenes and a paced tutorial; current outcomes are text screens.
- [x] Main menu, Continue, settings, toggle crouch/sprint and credits.
- [ ] Playtest with 3–5 people and tune stamina, AI, task timing and difficulty.
- [x] Native rendered visual QA and repeatable performance profiling.
- [ ] Human audio/controller QA and outside playtesting.
- [ ] Signed/notarized macOS release and actual Windows playtest. See builds/README.md for export status.

The remaining unchecked items need further content, direct visual review or outside testers. They are not marked complete merely because the systems exist.
