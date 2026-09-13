#!/usr/bin/env python3
"""Validate cold Battery Saver initialization; restore battery settings on exit."""
import argparse
from pathlib import Path
import subprocess
import threading

parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--after-launch', action='store_true',
                    help='Enable Saver once visible, before policy creation (for OEM install-time sleep).')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
adb = ['adb', '-s', args.device]
def run(*command):
    return subprocess.check_output([*adb, *command], text=True).strip()

battery = run('shell', 'dumpsys', 'battery')
if 'UPDATES STOPPED' in battery:
    raise SystemExit('Device already has battery overrides; preserve those and use another target.')
original = {key: run('shell', 'settings', 'get', 'global', key)
            for key in ['low_power', 'low_power_sticky']}
process = None
timer = None
try:
    if not args.after_launch:
        run('shell', 'dumpsys', 'battery', 'unplug')
        run('shell', 'cmd', 'power', 'set-mode', '1')
    process = subprocess.Popen(['flutter', 'test', 'integration_test/power_policy_test.dart', '-d', args.device,
        *(['--dart-define=POWER_AFTER_LAUNCH=true'] if args.after_launch else [])],
        cwd=root / 'example', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    def timeout():
        print('Timed out: keep the Android device unlocked with the test app visible.', flush=True)
        process.terminate()
    timer = threading.Timer(240, timeout)
    timer.daemon = True
    timer.start()
    for line in process.stdout:
        print(line, end='', flush=True)
        if 'REFRESH_RATE_HOST_POWER_ON' in line:
            run('shell', 'dumpsys', 'battery', 'unplug')
            run('shell', 'cmd', 'power', 'set-mode', '1')
        if 'REFRESH_RATE_HOST_POWER_OFF' in line:
            run('shell', 'cmd', 'power', 'set-mode', '0')
    raise SystemExit(process.wait())
finally:
    if timer: timer.cancel()
    if process is not None and process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
    run('shell', 'dumpsys', 'battery', 'reset')
    run('shell', 'cmd', 'power', 'set-mode', '1' if original['low_power'] == '1' else '0')
    for key, value in original.items():
        if run('shell', 'settings', 'get', 'global', key) != value:
            run('shell', 'settings', 'delete' if value == 'null' else 'put', 'global', key,
                *([] if value == 'null' else [value]))
