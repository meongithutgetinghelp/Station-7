# Station 7 — playability checks before more features

The current automated checks cover scripted rules and movement. These next checks need actual people and target computers.

## First-time player — Night 1

Give the player the game without explaining how to play. Observe:

- Can they find Electrical, start the power, and sign the logbook?
- Can they enter the staff side, sit, pick up a paper, use the computer, put the paper down, and use either stamp?
- Do they understand the difference between the person at the window and the live camera image?
- Can they leave the desk, scan their staff ID, inspect the platform, and find the exit seal?
- Does the nine-passenger shift teach enough without becoming repetitive?
- Can they explain why a decision was wrong and what is still needed to finish?

Record where they hesitate or ask for help; do not count an explanation from the observer as successful teaching.

## Complete campaign and recovery

- Finish Nights 1–7 as a human, including one mistaken approval and one mistaken denial.
- Try dying, retrying, loading a checkpoint and advancing to the next night.
- Close the game after an automatic checkpoint; confirm that continuing restores usable controls and consistent passenger/decision counts.
- Watch several complete boarding/departure cycles. Nobody should overlap, disappear at the platform edge, or remain aimed at a train that has left.
- Check whether the later nights provide interesting decisions or mainly repeat chores.

## Four-player session

- Use a real remote connection and assign flexible booth, platform, Security and repair duties.
- Try using the same target together, delayed document decisions, opening menus, and one client disconnecting.
- Confirm that each player sees the same queue, train, verdicts and objectives.
- Check death/shift reports: clients must retain a way to leave; only the host may retry/advance.

## Hardware and release

- Run a Windows build on Windows, and an exported macOS build on macOS.
- Run an extended busy session at the intended display resolution, recording frame-time spikes rather than only average FPS.
- Verify settings and save recovery after restarting the actual executable.
- Build release binaries only from the source revision that passed these checks.

For each issue, record the night, player count, last few actions, expected result, actual result, screenshot/video and relevant checkpoint. Keep copies of saves when testing interruption or corruption.

## New pacing: observe rather than explain

- Night 3: can someone notice the still figure on CAM 03, compare it with the world and understand that it is separate from ticket-verdict evidence? Test a run without the random opportunity too.
- Co-op: have two players watch the same feed; switch one away, then both. Check that dropout or closing a monitor cannot leave the sighting stuck.
- Night 4: watch a complete first departure and quiet aftermath. Check whether the reservation discrepancy is readable, and whether the pause before hostility helps tension. Save/load during the aftermath and try an outage.
- Read the archive by flashlight before opening and during normal work. Read a handwritten note, load, and advance nights; journal discoveries should persist.
- Finish with and without optional discoveries. The ending should remain understandable and its normal success conditions unchanged.
- Test reduced flashing and muted audio. This pass adds no light flashes or required sound-only clue.
