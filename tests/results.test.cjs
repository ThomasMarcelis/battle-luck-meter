const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');

// Presentation double: native callbacks replace the list and return their own values.
class Element {
    constructor() { this.children = []; this.classes = new Set(); this.style = {}; this.events = []; }
    appendTo(parent) { this.parent = parent; parent.children.push(this); return this; }
    prependTo(parent) { this.parent = parent; parent.children.unshift(this); return this; }
    remove() { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); this.parent = null; return this; }
    empty() { for (const child of this.children) child.parent = null; this.children = []; return this; }
    addClass(value) { this.classes.add(value); return this; }
    removeClass(value) { this.classes.delete(value); return this; }
    toggleClass(value, on) { return on ? this.addClass(value) : this.removeClass(value); }
    css(key, value) { this.style[key] = value; return this; }
    text(value) { if (arguments.length === 0) return this.content; this.content = value; return this; }
    get() { return this; }
    hasClass(value) { return this.classes.has(value); }
    bindTooltip(data) { this.tooltip = data; return this; }
    unbindTooltip() { this.tooltip = null; return this; }
    trigger(name) { this.events.push(name); return this; }
    outerHeight() { return 700; }
    height() { return 578; }
}

function session() {
    const errors = [], calls = [], receipts = [];
    function Panel() { this.createDIV(); }
    Panel.prototype.createDIV = function () { this.mStatisticsContainer = new Element(); this.mListContainer = new Element(); };
    Panel.prototype.addStatistics = function (data) {
        calls.push(data);
        this.mStatisticsContainer.empty();
        for (const bro of data) { const card = new Element().appendTo(this.mStatisticsContainer); card.bro = bro; }
        return 'populated';
    };
    Panel.prototype.destroyDIV = function () { this.mStatisticsContainer.empty(); this.mStatisticsContainer = null; return 'destroyed'; };
    function Screen() { this.mStatisticsPanel = new Panel(); }
    Screen.prototype.show = function (data) { this.mStatisticsPanel.addStatistics(data.statistics); return 'shown'; };
    Screen.prototype.notifyBackendOnShown = function () { return 'native notification'; };
    const context = vm.createContext({TacticalCombatResultScreen: Screen, TacticalCombatResultScreenStatisticsPanel: Panel,
        $: () => new Element(), Screens: {MSUConnection: {mSQHandle: 'msu-session', isConnected: () => true}},
        SQ: {call: (handle, method, line) => {
            assert.equal(handle, 'msu-session'); assert.equal(method, 'xbroLog'); receipts.push(line);
        }}, console: {log: () => { throw new Error('console output is not persisted'); }, error: error => errors.push(error)}});
    vm.runInContext(readFileSync(require.resolve('../ui/mods/xbro/xbro.js'), 'utf8'), context);
    const screen = new Screen();
    return {screen, panel: screen.mStatisticsPanel, errors, calls, receipts};
}

const luck = {battle: 1, push: 1, surface: 'results', enabled: true, marker: 89.5, emphasis: 1, ours_percent: '+50%', theirs_percent: '-25%', ours_tone: 'good', theirs_tone: 'good',
    text: 'Top 11% of outcomes at these odds', swing: 'Net hit swing: 3.00 hits in your favour.', sample: 'Counted attacks: 16.', ours: 'You: 6 hits vs 4.00 expected', theirs: 'Enemy: 3 hits vs 4.00 expected'};

test('six, twelve and sixteen brothers retain native data across result reloads', () => {
    const s = session();
    for (const count of [6, 12, 16]) {
        const statistics = Array.from({length: count}, (_, id) => Object.freeze({id}));
        assert.equal(s.screen.show({statistics, xbroLuck: luck}), 'shown');
        assert.equal(s.calls.at(-1), statistics);
        const view = s.panel.xbroView;
        assert.equal(view.readouts, undefined);
        assert.equal(view.oursPercent, undefined);
        assert.equal(view.theirsPercent, undefined);
        assert.equal(view.verdict.content, luck.text);
        assert.equal(view.swing.content, luck.swing);
        assert.equal(view.sample.content, luck.sample);
        assert.equal(view.marker.style.left, '89.5%');
        assert.equal(view.root.style.display, '');
        assert.match(s.receipts.at(-1), /status="rendered"/);
        assert.ok(s.receipts.at(-1).includes('text="'+encodeURIComponent(luck.text)+'"'));
        assert.ok(s.receipts.at(-1).includes('swing="'+encodeURIComponent(luck.swing)+'"'));
        assert.ok(s.receipts.at(-1).includes('sample="'+encodeURIComponent(luck.sample)+'"'));
        assert.ok(s.receipts.at(-1).includes('ours="'+encodeURIComponent(luck.ours)+'"'));
        assert.ok(s.receipts.at(-1).includes('theirs="'+encodeURIComponent(luck.theirs)+'"'));
        assert.equal(view.ours.content, luck.ours);
        assert.equal(view.theirs.content, luck.theirs);
        assert.equal(s.screen.notifyBackendOnShown(), 'native notification');
        assert.equal(s.panel.mListContainer.events.at(-1), 'update');
        assert.equal(s.panel.addStatistics(statistics), 'populated');
        assert.equal(view.root.tooltip, null);
        assert.equal(view.root.parent, null);
        assert.notEqual(s.panel.xbroView, view);
        assert.equal(s.panel.xbroView.readouts, undefined);
    }
    assert.deepEqual(s.errors, []);
});

