"""Generate every native binding from the pinned Pigeon schema.

Use --check to fail when checked-in generated sources differ from the schema.
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
outputs = [
    'lib/src/generated/refresh_rate_api.g.dart',
    'android/src/main/kotlin/in/qoder/refresh_rate/generated/RefreshRateApi.kt',
    'ios/refresh_rate/Sources/refresh_rate/generated/RefreshRateApi.swift',
    'ios/Classes/generated/RefreshRateApi.swift',
    'macos/Classes/generated/RefreshRateApi.swift',
    'macos/refresh_rate/Sources/refresh_rate/generated/RefreshRateApi.swift',
    'linux/refresh_rate_api.g.h', 'linux/refresh_rate_api.g.cc',
    'windows/refresh_rate_api.g.h', 'windows/refresh_rate_api.g.cpp',
]
before = {name: (root / name).read_bytes() if (root / name).exists() else None for name in outputs}
subprocess.run(['dart', 'run', 'pigeon', '--input', 'pigeons/refresh_rate_api.dart'], cwd=root, check=True)
swift = (root / outputs[2]).read_text().replace('import Flutter\n', 'import FlutterMacOS\n')
(root / 'macos/Classes/generated/RefreshRateApi.swift').write_text(swift)
subprocess.run([sys.executable, 'scripts/check_apple_sources.py', '--sync'], cwd=root, check=True)
# Pigeon 22 emits trailing spaces in switch cases and GObject error handlers.
# Normalize deterministically here so generation and whitespace checks agree.
for name in outputs:
    path = root / name
    path.write_text('\n'.join(line.rstrip() for line in path.read_text().splitlines()) + '\n')
changed = [name for name in outputs if before[name] != (root / name).read_bytes()]
if '--check' in sys.argv and changed:
    raise SystemExit('Generated bindings differ: ' + ', '.join(changed))
print('Generated bindings agree with Pigeon schema.' if '--check' in sys.argv else 'Generated all native bindings.')
