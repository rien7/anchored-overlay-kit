#!/usr/bin/env python3
"""Signed example build and isolated iOS Simulator acceptance (AXe + simctl).

No account, cloud, Metro, Expo, or consuming application is required.
One managed Simulator is leased under a file lock; personal devices are ignored.
An explicit --udid is caller-owned and is never shut down by this script.
"""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'dev.rien7.AnchoredOverlayDemo'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=120, **kwargs).stdout


def sim(*args):
    return run('xcrun', 'simctl', *args)


@contextmanager
def lease(explicit, runtime):
    if explicit:
        yield explicit
        return
    cache = Path.home() / 'Library/Caches/AnchoredOverlayKit'
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / 'simulator.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if runtime is None:
            runtimes = [r for r in json.loads(sim('list', 'runtimes', '--json'))['runtimes']
                        if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
            runtime = max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier']
        name = 'AnchoredOverlayKit Verify'
        devices = json.loads(sim('list', 'devices', '--json'))['devices'].get(runtime, [])
        device = next((d for d in devices if d['name'] == name and d.get('isAvailable')), None)
        udid = device['udid'] if device else sim('create', name, 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', runtime).strip()
        if not device or device['state'] != 'Booted':
            sim('boot', udid)
        try:
            sim('bootstatus', udid, '-b')
            yield udid
        finally:
            sim('shutdown', udid)


class UI:
    def __init__(self, udid, output):
        self.udid, self.output = udid, output
        self.prefix = ""
        output.mkdir(parents=True, exist_ok=True)

    def axe(self, *args):
        for attempt in range(6):
            try:
                result = run('axe', *args, '--udid', self.udid)
                break
            except subprocess.CalledProcessError as error:
                if args[0] != 'describe-ui' or attempt == 5:
                    raise RuntimeError(error.stderr or error.stdout) from error
                time.sleep(1)
        with (self.output / 'actions.jsonl').open('a') as log:
            log.write(json.dumps({'time': time.time(), 'command': ['axe', *args, '--udid', self.udid]}) + '\n')
        if result.startswith('Error:'):
            raise RuntimeError(result)
        return result

    def state(self):
        def flatten(node):
            if isinstance(node, list):
                for child in node:
                    yield from flatten(child)
            elif isinstance(node, dict):
                yield node
                for child in node.get('children', []):
                    yield from flatten(child)
        return list(flatten(json.loads(self.axe('describe-ui'))))

    def wait(self, predicate, message, timeout=15):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            found = predicate(self.state())
            if found:
                return found
            time.sleep(.25)
        raise AssertionError(message)

    def identifier(self, name):
        return self.prefix + name if name.startswith('demo-') else name

    def element(self, identifier):
        identifier = self.identifier(identifier)
        return self.wait(lambda items: next((i for i in reversed(items) if i.get('AXUniqueId') == identifier), None), 'Missing ' + identifier)

    def tap(self, identifier):
        frame = self.element(identifier)['frame']
        self.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.4')

    def capture(self, name):
        (self.output / (name + '.json')).write_text(self.axe('describe-ui'))
        sim('io', self.udid, 'screenshot', str(self.output / (name + '.png')))

    def no_menu(self):
        self.wait(lambda items: not any((i.get('AXUniqueId') or '').startswith(('menu-', 'swiftui-')) for i in items), 'Menu survived dismissal')
        self.wait(lambda items: any(i.get('AXUniqueId') == self.identifier('demo-plus') and i.get('AXValue') == 'closed' for i in items), 'Touch shields have not finished cleanup')

    def keyboard(self):
        return self.wait(lambda items: next((i['frame'] for i in items
                         if (i.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar')), None), 'Software keyboard missing')


def exercise(ui, sheet):
    ui.element('demo-input')
    if sheet:
        ui.axe('tap', '--label', 'Sheet', '--tap-style', 'physical', '--post-delay', '.7')
        ui.prefix = 'sheet-'
    ui.element('demo-input')
    ui.capture('unfocused')
    ui.tap('demo-plus')
    ui.element('menu-Files')
    ui.capture('unfocused-menu')
    ui.axe('tap', '-x', '380', '-y', '160', '--tap-style', 'physical', '--post-delay', '.3')
    ui.no_menu()
    if sheet:
        title = ui.wait(lambda items: next((i for i in items if i.get('AXLabel') == 'New session'), None), 'Missing sheet title')['frame']
        ui.axe('swipe', '--start-x', '200', '--start-y', str(title['y']), '--end-x', '200', '--end-y', '90', '--duration', '.5', '--post-delay', '.7')
        ui.capture('full-sheet')
    ui.tap('demo-input')
    ui.axe('type', 'overlay draft')
    keyboard = ui.keyboard()
    field = ui.element('demo-input')
    assert field.get('AXValue') == 'overlay draft', 'Initial draft missing'
    ui.tap('demo-plus')
    row = ui.element('menu-Recent Photos')['frame']
    assert row['y'] + row['height'] > keyboard['y'] + 1, 'Menu did not overlap keyboard keys'
    assert row['height'] >= 44
    ui.capture('over-keyboard')
    # Physical tap in menu/keyboard overlap proves the menu, not a key, receives it.
    overlap_y = (max(row['y'], keyboard['y']) + row['y'] + row['height']) / 2
    ui.axe('tap', '-x', str(row['x'] + row['width'] / 2), '-y', str(overlap_y), '--tap-style', 'physical', '--post-delay', '.4')
    ui.no_menu()
    assert 'Recent Photos · calls 1 · released true' in ui.element('demo-status')['AXLabel']
    assert ui.element('demo-input').get('AXValue') == 'overlay draft', 'Menu tap typed into draft'
    assert abs(ui.element('demo-input')['frame']['y'] - field['frame']['y']) < 1, 'Overlay changed input geometry'
    ui.capture('action-delivered')
    ui.tap('demo-plus')
    ui.axe('tap', '-x', '380', '-y', str(keyboard['y'] + 90), '--tap-style', 'physical', '--post-delay', '.4')
    ui.no_menu()
    assert ui.element('demo-input').get('AXValue') == 'overlay draft', 'Outside tap leaked into keyboard'
    ui.axe('tap', '--label', 'x', '--element-type', 'Button', '--tap-style', 'physical', '--post-delay', '.4')
    ui.wait(lambda items: any(i.get('AXUniqueId') == ui.identifier('demo-input') and i.get('AXValue') == 'overlay draftx' for i in items), 'Editor did not receive appended text')
    ui.capture('focus-retained')

    # Explicit public fallback, also used when the system host is unavailable.
    ui.tap('demo-fallback')
    ui.wait(lambda items: any(i.get('AXUniqueId') == ui.identifier('demo-fallback') and i.get('AXValue') == '1' for i in items), 'Fallback policy did not turn on')
    ui.tap('demo-plus')
    row = ui.element('menu-Recent Photos')['frame']
    assert row['y'] + row['height'] < keyboard['y'], 'Fallback went behind keyboard'
    ui.capture('above-keyboard')
    ui.axe('tap', '-x', '380', '-y', '160', '--tap-style', 'physical', '--post-delay', '.3')
    ui.no_menu()
    ui.tap('demo-fallback')
    ui.wait(lambda items: any(i.get('AXUniqueId') == ui.identifier('demo-fallback') and i.get('AXValue') == '0' for i in items), 'Fallback policy did not turn off')

    ui.axe('tap', '--label', 'Sheet SwiftUI menu' if sheet else 'SwiftUI menu', '--tap-style', 'physical', '--post-delay', '.4')
    ui.element('swiftui-Recent Photos')
    ui.capture('swiftui-menu')
    ui.tap('swiftui-Recent Photos')
    ui.no_menu()
    assert 'calls 2 · released true' in ui.element('demo-status')['AXLabel']

    for action in ['Files', 'Photo Library']:
        ui.tap('demo-plus')
        ui.element('menu-' + action)
        time.sleep(.5)
        ui.tap('menu-' + action)
        ui.no_menu()
        if action == 'Files':
            ui.wait(lambda items: any(i.get('AXLabel') == 'Cancel' for i in items), 'Files picker missing')
            ui.capture('files-picker')
            ui.axe('tap', '--label', 'Cancel', '--tap-style', 'physical', '--post-delay', '.6')
        else:
            # iOS 27 PHPicker is remote and AXe may return the underlying app tree.
            # Its close control was located visually in the captured phone viewport.
            time.sleep(2)
            ui.capture('photo-library-picker')
            ui.axe('tap', '-x', '38', '-y', '100', '--tap-style', 'physical', '--post-delay', '.6')
            ui.wait(lambda items: any(i.get('AXUniqueId') == ui.identifier('demo-status')
                    and 'picker returned' in i.get('AXLabel', '') for i in items), 'Photo picker did not call its completion')
        ui.element('demo-input')
    assert ui.element('demo-input').get('AXValue') == 'overlay draftx'
    assert 'calls 4 · released true' in ui.element('demo-status')['AXLabel']
    if any(i.get('AXLabel') == 'Continue' for i in ui.state()):
        ui.axe('tap', '--label', 'Continue', '--tap-style', 'physical', '--post-delay', '.5')
    ui.capture('pickers-returned')
    ui.tap('demo-input')
    ui.keyboard()
    ui.wait(lambda items: any(i.get('AXUniqueId') == ui.identifier('demo-input') and abs(i['frame']['y'] - field['frame']['y']) < 1 for i in items), 'Editor did not return above keyboard')
    assert 'calls 4 · released true' in ui.element('demo-status')['AXLabel'], 'Refocusing dispatched a menu action'
    for _ in range(3):
        ui.tap('demo-plus')
        ui.element('menu-Files')
        ui.axe('tap', '-x', '380', '-y', '160', '--tap-style', 'physical', '--post-delay', '.25')
        ui.no_menu()
        assert 'calls 4 · released true' in ui.element('demo-status')['AXLabel'], 'Outside dismissal dispatched a menu action'
    ui.tap('demo-plus')
    # Background cleanup must remove both application and keyboard shields.
    sim('launch', ui.udid, 'com.apple.Preferences')
    ui.wait(lambda items: not any(i.get('AXUniqueId') == 'demo-plus' for i in items), 'Application did not background')
    ui.capture('background')
    sim('launch', ui.udid, BUNDLE)
    ui.element('demo-input')
    ui.no_menu()
    ui.capture('background-return')
    if sheet:
        ui.axe('tap', '--label', 'close', '--tap-style', 'physical', '--post-delay', '.6')
        ui.wait(lambda items: not any(i.get('AXUniqueId') == 'sheet-demo-input' for i in items), 'Sheet did not close')
        ui.prefix = ''
        ui.element('demo-input')
        ui.capture('sheet-closed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--udid')
    parser.add_argument('--runtime')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--host', choices=['chat', 'sheet'])
    parser.add_argument('--appearance', choices=['light', 'dark'])
    parser.add_argument('--output', type=Path, default=ROOT / '.artifacts/acceptance')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    plan = [{'id': host, 'title': host + ' host preserves editing and routes keyboard-overlay touches',
             'requiredEvidence': ['screenshot', 'video']} for host in ['chat', 'sheet']]
    (args.output / 'plan.json').write_text(json.dumps(plan, indent=2))
    with lease(args.udid, args.runtime) as udid:
        build = ['xcodebuild', '-project', str(ROOT / 'Examples/OverlayDemo.xcodeproj'), '-scheme', 'OverlayDemo',
                 '-configuration', 'Debug', '-sdk', 'iphonesimulator', '-destination', 'id=' + udid]
        if not args.skip_build:
            with (ROOT / '.artifacts/build.log').open('w') as log:
                subprocess.run([*build, 'build'], check=True, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        settings = json.loads(run(*build, '-showBuildSettings', '-json'))[0]['buildSettings']
        app = Path(settings['TARGET_BUILD_DIR']) / settings['FULL_PRODUCT_NAME']
        sim('install', udid, str(app))
        helper = ROOT / '.artifacts/software-keyboard'
        run('xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(ROOT / 'scripts/software-keyboard.m'), '-o', str(helper))
        run(str(helper), os.environ.get('DEVELOPER_DIR') or run('xcode-select', '-p').strip(), udid)
        (args.output / 'environment.json').write_text(json.dumps({
            'udid': udid, 'devices': json.loads(sim('list', 'devices', '--json')), 'xcode': run('xcodebuild', '-version'),
            'app': str(app), 'buildCommand': build, 'source': str(ROOT), 'testedAt': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        }, indent=2))
        previous = args.output / 'results.json'
        results = json.loads(previous.read_text()) if (args.host or args.appearance) and previous.exists() else []
        for appearance in ([args.appearance] if args.appearance else ['light', 'dark']):
            sim('ui', udid, 'appearance', appearance)
            for host in ([args.host] if args.host else ['chat', 'sheet']):
                results = [r for r in results if (r['host'], r['appearance']) != (host, appearance)]
                output = args.output / appearance / host
                ui = UI(udid, output)
                (output / 'run.mp4').unlink(missing_ok=True)
                (output / 'actions.jsonl').unlink(missing_ok=True)
                subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
                sim('launch', udid, BUNDLE, '-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-AppleKeyboards', '(en_US@sw=QWERTY)')
                record = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--codec=h264', str(output / 'run.mp4')], stderr=subprocess.PIPE, stdout=subprocess.DEVNULL)
                item = {'host': host, 'appearance': appearance, 'status': 'failed'}
                try:
                    end = time.monotonic() + 20
                    while time.monotonic() < end:
                        if select.select([record.stderr], [], [], .5)[0]:
                            line = record.stderr.readline()
                            if b'Recording started' in line:
                                break
                            if not line:
                                raise RuntimeError('Recorder exited before start')
                    else:
                        raise RuntimeError('Recorder did not start')
                    exercise(ui, host == 'sheet')
                    item['status'] = 'passed'
                except Exception as error:
                    item['error'] = str(error)
                    ui.capture('failure')
                    raise
                finally:
                    record.send_signal(signal.SIGINT)
                    record.wait(timeout=20)
                    record.stderr.close()
                    results.append(item)
                    (args.output / 'results.json').write_text(json.dumps(results, indent=2))
                    print(json.dumps(item), flush=True)


if __name__ == '__main__':
    main()
