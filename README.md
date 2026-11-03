# Station 7

*A cooperative horror game set in a railway station after dark.*

Station 7 is a first-person cooperative horror game prototype where you and your crew work the night shift at an isolated railway station. Keep the station running, deal with unusual incidents, and figure out which passengers don't belong. What starts as an ordinary shift slowly becomes something much stranger.

## Features

- **Co-op multiplayer** — Play with up to four players over LAN or direct IP.
- **Station duties** — Restore power, inspect tickets, clean the station, and repair electrical faults.
- **Passenger inspection** — Check tickets and documents to identify suspicious passengers.
- **CCTV monitoring** — Keep an eye on the station through its security cameras.
- **Station incidents** — Respond to train arrivals and unexpected events throughout your shift.
- **Campaign progression** — Work through seven nights as things become increasingly unsettling.
- **Save system** — Resume your campaign from the host's saved checkpoint.

## Getting Started

**Requirements**

- Godot 4.7.2
- A system that supports the project's Forward+ renderer

**Setup**

1. Open Godot Project Manager.
2. Import the project using `project.godot`.
3. Wait for the assets to finish importing.
4. Press **F5** to launch the game.

**Playing with Friends**

1. The host selects **Host Game** to create a lobby.
2. Other players select **Join Game** and enter the host's IP address and port.
3. Joining players mark themselves as ready.
4. The host starts a new campaign or resumes a saved one.

The default multiplayer port is **UDP 27017**. All players should use the same project revision.

## Controls

| Key | Action |
| --- | --- |
| WASD | Move |
| Mouse | Look around |
| E | Interact |
| F | Flashlight |
| J | Duty journal |

## Current Limitations

Station 7 is still a prototype. Character art and animations are provisional.

The following features are not yet implemented:

- Internet invites and matchmaking
- Relay support
- Joining a session mid-shift
- Host migration
- Individual player revival

For playtesting, use a trusted LAN connection. Multiplayer behavior and test commands are documented in the [co-op guide](docs/COOP.md).

## Project Structure

| Folder | Description |
| --- | --- |
| [scenes/](scenes/) and [rooms/](rooms/) | Main scenes, shared resources, and room layouts |
| [scripts/](scripts/) | Gameplay, networking, and station systems |
| [assets/](assets/), [audio/](audio/), and [ui/](ui/) | Models, sound, and interface assets |
| [tests/](tests/) and [tools/](tools/) | Automated checks and development tools |
| [docs/](docs/) | Co-op setup, campaign design, and playtest notes |
