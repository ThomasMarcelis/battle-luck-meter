// Squirrel owns every readout; JS presents the live meter and final battle summary.
// ES3 for the game's Chromium 48.
(function () {
    'use strict';

    var views = 0;

    function build(container) {
        var root = $('<div class="xbro-luck"/>').css('display', 'none');
        var track = $('<div class="xbro-track"/>').appendTo(root);
        $('<div class="xbro-centre"/>').appendTo(track);
        var marker = $('<div class="xbro-marker"/>').appendTo(track);
        root.appendTo(container);
        try { root.bindTooltip({contentType: 'msu-generic', modId: 'mod_xbro', elementId: 'Luck'}); }
        catch (error) { root.remove(); throw error; }
        return {root: root, track: track, marker: marker, id: ++views, last: null};
    }

    function render(view, data) {
        if (!view || !data) return;
        view.root.css('display', data.enabled ? '' : 'none');
        view.marker.css('left', data.marker + '%');
        view.track.css('opacity', data.emphasis);
    }

    var uiSequence = 0;
    function report(data) {
        try {
            var line = '[xBroUI] schema=3 ui_seq=' + (++uiSequence) + ' battle=' + data.origin_battle + ' event=ui';
            var key, value;
            for (key in data) if (data.hasOwnProperty(key)) {
                value = data[key];
                line += ' ' + key + '=' + (typeof value === 'boolean' ? (value ? '1' : '0') :
                    typeof value === 'number' ? String(value) : '"' + encodeURIComponent(String(value)) + '"');
            }
            // The battle/results handle may already be disconnected during teardown.
            // MSU's session connection forwards receipts to Squirrel's logInfo.
            var connection = Screens.MSUConnection;
            if (!connection || !connection.isConnected()) throw new Error('MSU journal connection unavailable');
            SQ.call(connection.mSQHandle, 'xbroLog', line);
        } catch (error) { console.error('xBro UI report failed: ' + error); }
    }

    function receipt(module, data, status) {
        var view = module.xbroView;
        var info = {origin_battle: data.battle, push: data.push, view: view ? view.id : 0, status: status, surface: data.surface};
        if (view && status === 'rendered') {
            info.emphasis = view.track.get(0).style.opacity;
            info.left = view.marker.get(0).style.left;
            info.display = view.root.get(0).style.display;
            if (view.ours && view.theirs) {
                info.text = view.verdict.text();
                info.swing = view.swing.text(); info.sample = view.sample.text();
                info.ours = view.ours.text(); info.theirs = view.theirs.text();
            }
        }
        report(info);
    }

    function dispose(view) {
        if (!view) return;
        try { view.root.trigger('hide-tooltip').unbindTooltip(); }
        finally { view.root.remove(); }
    }

    if (typeof TacticalScreenTopbarRoundInformationModule !== 'undefined') {
        var proto = TacticalScreenTopbarRoundInformationModule.prototype;
        var createDIV = proto.createDIV, destroyDIV = proto.destroyDIV;

        proto.createDIV = function (parent) {
            createDIV.call(this, parent);
            try { this.xbroView = build(this.mContainer); }
            catch (error) { console.error('xBro create failed: ' + error); }
        };

        proto.destroyDIV = function () {
            var view = this.xbroView;
            try {
                dispose(view);
                if (view && view.last) receipt(this, view.last, 'destroyed');
            }
            catch (error) { console.error('xBro cleanup failed: ' + error); }
            this.xbroView = null;
            return destroyDIV.call(this);
        };

        proto.xbroUpdate = function (data) {
            if (!data) return;
            if (!this.xbroView) { receipt(this, data, 'missing_view'); return; }
            if (this.xbroLastPush && data.push <= this.xbroLastPush) { receipt(this, data, 'stale'); return; }
            try {
                render(this.xbroView, data);
                this.xbroLastPush = data.push;
                this.xbroView.last = data;
                receipt(this, data, 'rendered');
            } catch (error) {
                report({origin_battle: data.battle, push: data.push, view: this.xbroView.id, status: 'error', detail: String(error)});
                console.error('xBro render failed: ' + error);
            }
        };
    }

    if (typeof TacticalCombatResultScreen === 'undefined' ||
        typeof TacticalCombatResultScreenStatisticsPanel === 'undefined') return;

    function clearResult(panel) {
        try {
            var view = panel.xbroView;
            dispose(view);
            if (view && view.last) receipt(panel, view.last, 'destroyed');
        }
        catch (error) { console.error('xBro result cleanup failed: ' + error); }
        panel.xbroView = null;
        try {
            if (panel.mStatisticsContainer && panel.mStatisticsContainer.hasClass('xbro-results-list')) {
                panel.mStatisticsContainer.removeClass('xbro-results-list').removeClass('xbro-results-overflow');
                panel.mListContainer.trigger('update', true);
            }
        } catch (error) { console.error('xBro result layout cleanup failed: ' + error); }
    }

    function refreshResults(panel) {
        if (!panel.xbroView || !panel.mStatisticsContainer || !panel.mListContainer) return;
        // Vanilla removes the middle-card gaps for large parties to leave room
        // for its scrollbar. The summary can also make a twelve-brother list scroll.
        panel.mStatisticsContainer.toggleClass('xbro-results-overflow',
            panel.mStatisticsContainer.outerHeight() > panel.mListContainer.height());
        panel.mListContainer.trigger('update', true);
    }

    function appendResult(panel) {
        var data = panel.xbroData;
        panel.mStatisticsContainer.toggleClass('xbro-results-list', !!data && data.enabled);
        panel.mStatisticsContainer.toggleClass('xbro-results-overflow', false);
        if (!data || !data.enabled) {
            if (data) receipt(panel, data, 'suppressed');
            panel.mListContainer.trigger('update', true);
            return;
        }
        var view = build(panel.mStatisticsContainer);
        panel.xbroView = view;
        view.root.addClass('xbro-result-luck');
        view.verdict = $('<div class="xbro-result-verdict text-font-normal font-bold font-color-title"/>')
            .text(data.text).prependTo(view.root);
        $('<div class="xbro-result-title title-font-normal font-bold font-bottom-shadow font-color-subtitle"/>')
            .text('Battle luck').prependTo(view.root);
        var sides = $('<div class="xbro-result-sides text-font-normal font-color-description"/>').appendTo(view.root);
        view.ours = $('<div class="xbro-result-side"/>').text(data.ours).appendTo(sides);
        view.theirs = $('<div class="xbro-result-side"/>').text(data.theirs).appendTo(sides);
        var context = $('<div class="xbro-result-context text-font-normal font-color-description"/>').appendTo(view.root);
        view.swing = $('<div class="xbro-result-swing"/>').text(data.swing).appendTo(context);
        view.sample = $('<div class="xbro-result-sample"/>').text(data.sample).appendTo(context);
        render(view, data);
        view.last = data;
        receipt(panel, data, 'rendered');
        refreshResults(panel);
    }

    var screenProto = TacticalCombatResultScreen.prototype;
    var showResults = screenProto.show, resultsShown = screenProto.notifyBackendOnShown;
    screenProto.show = function (data) {
        // Set before native show synchronously loads the statistics datasource.
        this.mStatisticsPanel.xbroData = data && data.xbroLuck ? data.xbroLuck : null;
        return showResults.call(this, data);
    };
    screenProto.notifyBackendOnShown = function () {
        try { refreshResults(this.mStatisticsPanel); }
        catch (error) { console.error('xBro result scroll failed: ' + error); }
        return resultsShown.call(this);
    };

    var panelProto = TacticalCombatResultScreenStatisticsPanel.prototype;
    var addStatistics = panelProto.addStatistics, destroyStatistics = panelProto.destroyDIV;
    panelProto.addStatistics = function (data) {
        if (!this.mStatisticsContainer) return; // A datasource callback after disconnection.
        clearResult(this);
        var result = addStatistics.call(this, data);
        try { appendResult(this); }
        catch (error) {
            clearResult(this);
            console.error('xBro result create failed: ' + error);
        }
        return result;
    };
    panelProto.destroyDIV = function () {
        clearResult(this);
        this.xbroData = null;
        return destroyStatistics.call(this);
    };
}());
