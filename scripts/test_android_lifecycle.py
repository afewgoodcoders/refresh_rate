#!/usr/bin/env python3
"""Exercise real OS lifecycle transitions on an already-running Android target."""
import argparse
import pathlib
import re
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
adb = ['adb', '-s', args.device]

def run(*command):
    return subprocess.run([*adb, *command], check=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()

rotation = run('shell', 'settings', 'get', 'system', 'user_rotation')
# Android 11 calls this command set-user-rotation; Android 12 renamed it.
api_level = int(run('shell', 'getprop', 'ro.build.version.sdk'))
rotation_command = 'set-user-rotation' if api_level <= 30 else 'user-rotation'
if api_level <= 30:
    # Android 11 has no window-manager query mode.
    rotation_mode = ('free' if run('shell', 'settings', 'get', 'system',
                                'accelerometer_rotation') == '1' else 'lock')
else:
    # Query the active policy: persisted settings can lag a preceding shell
    # rotation change, especially when lifecycle runs follow one another.
    saved_rotation = run('shell', 'wm', rotation_command).split()
    rotation_mode = saved_rotation[0]
    if rotation_mode == 'lock':
        rotation = saved_rotation[1]
print(f'Rotation fixture: preserve {rotation_mode} {rotation}.', flush=True)
process = None
timeout = None
errors = []
workers = []

def resume():
    try:
        time.sleep(2)
        component = run('shell', 'cmd', 'package', 'resolve-activity', '--brief',
                        'in.qoder.refresh_rate_example').splitlines()[-1]
        if '/' not in component:
            raise RuntimeError('Example launcher activity could not be resolved')
        run('shell', 'am', 'start', '-n', component)
    except Exception as error:
        errors.append(error)

try:
    process = subprocess.Popen(['flutter', 'test', 'integration_test/lifecycle_test.dart',
                                '-d', args.device, '--reporter', 'expanded'], cwd=root / 'example', text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    timeout = threading.Timer(180, process.terminate)
    timeout.daemon = True
    timeout.start()
    for line in process.stdout:
        print(line, end='', flush=True)
        if 'REFRESH_RATE_HOST_BACKGROUND' in line:
            run('shell', 'input', 'keyevent', 'KEYCODE_HOME')
            worker = threading.Thread(target=resume)
            workers.append(worker)
            worker.start()
        elif 'REFRESH_RATE_HOST_ROTATE' in line:
            snapshot = run('shell', 'dumpsys', 'input')
            viewport = re.search(r'Viewport INTERNAL: displayId=0,.*?orientation=(\d)', snapshot)
            if viewport is None:
                raise RuntimeError('Cannot determine actual display rotation')
            target = (int(viewport.group(1)) + 1) % 4
            run('shell', 'wm', rotation_command, 'lock', str(target))
    code = process.wait()
    timeout.cancel()
    for worker in workers:
        worker.join()
    if errors:
        raise RuntimeError(str(errors))
    raise SystemExit(code)
finally:
    if timeout is not None:
        timeout.cancel()
    if process is not None and process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
    run('shell', 'wm', rotation_command, 'lock', rotation if rotation != 'null' else '0')
    if rotation_mode == 'free':
        run('shell', 'wm', rotation_command, 'free')
