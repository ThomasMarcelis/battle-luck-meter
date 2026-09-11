// xBro luck meter: a bar under the round counter. Squirrel pushes {enabled, pending, offset, text};
// this file only renders it. ES3 for the game's Chromium 48.
(function () {
    'use strict';
    if (typeof TacticalScreenTopbarRoundInformationModule === 'undefined') return;

    function build(container) {
        var root = $('<div class="xbro-luck xbro-pending"/>').css('display', 'none');
        var track = $('<div class="xbro-track"/>').appendTo(root);
        var marker = $('<div class="xbro-marker"/>').appendTo(track);
        var label = $('<div class="xbro-label title-font-small font-bold font-bottom-shadow font-color-title"/>').appendTo(root);
        root.appendTo(container);
        root.bindTooltip({contentType: 'msu-generic', modId: 'mod_xbro', elementId: 'Luck'});
        return {root: root, marker: marker, label: label};
    }

    function render(view, data) {
        if (!view || !data) return;
        view.root.css('display', data.enabled ? '' : 'none');
        view.root.toggleClass('xbro-pending', data.pending);
        // Lucky is positive and moves the marker left, onto the green end.
        view.marker.css('left', (50 - data.offset * 50) + '%');
        view.label.text(data.text);
    }

    function dispose(view) {
        if (!view) return;
        view.root.trigger('hide-tooltip').unbindTooltip();
        view.root.remove();
    }

    var proto = TacticalScreenTopbarRoundInformationModule.prototype;
    var createDIV = proto.createDIV, destroyDIV = proto.destroyDIV;

    proto.createDIV = function (parent) {
        createDIV.call(this, parent);
        try { this.xbroView = build(this.mContainer); }
        catch (error) { console.error('xBro create failed: ' + error); }
    };

    proto.destroyDIV = function () {
        try { dispose(this.xbroView); }
        catch (error) { console.error('xBro cleanup failed: ' + error); }
        this.xbroView = null;
        return destroyDIV.call(this);
    };

    proto.xbroUpdate = function (data) {
        render(this.xbroView, data);
    };
}());
