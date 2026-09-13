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
rotation_mode = run('shell', 'wm', 'user-rotation').split()[0]
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
                                '-d', args.device], cwd=root / 'example', text=True,
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
            run('shell', 'wm', 'user-rotation', 'lock', str(target))
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
    run('shell', 'wm', 'user-rotation', 'lock', rotation if rotation != 'null' else '0')
    if rotation_mode == 'free':
        run('shell', 'wm', 'user-rotation', 'free')
