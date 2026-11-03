# Four-player co-op prototype

One player hosts the campaign; up to three teammates join. Use the same source/build revision on every machine.

## Playing

1. Choose **Host Game**, select a UDP port (default **27017**), and create the lobby.
2. Teammates choose **Join Game**, enter the host computer's LAN IP address and the same port, then connect. `127.0.0.1` only connects to a host on the same computer.
3. Each teammate presses Ready. The host chooses a new campaign or the host's saved campaign.
4. The shift starts when all connected machines finish loading. The lobby locks during gameplay.
5. Switch on the Electrical Room’s main power. Every connected player, including the host, must then sign the rear booth logbook individually. The station opens and passengers arrive only after the last signature. The logbook and HUD show the crew’s progress.

Repeated signing counts once. An unsigned player who leaves is removed from the requirement. Restarting the shift clears all signatures. Partial signatures resume only within the same host session and shift; a new lobby must sign again. An already-open saved station resumes without replaying its opening announcement.

For connections across the internet, the host's UDP port must be reachable, usually through port forwarding or an existing private network. Steam invites, room-code discovery, NAT traversal and a relay service are not implemented.

## Shared and personal behavior

- The host controls the clock, passenger AI, trains, entity, doors, gates, cleaning, repairs, stock, rewards, and canonical campaign save.
- Credits, supplies, tools, collected clues, and objectives belong to the crew. Flashlight charge, stamina, cameras, photos and open UI remain local. Consumable requests debit the shared inventory once on the host.
- One local first-person controller runs on each computer. Other staff appear as simple third-person avatars; final art/animation is pending.
- Shared actions go through host validation. Ticket requests include the passenger ID so two clerks cannot accidentally process different passengers with the same stale UI. Purchases and cleaning rewards are serialized on the host.
- Escape opens personal settings without pausing the station. The host controls restart, loading, and next-night progression. Anyone may leave.
- Entity targeting and flashlight checks include teammates. Rescued passengers follow the staff member who helped them; if that member disconnects they follow the host.
- Current death behavior ends the crew's shift when a staff member is caught. Individual downing/revival is not implemented.
- Departing players are removed. Host departure returns clients to the main menu. There is no host migration or joining an ongoing shift; reconnect in a new lobby.
- Host saves retain the existing world checkpoint. Teammates spawn at staff entry on a loaded/restarted shift; their individual positions/charges are not campaign checkpoints.

## Network behavior and validation

ENet carries reliable lobby, scene, transaction and world-state messages. Scene generations reject old traffic after a restart. Player poses update at 20 Hz, world motion at 10 Hz, and canonical state at 4 Hz. Remote motion is interpolated. Passenger profiles are sent when the roster changes, not every motion tick. Motion batches stay below ENet's MTU for the default crowd.

Player movement is predicted locally, with host bounds, displacement and wall checks. This is a cooperative prototype, not a complete server-simulated movement/reconciliation or anti-cheat system.

Run the real multi-process test with:

```sh
python3 tools/test_coop.py --godot /absolute/path/to/Godot
```

It launches a host, three clients and a rejected extra client, using temporary saves and logs. It exercises lobby/readiness, local controller isolation, the full crowd, shared sign-in and cleaning, competing purchases/ticket decisions, invalid requests, personal pause, host save ownership, train replication, a teammate's flashlight, restart generations and disconnects.

Local headless tests do not establish graphical frame rate, internet latency, packet-loss tolerance or a complete seven-night playthrough. Those need rendered multi-computer testing before a smooth-online-play claim.

Reference: [Godot 4.7 high-level multiplayer](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html).

Current source uses protocol 6. All players need the same updated build. Incident stages, tracked passenger, warning time and final clearances are host-owned and replicated. The new passenger mesh/appearance system retains host-owned routes and deterministic identity; the multi-process test additionally checks all 24 appearances against the host. Personal accessibility settings remain local. Run all source suites with `python3 tools/test_source.py --godot /absolute/path/to/Godot`.

Optional local latency QA: `python3 tools/test_coop.py --godot /absolute/path/to/Godot --latency-ms 60 --jitter-ms 10 --packet-loss 0.005`. This relays localhost UDP with 60 ms one-way delay, ±10 ms jitter and 0.5% packet loss; it does not model every internet condition.

The pacing revision replicates optional sighting/aftermath state and campaign discoveries. Camera viewers send transient observations; one teammate looking away cannot remove the figure while another is watching. Viewer heartbeats do not throttle verdicts/purchases. The archive reader stays local; its validated evidence is shared. Live Night 4 transitions play interrupted PA locally once, while initial/restored snapshots do not replay it.
