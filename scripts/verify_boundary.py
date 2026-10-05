#!/usr/bin/env python3
"""Run boundary rendering/lifecycle tests on the library's leased simulator."""
import argparse
import subprocess
from verify import ROOT, lease

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--keep-simulator', action='store_true')
args = parser.parse_args()
output = ROOT / '.artifacts/boundary-tests'
output.mkdir(parents=True, exist_ok=True)
with lease(None, None, keep=args.keep_simulator) as udid:
    with (output / 'test.log').open('w') as log:
        subprocess.run([
            'xcodebuild', '-scheme', 'AnchoredOverlayKit',
            '-destination', 'id=' + udid, '-parallel-testing-enabled', 'NO',
            '-derivedDataPath', str(output / 'DerivedData'), 'test',
        ], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
print('Boundary tests passed. Log:', output / 'test.log')
