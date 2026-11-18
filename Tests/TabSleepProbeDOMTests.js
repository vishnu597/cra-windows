// Production JavaScript on a controlled DOM surface. The PC test proves renderer timing and real trusted input.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync('Packages/CraCore/Sources/CraCore/TabSleepProbe.swift', 'utf8');
function literal(name, optional = false) {
  const match = source.match(new RegExp('public static let ' + name + ' = """\\r?\\n([\\s\\S]*?)\\r?\\n    """'));
  if (!match && optional) return '';
  assert.ok(match, 'production ' + name + ' literal exists');
  // These static literals contain no Swift escapes or interpolation: dedenting is their exact Swift value.
  assert.ok(!match[1].includes('\\'), 'export escaped/interpolated Swift through Swift before testing it');
  return match[1].split(/\r?\n/).map(line => line.slice(4)).join('\n');
}
const install = literal('documentStartScript', true), probe = literal('script');
let checks = 0, failed = 0;
function expect(value, message) { assert.ok(value, message); checks++; }
function fixture({installRecorder = true, audio = true} = {}) {
  const listeners = new Map(), fields = [], media = [];
  class Element {
    constructor(properties = {}) {
      Object.assign(this, {tagName: 'INPUT', type: 'text', name: '', form: null, value: '', defaultValue: '', isConnected: true,
        isContentEditable: false, textContent: '', checked: false, defaultChecked: false}, properties);
    }
    closest() { return this.editableRoot ?? this; }
    getRootNode() { return document; }
  }
  class AudioContext {
    constructor(options = {}) { this.state = options.state ?? 'running'; this.listeners = []; }
    addEventListener(type, callback) { if (type === 'statechange') this.listeners.push(callback); }
    setState(state) { this.state = state; this.listeners.forEach(callback => callback()); }
  }
  const document = {querySelectorAll(selector) {
    if (selector === 'input, textarea, select') return fields;
    if (selector === 'input[type="radio"]') return fields.filter(field => field.type === 'radio');
    if (selector === 'audio, video') return media;
    throw new Error('Unexpected selector ' + selector);
  }};
  const sandbox = {document, Element, location: {href: 'https://fixture.test/form'},
    addEventListener(type, callback) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(callback);
    }};
  if (audio) Object.assign(sandbox, {AudioContext, webkitAudioContext: AudioContext});
  sandbox.window = sandbox;
  const context = vm.createContext(sandbox);
  if (installRecorder) vm.runInContext(install, context);
  return {sandbox, context, fields, media, Element,
    input(element, trusted = true, path = [element]) {
      for (const callback of listeners.get('input') ?? []) callback({isTrusted: trusted, target: element, composedPath: () => path});
    },
    ask() { return vm.runInContext(probe, context); },
    reinstall() { return vm.runInContext(install, context); }};
}
const tests = [];
function test(name, run, regression = false) { tests.push({name, run, regression}); }

test('controlled input keeps user text even when the framework updates defaultValue', () => {
  const f = fixture(), field = new f.Element({value: 'unfinished search', defaultValue: 'unfinished search'});
  f.fields.push(field);
  f.input(field);
  expect(f.ask() === 'typed', 'trusted text survives a controlled input matching its current default');
}, true);

test('a running Web Audio context keeps the page awake without an audio element', () => {
  const f = fixture();
  new f.sandbox.AudioContext();
  expect(f.media.length === 0 && f.ask() === 'sound', 'Web Audio is protected without an HTMLMediaElement');
}, true);

test('untrusted programmatic input does not manufacture a user edit', () => {
  const f = fixture(), field = new f.Element({value: 'framework value', defaultValue: 'framework value'});
  f.fields.push(field);
  f.input(field, false);
  expect(f.ask() === '', 'only a trusted input event records the field');
});

test('clearing or removing the edited field releases the hold', () => {
  const f = fixture(), field = new f.Element({value: 'draft', defaultValue: 'draft'});
  f.fields.push(field);
  f.input(field);
  field.value = '';
  f.input(field);
  expect(f.ask() === '', 'a cleared field holds no user text');
  field.value = field.defaultValue = 'more draft';
  f.input(field);
  field.isConnected = false;
  expect(f.ask() === '', 'a removed field no longer holds the page');
});

test('same-document SPA address changes retain user edits while a fresh document resets them', () => {
  const f = fixture(), field = new f.Element({value: 'draft', defaultValue: 'draft'});
  f.fields.push(field);
  f.input(field);
  f.sandbox.location.href = 'https://fixture.test/form?step=2';
  expect(f.ask() === 'typed', 'changing a SPA route cannot discard text still on the page');
  expect(fixture().ask() === '', 'a fresh document has no edits from its predecessor');
});

test('trusted editable content and an open shadow-root field are protected', () => {
  const f = fixture(), editable = new f.Element({tagName: 'DIV', isContentEditable: true, textContent: 'draft'});
  const child = new f.Element({tagName: 'SPAN', isContentEditable: true, editableRoot: editable});
  f.input(child);
  expect(f.ask() === 'typed', 'input inside an editable child tracks its editable root');
  editable.textContent = '   ';
  expect(f.ask() === '', 'empty editable content releases the hold');
  const shadowField = new f.Element({value: 'shadow draft', defaultValue: 'shadow draft'});
  f.input(new f.Element({tagName: 'CUSTOM-ELEMENT'}), true, [shadowField]);
  expect(f.ask() === 'typed', 'composedPath finds a field inside an open shadow root');
});

