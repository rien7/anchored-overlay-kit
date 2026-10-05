"""Real touches: expanding recent photos, retained selection/scroll and focus."""
import time
from verify import ROOT, run


def exercise(ui, sheet):
    ui.element('demo-input')
    if sheet:
        ui.axe('tap', '--label', 'Sheet', '--tap-style', 'physical', '--post-delay', '.7')
        ui.prefix = 'sheet-'
    ui.tap('demo-input')
    ui.keyboard()
    ui.axe('type', 'photos draft')
    assert ui.element('demo-input')['AXValue'] == 'photos draft', 'Initial draft injection failed'
    keyboard = ui.keyboard()
    composer = ui.element('demo-input')['frame']
    ui.tap('demo-plus')
    menu_top = ui.element('menu-Files')['frame']['y']
    ui.capture('menu')
    ui.tap('menu-Recent Photos')
    time.sleep(.7)
    top = ui.element('photos-grid')['frame']['y']
    assert abs(top - menu_top) < 2, 'Expansion moved the menu top'
    grid = ui.element('photos-grid')['frame']
    assert grid['y'] + grid['height'] > keyboard['y'] + 100, 'Grid does not cover keyboard'
    controls = [ui.element(name)['frame'] for name in ['photos-back', 'photos-done']]
    for control in controls:
        assert control['width'] >= 44 and control['height'] >= 44
        assert control['y'] > grid['y'] + grid['height'] / 2, 'Controls are not at the bottom'
        assert control['y'] + control['height'] < grid['y'] + grid['height'] - 12, 'Controls touch bottom edge'
    assert ui.element('photos-done')['AXLabel'] == 'All Photos'
    ui.tap('photo-0')
    ui.capture('photos-boundary-selected')
    helper = ROOT / '.artifacts/boundary-pixels'
    run('xcrun', '--sdk', 'macosx', 'swiftc', str(ROOT / 'scripts/verify-boundary-pixels.swift'), '-o', str(helper))
    screen = next(item['frame'] for item in ui.state() if item.get('type') == 'Application')
    result = run(str(helper), str(ui.output / 'photos-boundary-selected.png'),
                 str(grid['x']), str(grid['y']), str(screen['width']))
    (ui.output / 'boundary-pixels.txt').write_text(result)
    ui.tap('photo-1')
    assert ui.element('photo-1')['AXValue'] == 'Selected 2'
    ui.tap('photo-0')
    assert ui.element('photo-1')['AXValue'] == 'Selected 1', 'Selection order not compacted'
    assert '1 selected' in ui.element('photos-done')['AXValue']
    ui.capture('photos-selected')
    ui.axe('swipe', '--start-x', str(grid['x'] + 120), '--start-y', str(grid['y'] + grid['height'] - 25),
           '--end-x', str(grid['x'] + 120), '--end-y', str(grid['y'] + 30), '--duration', '.4', '--post-delay', '1')
    time.sleep(1)
    # Reusable grids expose visible cells, not every offscreen photo. Track a
    # fully visible item to prove both scrolling and retained page position.
    visible = [item for item in ui.state()
               if (item.get('AXUniqueId') or '').startswith('photo-')
               and item['frame']['y'] >= grid['y']
               and item['frame']['y'] + item['frame']['height'] <= grid['y'] + grid['height']]
    retained = min(visible, key=lambda item: int(item['AXUniqueId'].split('-')[-1]))
    assert int(retained['AXUniqueId'].split('-')[-1]) >= 3, 'Photo grid did not scroll'
    retained_id = retained['AXUniqueId']
    before = retained['frame']['y']
    ui.capture('photos-scrolled')
    ui.tap('photos-back')
    ui.capture('returned')
    ui.tap('menu-Recent Photos')
    time.sleep(.7)
    assert '1 selected' in ui.element('photos-done')['AXValue'], 'Selection lost on return'
    assert abs(ui.element(retained_id)['frame']['y'] - before) < 2, 'Photo scroll offset lost'
    ui.capture('photos-restored')
    ui.tap('photos-back')
    ui.tap('menu-Recent Photos')
    time.sleep(.8)
    assert '1 selected' in ui.element('photos-done')['AXValue'], 'Repeated navigation remounted page'
    ui.capture('photos-reopened')
    ui.axe('swipe', '--start-x', str(grid['x'] + 120), '--start-y', str(grid['y'] + 30),
           '--end-x', str(grid['x'] + 120), '--end-y', str(grid['y'] + grid['height'] - 80),
           '--duration', '.25', '--post-delay', '1')
    assert ui.element('photo-1')['AXValue'] == 'Selected 1', 'Reused cell lost its selection'
    ui.tap('photo-1')
    assert ui.element('photos-done')['AXLabel'] == 'All Photos', 'Reused cell did not deselect'
    ui.tap('photo-1')
    assert ui.element('photo-1')['AXValue'] == 'Selected 1'
    ui.capture('photos-reused')
    ui.tap('photos-done')
    time.sleep(.8)
    assert ui.element('demo-input')['AXValue'] == 'photos draft'
    assert abs(ui.element('demo-input')['frame']['y'] - composer['y']) < 1
    ui.axe('tap', '--label', 'x', '--element-type', 'Button', '--tap-style', 'physical', '--post-delay', '.4')
    assert ui.element('demo-input')['AXValue'] == 'photos draftx', 'Keyboard focus lost'
    ui.capture('finished')