test('percentage payload changes never create result badges; disabled and absent results still clear', () => {
    const s = session();
    for (const percent of ['+100%', '—', '0%', '-100%']) {
        s.screen.show({statistics: [], xbroLuck: {...luck, marker: 45.5, emphasis: 0.55, ours_percent: percent}});
        assert.equal(s.panel.xbroView.readouts, undefined);
        assert.equal(s.panel.xbroView.marker.style.left, '45.5%');
    }
    s.screen.show({statistics: [], xbroLuck: {...luck, text: 'No attacks recorded', ours_percent: '—', theirs_percent: '—', swing: '', sample: ''}});
    assert.equal(s.panel.xbroView.verdict.content, 'No attacks recorded');
    assert.equal(s.panel.xbroView.swing.content, '');
    assert.equal(s.panel.xbroView.sample.content, '');
    const old = s.panel.xbroView;
    s.screen.show({statistics: [], xbroLuck: {...luck, enabled: false}});
    assert.equal(s.panel.xbroView, null);
    assert.equal(old.root.parent, null);
    s.screen.show({statistics: [], xbroLuck: luck});
    s.screen.show({statistics: []});
    assert.equal(s.panel.xbroView, null);
    assert.equal(s.panel.xbroData, null);
    assert.deepEqual(s.errors, []);
});

test('disconnect cleans the tooltip and cached result; late callbacks cannot recreate it', () => {
    const s = session();
    s.screen.show({statistics: [], xbroLuck: luck});
    const view = s.panel.xbroView;
    assert.equal(s.panel.destroyDIV(), 'destroyed');
    assert.equal(view.root.tooltip, null);
    assert.equal(view.root.parent, null);
    assert.match(s.receipts.at(-1), /status="destroyed"/);
    assert.equal(s.panel.xbroData, null);
    const calls = s.calls.length;
    s.panel.addStatistics([{id: 'late'}]);
    assert.equal(s.calls.length, calls);
    assert.equal(s.panel.xbroView, null);
    assert.equal(s.screen.notifyBackendOnShown(), 'native notification');
    s.panel.createDIV();
    s.screen.show({statistics: [{id: 'next battle'}]});
    assert.equal(s.panel.xbroView, null);
    assert.deepEqual(s.errors, []);
});

test('tooltip cleanup failure cannot suppress list replacement or native destruction', () => {
    const s = session();
    s.screen.show({statistics: [], xbroLuck: luck});
    const old = s.panel.xbroView;
    old.root.unbindTooltip = () => { throw new Error('tooltip unavailable'); };
    assert.equal(s.panel.addStatistics([{id: 1}]), 'populated');
    assert.equal(old.root.parent, null);
    s.panel.xbroView.root.unbindTooltip = old.root.unbindTooltip;
    assert.equal(s.panel.destroyDIV(), 'destroyed');
    assert.equal(s.errors.length, 2);
});

test('failed summary creation restores native list layout and refreshes scrolling', () => {
    const s = session(), nativeClasses = [...s.panel.mStatisticsContainer.classes];
    s.screen.show({statistics: [], xbroLuck: luck});
    const bindTooltip = Element.prototype.bindTooltip;
    Element.prototype.bindTooltip = () => { throw new Error('tooltip unavailable'); };
    try {
        const statistics = [{id: 1}, {id: 2}];
        assert.equal(s.screen.show({statistics, xbroLuck: luck}), 'shown');
        assert.equal(s.calls.at(-1), statistics);
        assert.equal(s.panel.xbroView, null);
        assert.deepEqual([...s.panel.mStatisticsContainer.classes], nativeClasses);
        assert.equal(s.panel.mListContainer.events.at(-1), 'update');
        assert.equal(s.errors.length, 1);
        assert.match(s.errors[0], /result create failed/);
    } finally { Element.prototype.bindTooltip = bindTooltip; }
});
