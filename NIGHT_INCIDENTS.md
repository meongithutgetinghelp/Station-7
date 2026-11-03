# Authored night incidents

The opening sequence is unchanged: switch on mains power, then every connected crew member signs the rear logbook. Incidents begin after a fixed number of completed document checks, never during setup. Nights 1–3 remain observation-only.

| Night | Trigger | Incident and response |
|---|---|---|
| 1 — Exit seal | 2 checks | Inspect EXIT SEAL beside the entrance stairs. Introduces leaving the desk to verify station safety. |
| 2 — Dead line | 4 checks | CAM 04 loses signal. Use LINE RESET on the Security room's east wall. Other cameras stay live; the failed feed cannot award anomaly reports. |
| 3 — False last call | 4 checks | An unverified voiced cancellation conflicts with the official North Terminal service indicator on Platform 7. Select KEEP SERVICE. CANCEL gives a correction without harming passengers. |
| 4 — Overload | 6 checks | An 18-second warning allows preparation before mains power trips. Use the existing three-wire repair and main switch. |
| 5 — Roll call | 6 checks | Use ROLL CALL on the booth rear workbench. A cleared waiting passenger may need escort to the booth or Security; the scripted assistance interval is 90 seconds. If everyone cleared has already boarded, the register confirms them instead. A lost target can be reconciled at the register, but the loss still counts against the shift. |
| 6 — Split circuit | 8 checks | Repair the hall light at Electrical panel 2. This reveals a fault in the central gate reader; repair that reader next. |
| 7 — Final clearance | 4 checks | The train waits with boarding open until three clearances are signed. Booth requires all documents checked; Security requires confirmed intruder identity; Platform 7 requires a genuine passenger aboard. |

An active incident is a required shift duty. The compact HUD briefly shows its current step; J opens the full briefing, duties and station condition. Ordinary next-step prompts fade after ten seconds. Power and rescue guidance remain visible. Work panels hide the gameplay HUD.

## Persistence and co-op

NightEvents owns the incident stage, warning time, tracked passenger and signed clearances. The host owns transitions; clients use existing distance-validated physical interactions. Additive save-participant data restores state without replaying a fault, PA line or reward. Protocol 5 snapshots replicate current incident state; scene generations reject stale requests. Completion rewards are idempotent.

The new printed notices, scuffs and cable runs are static, reuse textures/materials, and add no solid collision or lights. Wall wear and cable clips use MultiMesh batches.

## Verification limits

night_events_test_runner.gd exercises all seven incident state machines, checkpoints before/after completion, duplicate actions, final-train hold/release, compact HUD behavior and seven consecutive successful campaign transitions. It uses controlled inspection/boarding statistics; it is not a human playthrough of every passenger. Separate existing suites cover real passenger movement, inspections, boarding, stairs, attacks, rescues, power and progression. The ENet suite covers incident replication, remote resolution, range validation and duplicate requests.

Human pacing, scare effectiveness, controller ergonomics, a full seven-night run by people and multi-computer internet play still need outside playtesting.
