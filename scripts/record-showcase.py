#!/usr/bin/env python3
"""Record one continuous README demo; all Simulator setup precedes capture."""
import argparse
import hashlib
import json
import os
import plistlib
import select
import signal
import subprocess
import time
from pathlib import Path

from verify import BUNDLE, ROOT, UI, lease, run, sim


def source_digest(directory):
    digest = hashlib.sha256()
    for path in sorted(directory.rglob('*')):
        if path.is_file() and path.suffix in {'.swift', '.jpg', '.plist', '.pbxproj', '.xcscheme'}:
            digest.update(str(path.relative_to(ROOT)).encode() + b'\0' + path.read_bytes() + b'\0')
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', default='com.apple.CoreSimulator.SimRuntime.iOS-26-4')
    parser.add_argument('--output', type=Path, default=ROOT / '.artifacts/showcase')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    (ROOT / '.artifacts').mkdir(exist_ok=True)
    with lease(None, args.runtime) as udid:
        build = ['xcodebuild', '-project', str(ROOT / 'Examples/OverlayDemo.xcodeproj'),
                 '-scheme', 'OverlayDemo', '-configuration', 'Release',
                 '-sdk', 'iphonesimulator', '-destination', 'id=' + udid]
        with (args.output / 'build.log').open('w') as log:
            subprocess.run([*build, 'build'], check=True, stdout=log,
                           stderr=subprocess.STDOUT, timeout=300)
        settings = json.loads(run(*build, '-showBuildSettings', '-json'))[0]['buildSettings']
        app = Path(settings['TARGET_BUILD_DIR']) / settings['FULL_PRODUCT_NAME']
        with (app / 'Info.plist').open('rb') as file:
            assert plistlib.load(file).get('CADisableMinimumFrameDurationOnPhone') is True, 'ProMotion opt-in missing'
        sim('install', udid, str(app))
        helper = ROOT / '.artifacts/software-keyboard'
        run('xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-framework', 'Foundation',
            str(ROOT / 'scripts/software-keyboard.m'), '-o', str(helper))
        run(str(helper), os.environ.get('DEVELOPER_DIR') or run('xcode-select', '-p').strip(), udid)
        sim('ui', udid, 'appearance', 'light')
        sim('status_bar', udid, 'override', '--time', '9:41', '--dataNetwork', 'wifi',
            '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
        subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
        sim('launch', udid, BUNDLE, '--showcase', '-AppleLanguages', '(en)', '-AppleLocale', 'en_US')
        ui = UI(udid, args.output)
        ui.element('showcase-input')
        ui.keyboard()
        # A fresh runtime may show keyboard onboarding. Complete it before
        # capture, then require an actual software key rather than its host.
        if any(item.get('AXLabel') == 'Continue' and item.get('type') == 'Button'
               for item in ui.state()):
            ui.axe('tap', '--label', 'Continue', '--element-type', 'Button',
                   '--tap-style', 'physical', '--post-delay', '.5')
        ui.wait(lambda items: any(item.get('AXLabel') == 'f' and item.get('type') == 'Button'
                                  for item in items), 'Software keys missing')
        time.sleep(1)
        ui.capture('ready')
        initial = ui.element('showcase-input')['AXValue']
        assert initial == 'A few favorites '

        video = args.output / 'capture.mp4'
        video.unlink(missing_ok=True)
        recorder = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo',
                                     '--codec=hevc', str(video)], stderr=subprocess.PIPE,
                                    stdout=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if select.select([recorder.stderr], [], [], .5)[0]:
                    line = recorder.stderr.readline()
                    if b'Recording started' in line:
                        break
                    if not line:
                        raise RuntimeError('Recorder exited before capture')
            else:
                raise RuntimeError('Recorder did not start')
            # One HID session keeps the demonstration paced, without AX dumps
            # or capture pauses between actions. Each action occurs only once.
            steps = [
                'sleep 0.8',
                'tap --id showcase-plus --post-delay 1.0',
                'tap --id showcase-photos --post-delay 1.4',
                'tap --id photo-0 --post-delay 0.7',
                'tap --id photo-2 --post-delay 1.0',
                'tap --id photos-done --post-delay 1.5',
                'tap --label f --element-type Button --tap-style physical --post-delay 0.3',
                "type 'rom the weekend'",
                'sleep 1.5',
            ]
            command = ['axe', 'batch', '--udid', udid, '--tap-style', 'simulator',
                       '--ax-cache', 'perStep', '--wait-timeout', '3']
            for step in steps:
                command.extend(['--step', step])
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (args.output / 'interaction.log').write_text(result.stdout + result.stderr)
            result.check_returncode()
        finally:
            recorder.send_signal(signal.SIGINT)
            recorder.wait(timeout=20)
            recorder.stderr.close()
        ui.capture('finished')
        for index in range(2):
            ui.element('showcase-attachment-' + str(index))
        assert ui.element('showcase-input')['AXValue'] == initial + 'from the weekend', 'Keyboard focus lost'
        assert ui.element('showcase-plus')['AXValue'] == 'closed', 'Overlay cleanup incomplete'
        metadata = {
            'libraryVersion': json.loads((ROOT / 'package.json').read_text())['version'],
            'libraryCommit': run('git', 'rev-parse', 'HEAD').strip(),
            'libraryHasLocalChanges': subprocess.run(['git', 'diff', '--quiet', '--', 'Sources']).returncode != 0,
            'librarySourceSHA256': source_digest(ROOT / 'Sources'),
            'exampleSourceSHA256': source_digest(ROOT / 'Examples'),
            'runtime': args.runtime, 'xcode': run('xcodebuild', '-version').strip(),
            'configuration': 'Release',
            'captureCodec': 'hevc',
            'tapStyle': 'simulator',
            'steps': steps, 'continuous': True, 'playbackSpeed': 1,
            'verification': ['two mounted attachments', 'continued physical keyboard input', 'overlay cleanup'],
        }
        (args.output / 'recording.json').write_text(json.dumps(metadata, indent=2) + '\n')
        print(json.dumps({'video': str(video), 'status': 'passed'}), flush=True)


if __name__ == '__main__':
    main()
