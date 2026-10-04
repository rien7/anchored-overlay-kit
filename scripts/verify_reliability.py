"""Lifecycle outcomes and reactive retained SwiftUI content using real controls."""
import time


def exercise(ui, sheet):
    if sheet:
        ui.axe('tap', '--label', 'Sheet', '--tap-style', 'physical', '--post-delay', '.7')
        ui.prefix = 'sheet-'
    ui.tap('demo-input')
    ui.keyboard()
    ui.axe('type', 'reliable draft')
    assert ui.element('demo-input')['AXValue'] == 'reliable draft', 'Initial draft injection failed'
    ui.keyboard()
    ui.tap('demo-reliability')
    ui.wait(lambda items: any(i.get('AXLabel') == 'Lifecycle passed' for i in items), 'Lifecycle checks failed', timeout=60)
    ui.element('reliability-close')
    time.sleep(.8)
    initial = ui.element('reliability-close')['frame']['y'] - ui.element('reliability-count')['frame']['y']
    ui.capture('reactive-compact')
    ui.tap('reliability-count')
    ui.tap('reliability-load')
    ui.element('reliability-loaded')
    time.sleep(.8)
    expanded = ui.element('reliability-close')['frame']['y'] - ui.element('reliability-count')['frame']['y']
    assert expanded > initial + 50, 'SwiftUI page did not automatically grow'
    ui.capture('reactive-loaded')
    ui.tap('reliability-next')
    ui.capture('second-page')
    ui.tap('reliability-back')
    time.sleep(.8)
    assert ui.element('reliability-count')['AXLabel'] == 'Count 1', 'Retained state lost'
    assert abs(ui.element('reliability-close')['frame']['y'] - ui.element('reliability-count')['frame']['y'] - expanded) < 2
    ui.capture('reactive-returned')
    ui.tap('reliability-close')
    time.sleep(.8)
    ui.axe('tap', '--label', 'x', '--element-type', 'Button', '--tap-style', 'physical', '--post-delay', '.4')
    assert ui.element('demo-input')['AXValue'] == 'reliable draftx'
    ui.capture('lifecycle-finished')
