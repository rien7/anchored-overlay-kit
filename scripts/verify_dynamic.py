"""Behavioral checks shared by the isolated Simulator runner."""
import time
import json


def exercise(ui, sheet):
    ui.element('demo-input')
    if sheet:
        ui.axe('tap', '--label', 'Sheet', '--tap-style', 'physical', '--post-delay', '.7')
        ui.prefix = 'sheet-'
    ui.tap('demo-input')
    ui.axe('type', 'dynamic draft')
    keyboard = ui.keyboard()
    input_frame = ui.element('demo-input')['frame']
    for adapter in ['UIKit', 'SwiftUI']:
        if adapter == 'UIKit':
            ui.tap('demo-dynamic-uikit')
        else:
            ui.axe('tap', '--label', 'Sheet dynamic SwiftUI' if sheet else 'Dynamic SwiftUI', '--tap-style', 'physical', '--post-delay', '.7')
        first = ui.element('dynamic-expand')['frame']
        last = ui.element('dynamic-close')['frame']
        initial_height = last['y'] + last['height'] - first['y']
        ui.capture(adapter + '-compact')
        ui.tap('dynamic-counter')
        assert '1' in ui.element('dynamic-counter')['AXLabel'], 'Counter action lost'
        ui.tap('dynamic-load')
        ui.element('dynamic-loaded')
        time.sleep(.7)
        first = ui.element('dynamic-expand')['frame']
        last = ui.element('dynamic-close')['frame']
        assert last['y'] + last['height'] - first['y'] > initial_height + 30, 'Content measurement did not grow container'
        ui.capture(adapter + '-loaded')
        ui.tap('dynamic-expand')
        time.sleep(.7)
        assert 'Back' in ui.element('dynamic-expand')['AXLabel']
        first = ui.element('dynamic-expand')['frame']
        last = ui.element('dynamic-close')['frame']
        assert 'Panel 378' in ui.element('demo-status').get('AXValue', ''), 'Container did not resolve the available width'
        assert last['y'] + last['height'] > keyboard['y'], 'Expanded panel did not overlap keyboard'
        assert '1' in ui.element('dynamic-counter')['AXLabel'], 'Expansion remounted state'
        ui.capture(adapter + '-expanded')
        row_before = None
        if adapter == 'SwiftUI':
            row = ui.element('dynamic-row-0')['frame']
            ui.axe('swipe', '--start-x', '180', '--start-y', str(row['y'] + 120), '--end-x', '180', '--end-y', str(row['y'] + 20), '--duration', '.35', '--post-delay', '.5')
            rows = [i for i in ui.state() if (i.get('AXUniqueId') or '').startswith('dynamic-row-') and i['frame']['y'] > row['y'] + 10]
            row_before = rows[0]
            # AXe's swipe can still be decelerating after its post-delay.
            # Compare settled offsets, not two samples of the same momentum.
            last_y = [None]
            stable_count = [0]
            def settled(items):
                item = next((i for i in items if i.get('AXUniqueId') == row_before['AXUniqueId']), None)
                if not item:
                    return None
                y = item['frame']['y']
                if last_y[0] is not None and abs(y - last_y[0]) < .25:
                    stable_count[0] += 1
                else:
                    stable_count[0] = 0
                last_y[0] = y
                return item if stable_count[0] >= 2 else None
            row_before = ui.wait(settled, 'Reference scroll did not settle')
            (ui.output / 'scroll-before.json').write_text(json.dumps(row_before, indent=2))
            ui.capture('SwiftUI-scrolled')
        ui.tap('dynamic-expand')
        time.sleep(.7)
        assert 'Expand' in ui.element('dynamic-expand')['AXLabel']
        assert '1' in ui.element('dynamic-counter')['AXLabel'], 'Return lost state'
        ui.capture(adapter + '-returned')
        if adapter == 'SwiftUI':
            ui.tap('dynamic-reverse')
            time.sleep(.8)
            assert 'Back' in ui.element('dynamic-expand')['AXLabel'], 'Interrupted transition ended on stale layout'
            assert '1' in ui.element('dynamic-counter')['AXLabel']
            row_after = ui.element(row_before['AXUniqueId'])
            (ui.output / 'scroll-after.json').write_text(json.dumps(row_after, indent=2))
            assert abs(row_after['frame']['y'] - row_before['frame']['y']) < 2, 'Scroll offset changed on return'
            ui.capture('SwiftUI-interrupted')
        ui.tap('dynamic-close')
        ui.wait(lambda items: not any((i.get('AXUniqueId') or '').startswith('dynamic-') for i in items), 'Dynamic overlay survived close')
        time.sleep(.7)
        assert ui.element('demo-input')['AXValue'] == 'dynamic draft', 'Dynamic action typed into draft'
        assert abs(ui.element('demo-input')['frame']['y'] - input_frame['y']) < 1, 'Resize moved composer'
    ui.axe('tap', '--label', 'x', '--element-type', 'Button', '--tap-style', 'physical', '--post-delay', '.4')
    assert ui.element('demo-input')['AXValue'] == 'dynamic draftx', 'Focus was not retained'
    ui.capture('dynamic-finished')
