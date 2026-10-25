// node test/model.test.js
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')

const source = fs.readFileSync(path.join(__dirname, '..', 'StartMenuModel.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
const model = {}
vm.runInNewContext(source + '\nObject.assign(model, { uniqueIds, parsePins, serializePins, pin, unpin, movePin, parseRecent, addRecent, forgetRecent, ago, letterFor, letters, alphabet, placement, gridStep })', { model })

let passed = 0
function test(name, fn) {
  fn()
  passed++
  console.log('ok - ' + name)
}
// Values made in another context fail deepStrictEqual on their prototypes.
const same = (actual, expected) => assert.deepStrictEqual(JSON.parse(JSON.stringify(actual)), expected)

test('pins keep each desktop id once, without .desktop', () => {
  same(model.uniqueIds(['foot', 'chromium.desktop', 'foot', ' ', null]), ['foot', 'chromium'])
})

test('no saved pins reads as none rather than empty', () => {
  assert.strictEqual(model.parsePins(''), null)
  assert.strictEqual(model.parsePins('{"other": 1}'), null)
  same(model.parsePins('{"pinned": []}'), [])
  same(model.parsePins(model.serializePins(['a', 'b.desktop'])), ['a', 'b'])
})

test('pinning adds at the end once, unpinning removes', () => {
  same(model.pin(['a', 'b'], 'c.desktop'), ['a', 'b', 'c'])
  same(model.pin(['a', 'b'], 'a'), ['a', 'b'])
  same(model.unpin(['a', 'b', 'c'], 'b'), ['a', 'c'])
})

test('a pin moves to the slot it is dropped in', () => {
  same(model.movePin(['a', 'b', 'c', 'd'], 'd', 0), ['d', 'a', 'b', 'c'])
  same(model.movePin(['a', 'b', 'c', 'd'], 'a', 2), ['b', 'c', 'a', 'd'])
  same(model.movePin(['a', 'b'], 'a', 99), ['b', 'a'])
})

test('recent apps put the latest first, once each, up to the limit', () => {
  let recent = []
  for (let i = 0; i < 15; i++) recent = model.addRecent(recent, 'app' + i, i)
  assert.strictEqual(recent.length, 12)
  assert.strictEqual(recent[0].id, 'app14')
  recent = model.addRecent(recent, 'app10', 99)
  same(recent.slice(0, 2).map(r => r.id), ['app10', 'app14'])
  assert.strictEqual(recent.filter(r => r.id === 'app10').length, 1)
  same(model.forgetRecent(recent, 'app10').map(r => r.id).indexOf('app10'), -1)
})

test('a damaged recent file reads as what it can', () => {
  same(model.parseRecent('not json'), [])
  same(model.parseRecent('[{"id":"a","at":5},{"id":"a","at":4},{"at":3},{"id":"b","at":"x"},{"id":"c.desktop","at":2}]'), [{ id: 'a', at: 5 }, { id: 'c', at: 2 }])
})

test('times read the way the start menu says them', () => {
  const now = 1e12
  assert.strictEqual(model.ago(now - 10e3, now), 'Just now')
  assert.strictEqual(model.ago(now - 5 * 60e3, now), '5 min ago')
  assert.strictEqual(model.ago(now - 3600e3, now), '1 hour ago')
  assert.strictEqual(model.ago(now - 30 * 3600e3, now), 'Yesterday')
  assert.strictEqual(model.ago(now - 3 * 86400e3, now), '3 days ago')
  assert.strictEqual(model.ago(now - 20 * 86400e3, now), '2 weeks ago')
})

test('apps are filed under their first letter, digits and symbols under #', () => {
  assert.strictEqual(model.letterFor('firefox'), 'F')
  assert.strictEqual(model.letterFor('7-Zip'), '#')
  assert.strictEqual(model.letterFor(''), '#')
  same(model.letters(['1Password', 'Alacritty', 'akregator', 'Btop']), ['#', 'A', 'B'])
  assert.strictEqual(model.alphabet().length, 27)
})

const screen = { width: 2560, height: 1440, reserved: [0, 30, 0, 0] }

test('the menu hangs from the apps button, inward of the dock', () => {
  const dock = { x: 800, y: 1300, width: 900, height: 60 }
  const button = { x: 800, y: 1300, width: 60, height: 60 }
  same(model.placement({ position: 'bottom', dock, button }, screen, 600, 700, 6, 10, 50), { x: 800, y: 594 })
  same(model.placement({ position: 'top', dock: { x: 800, y: 30, width: 900, height: 60 }, button: { x: 800, y: 30, width: 60, height: 60 } }, screen, 600, 700, 6, 10, 50), { x: 800, y: 96 })
  same(model.placement({ position: 'left', dock: { x: 0, y: 300, width: 60, height: 800 }, button: { x: 0, y: 300, width: 60, height: 60 } }, screen, 600, 700, 6, 10, 50), { x: 66, y: 300 })
  same(model.placement({ position: 'right', dock: { x: 2500, y: 300, width: 60, height: 800 }, button: { x: 2500, y: 900, width: 60, height: 60 } }, screen, 600, 700, 6, 10, 50), { x: 1894, y: 730 })
})

test('the menu stays clear of the bar and the screen edges', () => {
  const dock = { x: 2200, y: 1300, width: 300, height: 60 }
  same(model.placement({ position: 'bottom', dock, button: { x: 2200, y: 1300, width: 60, height: 60 } }, screen, 600, 700, 6, 10, 50), { x: 1950, y: 594 })
  same(model.placement({ position: 'bottom', dock, button: { x: 2200, y: 1300, width: 60, height: 60 } }, screen, 600, 1400, 6, 10, 50).y, 40)
})

test('without the dock place the menu centers along its edge, or at the bottom', () => {
  same(model.placement({ position: 'bottom' }, screen, 600, 700, 6, 10, 50), { x: 980, y: 684 })
  same(model.placement({ position: 'left' }, screen, 600, 700, 6, 10, 50), { x: 56, y: 385 })
  same(model.placement({ screen: 'DP-1' }, screen, 600, 700, 6, 10, 50), { x: 980, y: 730 })
  same(model.placement({}, { width: 500, height: 400 }, 600, 700, 6, 10, 50), { x: 10, y: 10 })
})

test('arrows move through a grid and leave it at its top and bottom', () => {
  same(model.gridStep(0, 10, 4, 'left'), { index: 0, leave: 0 })
  same(model.gridStep(1, 10, 4, 'down'), { index: 5, leave: 0 })
  same(model.gridStep(6, 10, 4, 'down'), { index: 9, leave: 0 })
  same(model.gridStep(9, 10, 4, 'down'), { index: 9, leave: 1 })
  same(model.gridStep(2, 10, 4, 'up'), { index: 2, leave: -1 })
  same(model.gridStep(5, 10, 4, 'up'), { index: 1, leave: 0 })
  same(model.gridStep(0, 0, 4, 'down'), { index: -1, leave: 0 })
})

console.log(`${passed} passed`)
