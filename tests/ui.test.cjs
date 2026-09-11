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
    toggleClass(name, on) { on ? this.classes.add(name) : this.classes.delete(name); return this; }
    text(value) { this.content = value; return this; }
    bindTooltip(data) { this.tooltip = data; return this; }
    unbindTooltip() { this.tooltip = null; return this; }
    trigger(name) { this.events.push(name); return this; }
    remove() { if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1); this.parent = null; return this; }
}

function session() {
    const errors = [];
    function Module() { this.mContainer = null; }
    Module.prototype.createDIV = function (parent) { this.mContainer = new Node('<div class="topbar-round-information-module"/>').appendTo(parent); };
    Module.prototype.destroyDIV = function () { this.mContainer.remove(); this.mContainer = null; };
    const context = vm.createContext({TacticalScreenTopbarRoundInformationModule: Module, $: markup => new Node(markup),
        console: {error: message => errors.push(message)}, Math});
    vm.runInContext(readFileSync(require.resolve('../ui/mods/xbro/xbro.js'), 'utf8'), context);
    const module = new Module(), parent = new Node('<div class="middle-module-container"/>');
    module.createDIV(parent);
    return {module, parent, errors, root: () => module.mContainer.children[0]};
}

test('create adds one tooltip-bound bar in the pending state inside the native container', () => {
    const s = session(), root = s.root();
    assert.equal(s.module.mContainer.children.length, 1);
    assert.ok(root.classes.has('xbro-pending'));
    assert.equal(root.style.display, 'none', 'hidden until Squirrel pushes');
    assert.deepEqual({...root.tooltip}, {contentType: 'msu-generic', modId: 'mod_xbro', elementId: 'Luck'});
    assert.deepEqual(s.errors, []);
});

test('update renders offset, text, pending and enabled exactly as pushed', () => {
    const s = session(), root = s.root(), marker = root.children[0].children[0], label = root.children[1];
    s.module.xbroUpdate({enabled: true, pending: false, offset: 0.6, text: 'Lucky 93%'});
    assert.equal(marker.style.left, '20%');
    assert.equal(label.content, 'Lucky 93%');
    assert.ok(!root.classes.has('xbro-pending'));
    assert.equal(root.style.display, '');
    s.module.xbroUpdate({enabled: true, pending: false, offset: -0.6, text: 'Unlucky 93%'});
    assert.equal(marker.style.left, '80%');
    s.module.xbroUpdate({enabled: false, pending: true, offset: 0, text: ''});
    assert.equal(root.style.display, 'none');
    assert.ok(root.classes.has('xbro-pending'));
    assert.equal(label.content, '');
    s.module.xbroUpdate({enabled: true, pending: false, offset: 1, text: 'Lucky 99%'});
    assert.equal(marker.style.left, '0%');
    s.module.xbroUpdate(null);
    assert.equal(marker.style.left, '0%', 'null push is ignored');
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
    s.module.xbroUpdate({enabled: true, pending: false, offset: 0.5, text: 'late'});
    assert.deepEqual(s.errors, []);
    const t = session();
    t.root().unbindTooltip = () => { throw new Error('tooltip gone'); };
    assert.doesNotThrow(() => t.module.destroyDIV());
    assert.equal(t.module.mContainer, null);
    assert.equal(t.errors.length, 1);
    assert.match(t.errors[0], /tooltip gone/);
});
