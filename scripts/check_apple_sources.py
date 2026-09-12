"""Keep CocoaPods and SPM entry points identical; --sync refreshes mirrors."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
pairs = [
    ('ios/refresh_rate/Sources/refresh_rate/RefreshRatePlugin.swift', 'ios/Classes/RefreshRatePlugin.swift'),
    ('ios/refresh_rate/Sources/refresh_rate/generated/RefreshRateApi.swift', 'ios/Classes/generated/RefreshRateApi.swift'),
    ('ios/refresh_rate/Sources/refresh_rate_objc/DisplayLinkSwizzle.m', 'ios/Classes/DisplayLinkSwizzle.m'),
    ('macos/Classes/RefreshRatePlugin.swift', 'macos/refresh_rate/Sources/refresh_rate/RefreshRatePlugin.swift'),
    ('macos/Classes/generated/RefreshRateApi.swift', 'macos/refresh_rate/Sources/refresh_rate/generated/RefreshRateApi.swift'),
]
failed = []
for source, mirror in pairs:
    source, mirror = root / source, root / mirror
    if '--sync' in sys.argv:
        mirror.parent.mkdir(parents=True, exist_ok=True)
        mirror.write_bytes(source.read_bytes())
    if source.read_bytes() != mirror.read_bytes():
        failed.append(str(mirror.relative_to(root)))
if failed:
    raise SystemExit('Apple source mirrors differ: ' + ', '.join(failed))
print('Apple source mirrors agree.')
