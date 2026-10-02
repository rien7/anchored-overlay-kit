"""Geometry and material checks against the rendered native panel."""
import json
import time


def geometry(ui):
    return json.loads(ui.element('dynamic-geometry')['AXValue'])


def assert_edge(ui, inset=12, glass=True, capped=False):
    data = geometry(ui)
    assert abs(data['windowHeight'] - data['y'] - data['height'] - inset) < .5, data
    if capped:
        assert abs(data['width'] - 300) < .5, data
        assert abs(data['bottomLeft'] - 24) < .5, data
    else:
        assert abs(data['x'] - inset) < .5, data
        assert abs(data['windowWidth'] - data['width'] - 2 * inset) < .5, data
        assert data['windowRadius'] > inset, data
        for name in ['bottomLeft', 'bottomRight']:
            assert abs(data[name] - (data['windowRadius'] - inset)) < .5, data
    assert abs(data['top'] - 24) < .5, data
    assert data['glass'] == int(glass), data
    close = ui.element('dynamic-close')['frame']
    assert close['y'] + close['height'] <= data['windowHeight'] - data['safeBottom'] + .5, 'Close intersects home indicator'
    return data


def exercise(ui, sheet):
    ui.element('demo-input')
    if sheet:
        ui.axe('tap', '--label', 'Sheet', '--tap-style', 'physical', '--post-delay', '.7')
        ui.prefix = 'sheet-'
    ui.tap('demo-input')
    ui.axe('type', 'glass draft')
    ui.keyboard()
    observations = []
    for adapter in ['UIKit', 'SwiftUI']:
        if adapter == 'UIKit':
            ui.tap('demo-dynamic-uikit')
        else:
            ui.axe('tap', '--label', 'Sheet dynamic SwiftUI' if sheet else 'Dynamic SwiftUI', '--tap-style', 'physical', '--post-delay', '.7')
        ui.tap('dynamic-counter')
        ui.tap('dynamic-expand')
        time.sleep(.8)
        for name, inset, glass, capped in [('regular', 12, True, False), ('clear', 12, True, False), ('material', 12, False, False), ('inset20', 20, True, False), ('capped', 12, True, True), ('regular-returned', 12, True, False)]:
            observations.append(dict(adapter=adapter, state=name, geometry=assert_edge(ui, inset, glass, capped)))
            assert '1' in ui.element('dynamic-counter')['AXLabel'], 'Material update remounted content'
            ui.capture(adapter + '-' + name)
            if name != 'regular-returned':
                ui.tap('dynamic-material')
                time.sleep(.7)
        if adapter == 'UIKit':
            data = geometry(ui)
            ui.axe('tap', '-x', str(data['x'] + 1), '-y', str(data['y'] + 1), '--tap-style', 'physical', '--post-delay', '.7')
            ui.wait(lambda items: not any(i.get('AXUniqueId') == 'dynamic-close' for i in items), 'Rounded corner did not dismiss through backdrop')
        else:
            ui.tap('dynamic-close')
        time.sleep(.7)
    ui.tap('demo-fallback')
    keyboard = ui.keyboard()
    ui.tap('demo-dynamic-uikit')
    ui.tap('dynamic-expand')
    time.sleep(.8)
    data = geometry(ui)
    assert data['y'] + data['height'] <= keyboard['y'] - 7, data
    assert abs(data['bottomLeft'] - 24) < .5 and abs(data['bottomRight'] - 24) < .5, data
    observations.append(dict(adapter='UIKit', state='above-keyboard', geometry=data))
    ui.capture('above-keyboard')
    ui.tap('dynamic-close')
    ui.tap('demo-fallback')
    ui.axe('tap', '--label', 'x' , '--element-type', 'Button', '--tap-style', 'physical', '--post-delay', '.4')
    assert ui.element('demo-input')['AXValue'] == 'glass draftx'
    ui.capture('glass-finished')
    (ui.output / 'geometry.json').write_text(json.dumps(observations, indent=2))
