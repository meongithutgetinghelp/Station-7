**Current update:** multiplayer is now implemented as a four-player prototype. See [COOP.md](COOP.md) and [PASSENGER_REDESIGN.md](PASSENGER_REDESIGN.md). The local-only statements below describe the earlier update, before co-op work.

> Update, 1 November 2026: four-player LAN/direct-IP co-op is now implemented as a tested prototype. See COOP.md and the latest PROGRESS.md section; local-only statements below describe the older 31 October revision.

# Requested systems and environment update — implementation tracker

Source requirements: the user's 31 October gameplay, systems and environment update. Existing features are extended in place. Each stage is checked before proceeding. Entries below describe this update, not the older baseline checklist.

- [x] Slim cylindrical mop handle, socket and separate cotton strands.
- [x] Clean initial floor; random dirt only while passengers are present; reusable dirt spots and save/load.
- [x] Rectangular station bins near walls, oriented into the room.
- [x] Safe passenger-disguise-only entity behavior on Nights 1–3; attacks/kidnappings from Night 4.
- [x] Outside/stairway arrivals, both seat orientations, corrected seated joints, passenger activities and VIP lounge visits.
- [x] Smooth player-controlled CCTV and seated booth workstation.
- [x] Gender/document consistency, separate stolen-ticket vs impersonation investigations, fictional government registry terminal.
- [x] Human-scale player, first-person hands and equipped broom/mop, battery, flashlight and phone.
- [x] Public hall ceiling lowered to 7 m at the user’s request, adjusted lighting, charging area and janitor room/equipment holder.
- [x] Audible PA chime and editable recording slots; custom-clip playback checked.
- [x] Spoken PA voice lines: awaiting the user’s own recordings; none were generated.
- [x] Shopkeeper, food/drinks/batteries and player/passenger purchases.
- [x] Phone balance, persistent economy, nonrepeatable rewards and photo foundation.
- [x] Separate signed women/men restroom entrances, connected sinks, correctly fitted stall doors and shaped toilets.
- [x] Final integrated headless checks: 262 passing checks across 11 suites.
- [x] Refreshed both exports; the packaged macOS menu and full station start headlessly without script errors; rapid station shutdown reports four retained objects.
- [ ] Direct graphical/audio/photo QA and outside playtesting.

Native Godot UI access was denied earlier in this session. Automated checks can validate behavior, dimensions and collision, but direct graphical/audio review remains unverified. The inspected source had no networking system; gameplay remains local.

## Verification and practical limits

- Integration checks exercise real collision/navigation routes for exterior stair arrivals, both seating areas, Smoking, Restroom, VIP Lounge, kiosk purchases, boarding and street exits.
- System checks cover clean startup, passenger-only random litter, cleaning, bin clearance, early-night safety, later-night attacks, government-record outcomes, seated saves, money/reward idempotency, charging, equipment, CCTV pan and custom PA stream playback.
- Photos require a rendered game window. File capture is implemented but screenshot contents and visual/audio quality remain pending direct review.
- Hands, people, furniture and toilets use authored procedural geometry. They are functional, but finished animation/art quality has not been visually approved.
- Existing source had no network synchronization or lobby/session flow. The systems remain local; this update does not claim multiplayer implementation.

All eleven suites passed. The final crowd/monitor, core and update-system rechecks passed without script errors or warnings. PA sequencing now uses an owned timer and stops its audio during teardown; rendered audio review remains pending.

## Latest crowd, CCTV and bathroom changes

- Eight arrivals per group, three groups per new shift (24 people); arrivals begin before staff sign-in.
- Every newcomer completes two or three shuffled visits before requesting a ticket. Queue length is capped at six; others continue waiting activities.
- Six full-screen CCTV feeds with clickable station map, number keys, smooth pan and a lower-monitor control. Security and physical monitors open feeds directly.
- Both bathrooms expanded to 15 × 5 m gross, four toilets and four sinks each, with a real east-wing floor and roof extension. The bin was moved off the men’s entrance.
- Older in-progress saves retain their original passenger quota so those shifts remain completable. Start a fresh shift to see the new 24-person default.

### Further bathroom and proportion revision

Each side now has a 15 × 10 m main washroom plus a 10 × 5 m entrance foyer (about 200 m² gross). Four sinks line up opposite four toilets across an open aisle. Stalls are 2.2 × 3.2 m with 2.5 m partitions. Original wooden benches, office chairs and fare-gate assemblies were enlarged around the existing 1.72 m player. Floors, roof, lighting, navigation, hiding areas and passenger sitting anchors follow the new dimensions.
