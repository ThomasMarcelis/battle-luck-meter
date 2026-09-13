const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');

// Minimal jQuery double covering exactly what xbro.js touches.
class Node {
    constructor(markup) {
        const match = /class="([^"]*)"/.exec(markup || '');
        this.classes = new Set(match ? match[1].split(' ') : []);
        this.children = []; this.parent = null; this.style = {}; this.content = ''; this.tooltip = null; this.events = [];
    }
    appendTo(parent) { parent.children.push(this); this.parent = parent; return this; }
    css(key, value) { this.style[key] = value; return this; }
    get() { return this; }
    hasClass(name) { return this.classes.has(name); }
    toggleClass(name, on) { on ? this.classes.add(name) : this.classes.delete(name); return this; }
    text(value) { if (arguments.length === 0) return this.content; this.content = value; return this; }
    bindTooltip(data) { this.tooltip = data; return this; }
    unbindTooltip() { this.tooltip = null; return this; }
    trigger(name) { this.events.push(name); return this; }
    remove() { if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1); this.parent = null; return this; }
}

function session() {
    const errors = [], receipts = [];
    const connection = {mSQHandle: 'msu-session', isConnected() { return this.mSQHandle !== null; }};
    function Module() { this.mContainer = null; this.mSQHandle = "topbar"; }
    Module.prototype.createDIV = function (parent) { this.mContainer = new Node('<div class="topbar-round-information-module"/>').appendTo(parent); };
    Module.prototype.destroyDIV = function () { this.mContainer.remove(); this.mContainer = null; };
    const context = vm.createContext({TacticalScreenTopbarRoundInformationModule: Module, $: markup => new Node(markup),
        Screens: {MSUConnection: connection}, SQ: {call: (handle, method, message) => {
            assert.equal(handle, 'msu-session');
            assert.equal(method, 'xbroLog');
            const data = {};
            for (const match of message.matchAll(/([a-z_]+)=("[^"]*"|\S+)/g)) {
                const value = match[2];
                data[match[1]] = value[0] === '"' ? decodeURIComponent(value.slice(1,-1)) : Number(value);
            }
            receipts.push(data);
        }}, console: {log: () => { throw new Error('console output is not persisted'); }, error: message => errors.push(message)}, Math});
    vm.runInContext(readFileSync(require.resolve('../ui/mods/xbro/xbro.js'), 'utf8'), context);
    const module = new Module(), parent = new Node('<div class="middle-module-container"/>');
    module.createDIV(parent);
    const update = module.xbroUpdate;
    let pushes = 0;
    module.xbroUpdate = data => update.call(module, data ? {battle: 1, push: ++pushes, surface: 'battle', ...data} : data);
    return {module, parent, errors, receipts, connection, root: () => module.mContainer.children[0]};
}

test('create binds a tooltip and stays hidden until a push', () => {
    const s = session(), root = s.root();
    assert.equal(s.module.mContainer.children.length, 1);
    assert.equal(root.style.display, 'none', 'hidden until Squirrel pushes');
    assert.deepEqual({...root.tooltip}, {contentType: 'msu-generic', modId: 'mod_xbro', elementId: 'Luck'});
    assert.deepEqual(s.errors, []);
});

const initial = {enabled: true, marker: 50, emphasis: 0.5, ours_percent: '—', theirs_percent: '—', ours_tone: 'neutral', theirs_tone: 'neutral'};

test('renders only the luck marker and ignores volatile percentage payloads', () => {
    const s = session(), view = s.module.xbroView;
    s.module.xbroUpdate(initial);
    assert.equal(view.readouts, undefined);
    assert.equal(view.oursPercent, undefined);
    assert.equal(view.theirsPercent, undefined);
    assert.equal(view.root.children.length, 1, 'only the track is visible');
    assert.equal(view.marker.style.left, '50%');
    s.module.xbroUpdate({...initial, marker: 45.5, emphasis: 0.55, ours_percent: '-100%', ours_tone: 'bad'});
    assert.equal(view.marker.style.left, '45.5%');
    assert.equal(view.track.style.opacity, 0.55);
    assert.equal(view.root.style.display, '');
    s.module.xbroUpdate({...initial, marker: 100, emphasis: 1, ours_percent: '+1900%', ours_tone: 'good', theirs_percent: '+10%', theirs_tone: 'bad'});
    assert.equal(view.marker.style.left, '100%');
    assert.equal(view.track.style.opacity, 1);
    s.module.xbroUpdate({...initial, enabled: false, marker: 0, ours_percent: '0%'});
    assert.equal(view.marker.style.left, '0%');
    assert.equal(view.root.style.display, 'none');
    s.module.xbroUpdate(null);
    assert.equal(view.marker.style.left, '0%', 'null push is ignored');
    assert.deepEqual(s.errors, []);
});

test('destroy unbinds the tooltip, removes the bar, and native teardown always runs', () => {
    const s = session(), root = s.root();
    s.module.destroyDIV();
    assert.equal(root.tooltip, null);
    assert.deepEqual(root.events, ['hide-tooltip']);
    assert.equal(root.parent, null);
    assert.equal(s.module.mContainer, null);
    assert.equal(s.module.xbroView, null);
    s.module.xbroUpdate(initial);
    assert.deepEqual(s.errors, []);
    const t = session();
    t.root().unbindTooltip = () => { throw new Error('tooltip gone'); };
    assert.doesNotThrow(() => t.module.destroyDIV());
    assert.equal(t.module.mContainer, null);
    assert.equal(t.errors.length, 1);
    assert.match(t.errors[0], /tooltip gone/);
});


test('reports actual rendered fields and destroy, rejects stale or late updates', () => {
    const s = session();
    s.module.xbroUpdate({...initial, battle: 2, push: 10, marker: 55, emphasis: 0.6, ours_percent: '+100%', ours_tone: 'good'});
    const receipt = s.receipts.at(-1);
    assert.deepEqual(receipt, {schema: 3, ui_seq: 1, battle: 2, event: NaN, origin_battle: 2, push: 10, view: 1, status: 'rendered', surface: 'battle',
        emphasis: 0.6, left: '55%', display: ''});
    s.module.xbroUpdate({...initial, battle: 1, push: 9, enabled: false});
    assert.equal(s.receipts.at(-1).status, 'stale');
    assert.equal(s.module.xbroView.marker.style.left, '55%');
    s.module.mSQHandle = null; // The native screen disconnects first.
    s.module.destroyDIV();
    assert.equal(s.receipts.at(-1).status, 'destroyed');
    s.module.xbroUpdate({...initial, battle: 2, push: 11});
    assert.equal(s.receipts.at(-1).status, 'missing_view');
    assert.deepEqual(s.errors, []);
    s.connection.mSQHandle = null;
    assert.doesNotThrow(() => s.module.xbroUpdate({...initial, battle: 2, push: 12}));
    assert.equal(s.receipts.at(-1).push, 11, 'disconnected journal does not fabricate a receipt');
    assert.match(s.errors.at(-1), /journal connection unavailable/);
});
