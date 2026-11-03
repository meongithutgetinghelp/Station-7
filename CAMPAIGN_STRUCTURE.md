# Current Night 1–7 structure

Source audit, 2 November 2026. This describes implemented rules and briefings, not a completed human playthrough.

Every shift currently shares power repair/startup, crew sign-in, passenger document checks, platform patrol, cleaning and scheduled train boarding. Night 1 is now a shorter tutorial: 9 passengers in three groups of 3; subsequent nights retain 24 passengers in groups of 8. Existing longer tutorial saves keep their saved workload. Optional lost-property and help conversations are random; the incidents below are authored campaign duties.

| Night | Implemented focus | Main authored duty |
|---|---|---|
| 1 — First Service | Learn power, sign-in, the booth, staff gate access and patrol. The briefing already teaches that an impostor can be missing from the camera. | Inspect the entrance EXIT SEAL after two inspections. |
| 2 — A Face in the Window | Impersonators appear earlier; compare the person at the window with camera evidence. | Restore CAM 04 at Security's LINE RESET junction; other feeds continue operating. |
| 3 — Borrowed Identities | Stolen tickets, identity mismatches and missing issue stamps increase document complexity. | Verify a false cancellation announcement against official dispatch and keep the genuine service running. |
| 4 — After the Last Call | The entity can hunt outside the queue. Collect three reports, identify it at Security and conserve flashlight charge. | An overload gives an 18-second preparation warning before a power failure. |
| 5 — Everyone Accounted For | Passenger protection and shared work become central; the briefing requires no passenger losses from this night onward. | Reconcile the roll call and escort the marked passenger to safety. |
| 6 — Failing Infrastructure | Inspections, rescues and maintenance compete. Repair damaged lights, gates and doors before finishing the shift. | Repair the hall-light circuit, then the central gate reader. |
| 7 — The Final Service | Expect an impostor in every wave. Protect passengers, confirm the intruder and complete the final service; campaign losses affect the ending. | Obtain Booth, Security and Platform clearances. The final train waits until the duty is complete. |

## Comparison with the proposed direction

- The existing escalation already broadly matches learning → evidence → active threat → overlapping duties → final clearance.
- Night 1 currently explains the missing-camera clue explicitly. Leaving that clue for players to discover would better support the proposed quiet first night and suspicious second night, but would require fair in-world teaching and fresh-player testing.
- Nights 1–3 still rely on discrete authored duties. The present CCTV system offers live views and camera-absence evidence; cross-feed behavioural/reflection investigations are a future addition, not a completed feature.
- Nights 4–7 could feel repetitive if the three reports, repairs and ticket waves repeat without new deductions. Test whether later evidence changes the player's interpretation instead of simply increasing workload.
- Document combinations already vary. Reputation/trust and future-incident consequences should be designed as a connected extension after stabilization, rather than assumed to exist.
- Four-player readiness and shared authoritative actions exist. Flexible responsibilities are a good direction; avoid locking tasks behind classes that block players from helping each other.
- The final clearance is implemented. A distinct final investigative payoff and major confrontation still need evaluation against a full human playthrough.

## Recommended next pass

Finish the current hand and carriage work, then observe a seven-night human run. Record repeated tasks, unclear clues, progression blockers and downtime before deciding which new investigation mechanic earns its complexity.

References: `shift_guidance.gd` (briefings), `night_events.gd` (authored duties), `game_manager.gd` (campaign progression), `passenger_dialogue_events.gd` (optional random conversations).

## Implemented pacing revision — 2 November

Night 1 no longer receives automatic entity sabotage; Night 2 disturbances use a longer interval. Night 3 has one optional 35% camera-figure opportunity after five checks and outside an active authored duty; a miss stays a miss. Night 4 adds an actual departure aftermath: a retained SEAT 07 reservation, static platform figure and interrupted quiet PA, followed by a 20-second interval before the first automatic hunt. A time-based recovery supports old checkpoints. The Security archive and discovered letters/observations persist as optional campaign evidence; final epilogue lines respond to them without gating completion or changing ending eligibility. These are implemented, with tests recorded in builds/pacing-qa/REPORT.md; human pacing remains unverified.
