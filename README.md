# Station 7

Station 7 is a first-person cooperative horror game prototype set in a railway station during the night shift. Restore power, open the station with your crew, inspect passengers, and keep the station running as unusual incidents escalate across seven nights.

## What you can play

- Host a campaign for up to four players over LAN or direct IP.
- Restore main power and have every crew member sign the booth logbook to open the station.
- Inspect tickets and passenger documents, monitor CCTV, and respond to train arrivals and station incidents.
- Clean the station, repair electrical faults, and investigate clues about anomalous passengers.
- Resume a campaign from the host's saved checkpoint.

## Requirements and setup

Use **Godot 4.7.2** and a system that supports the project's Forward+ renderer. Import `project.godot` in Godot Project Manager, wait for the assets to import, and press **F5**. Use the same project revision on all machines.

1. The host selects **Host Game** and creates a lobby. The default port is **UDP 27017**.
2. Teammates select **Join Game** and enter the host's LAN IP address and port.
3. Teammates mark themselves ready. The host starts a new campaign or resumes a saved campaign.
4. Turn on main power in the Electrical Room, then have every crew member sign the booth logbook.

Use **WASD** and the mouse to move and look, **E** to interact, **F** for the flashlight, and **J** for the duty journal.

## Prototype limitations

Character art and animations are provisional. Internet invites, matchmaking, relay support, mid-shift joining, host migration, and individual player revival are unimplemented. Use a trusted LAN for playtesting. See [COOP.md](docs/COOP.md) for session behavior and test commands.

## Project layout

| Folder | Contents |
| --- | --- |
| [scenes/](scenes/) and [rooms/](rooms/) | Main scenes, shared resources, and room layouts |
| [scripts/](scripts/) | Gameplay, networking, and station systems |
| [assets/](assets/), [audio/](audio/), and [ui/](ui/) | Models, sound, and interface assets |
| [tests/](tests/) and [tools/](tools/) | Automated checks and development tools |
| [docs/](docs/) | Co-op setup, campaign design, and playtest notes |