test('checkboxes and selections release after returning to their original choice', () => {
  const f = fixture(), checkbox = new f.Element({type: 'checkbox', checked: true});
  f.input(checkbox);
  expect(f.ask() === 'typed', 'a changed checkbox is protected');
  checkbox.checked = false;
  const select = new f.Element({tagName: 'SELECT', options: [{selected: true, defaultSelected: false}]});
  f.input(select);
  expect(f.ask() === 'typed', 'a changed selection is protected');
  select.options[0].selected = false;
  expect(f.ask() === '', 'the original choices release the hold');
});

test('controlled checkboxes and radios retain their original choice before framework defaults change', () => {
  for (const type of ['checkbox', 'radio']) {
    const f = fixture(), field = new f.Element({type, checked: true, defaultChecked: false});
    f.fields.push(field);
    f.input(field);
    field.defaultChecked = field.checked;
    expect(f.ask() === 'typed', 'a framework changing defaultChecked cannot hide the trusted ' + type + ' change');
    field.checked = false;
    f.input(field);
    field.defaultChecked = field.checked;
    expect(f.ask() === '', 'returning to the original ' + type + ' choice releases the hold');
  }
}, true);

test('a controlled selection retains original choices before framework defaults change', () => {
  const f = fixture(), first = {selected: false, defaultSelected: true}, second = {selected: true, defaultSelected: false};
  const field = new f.Element({tagName: 'SELECT', options: [first, second]});
  f.fields.push(field);
  f.input(field);
  for (const option of field.options) option.defaultSelected = option.selected;
  expect(f.ask() === 'typed', 'a framework changing defaultSelected cannot hide a trusted selection');
  first.selected = true;
  second.selected = false;
  f.input(field);
  for (const option of field.options) option.defaultSelected = option.selected;
  expect(f.ask() === '', 'returning to the original selection releases the hold');
}, true);

test('returning to the original controlled radio-group choice releases both radios', () => {
  const f = fixture(), first = new f.Element({type: 'radio', name: 'choice', checked: true, defaultChecked: true});
  const second = new f.Element({type: 'radio', name: 'choice'});
  const other = new f.Element({type: 'radio', name: 'other', checked: false, defaultChecked: true});
  f.fields.push(first, second);
  // A same-form group in this document only: another group must not become a recorded user edit.
  const query = f.sandbox.document.querySelectorAll;
  f.sandbox.document.querySelectorAll = selector => selector === 'input[type="radio"]' ? [first, second, other] : query(selector);
  first.checked = false;
  second.checked = true;
  f.input(second);
  for (const field of [first, second]) field.defaultChecked = field.checked;
  expect(f.ask() === 'typed', 'switching to another radio retains the group edit');
  first.checked = true;
  second.checked = false;
  f.input(first);
  for (const field of [first, second]) field.defaultChecked = field.checked;
  expect(f.ask() === '', 'returning the group to its initial choice releases both original baselines');
}, true);

test('suspended and closed realtime contexts release the sound hold', () => {
  const f = fixture(), audio = new f.sandbox.AudioContext();
  audio.setState('suspended');
  expect(f.ask() === '', 'suspended Web Audio no longer holds');
  audio.setState('running');
  expect(f.ask() === 'sound', 'resumed Web Audio holds again');
  audio.setState('closed');
  expect(f.ask() === '', 'closed Web Audio no longer holds');
  const prefixed = new f.sandbox.webkitAudioContext();
  expect(f.ask() === 'sound', 'a supported prefixed constructor is tracked too');
  prefixed.setState('closed');
  expect(f.ask() === '', 'closing the prefixed context releases the hold');
});

test('wrapping constructors preserves prototype, subclassing and repeated installation', () => {
  const f = fixture(), Constructor = f.sandbox.AudioContext;
  class Derived extends Constructor {}
  const context = new Derived();
  expect(context instanceof Constructor && context instanceof Derived, 'native construction and subclass prototypes survive');
  f.reinstall();
  expect(f.sandbox.AudioContext === Constructor && f.ask() === 'sound', 'installing again preserves contexts and constructor identity');
});

test('ordinary fields, HTML media and beforeunload retain their existing protection', () => {
  const f = fixture({audio: false}), field = new f.Element({value: 'plain draft'});
  f.fields.push(field);
  expect(f.ask() === 'typed', 'current/default fallback protects a plain field');
  field.value = '';
  f.media.push({paused: false, ended: false, muted: false, volume: 0.5});
  expect(f.ask() === 'sound', 'a playing media element is protected');
  f.media[0].muted = true;
  f.sandbox.onbeforeunload = () => {};
  expect(f.ask() === 'beforeunload', 'a page asking before close remains protected');
  f.sandbox.onbeforeunload = null;
  expect(f.ask() === '', 'a quiet page without edits can sleep');
});

test('a missing recorder keeps the page instead of silently losing unobserved state', () => {
  expect(fixture({installRecorder: false}).ask() === 'no recorder', 'document-start installation failure refuses sleep');
});

for (const {name, run, regression} of tests) {
  if (process.argv.includes('--regressions') && !regression) continue;
  try { run(); console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.message); }
}
console.log(`${checks} checks, ${failed} failing tests`);
if (failed) process.exitCode = 1;
