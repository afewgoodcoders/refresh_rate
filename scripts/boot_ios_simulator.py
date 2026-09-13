"""Select an available iPhone simulator and expose its ID to GitHub Actions."""
import json
import os
from pathlib import Path
import subprocess

all_devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
phones = [d for runtime, devices in all_devices['devices'].items() if '.iOS-' in runtime
          for d in devices if d.get('isAvailable') and d['name'].startswith('iPhone')]
if not phones:
    raise SystemExit('No available iPhone simulator runtime')
device = next((d for d in phones if d['state'] == 'Booted'), phones[0])
if device['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True)
with Path(os.environ['GITHUB_ENV']).open('a') as env:
    env.write('IOS_TEST_DEVICE=' + device['udid'] + '\n')
print('Using simulator:', device['name'], device['udid'])
