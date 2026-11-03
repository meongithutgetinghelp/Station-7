"""Run Godot regression suites without touching the player's save file."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--output', default='builds/coop-prototype/qa/passenger-redesign')
args = parser.parse_args()
project = Path(__file__).resolve().parents[1]
output = (project / args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
suites = ['horror_pacing', 'night_events', 'performance', 'ui_refresh', 'atmosphere', 'robot_camera', 'station_finishes', 'opening_flow', 'scratch', 'cleaning', 'core', 'jobs_entity', 'passenger', 'train',
          'campaign', 'passenger_activities', 'update_systems', 'crowd_monitor',
          'menu_transition', 'entity_animation', 'passenger_visual', 'shift_guidance',
          'entity_letter', 'passenger_dialogue', 'booth_desk', 'train_model', 'booth_interruption', 'beta_fixes', 'hands_interior', 'stability', 'tutorial_playthrough', 'playability', 'campaign_playthrough']
results = []
for suite in suites:
    with (output / f'{suite}.log').open('w') as log:
        try:
            result = subprocess.run([args.godot, '--headless', '--path', str(project),
                                     '--fixed-fps', '60', '--script', f'{suite}_test_runner.gd'],
                                    stdout=log, stderr=subprocess.STDOUT, timeout=240 if suite == 'campaign_playthrough' else 90)
            status = result.returncode
        except subprocess.TimeoutExpired:
            status = -1
    text = (output / f'{suite}.log').read_text()
    record = {'suite': suite, 'exit': status, 'checks': text.count('PASS:'),
              'script_errors': text.count('SCRIPT ERROR'), 'errors': text.count('ERROR:')}
    results.append(record)
    print(json.dumps(record), flush=True)
(output / 'results.json').write_text(json.dumps(results, indent=2))
raise SystemExit(1 if any(r['exit'] or r['errors'] or r['script_errors'] for r in results) else 0)
