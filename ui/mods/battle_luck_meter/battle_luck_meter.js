// Squirrel owns every value; JS presents the bar, optional readouts and exact final battle summary.
// ES3 for the game's Chromium 48.
(function () {
    'use strict';

    var views = 0;

    function build(container) {
        var root = $('<div class="battle-luck-meter-luck"/>').css('display', 'none');
        var track = $('<div class="battle-luck-meter-track"/>').appendTo(root);
        $('<div class="battle-luck-meter-centre"/>').appendTo(track);
        var marker = $('<div class="battle-luck-meter-marker"/>').appendTo(track);
        var readouts = $('<div class="battle-luck-meter-readouts title-font-small font-bold font-bottom-shadow font-color-title"/>').css('display', 'none').appendTo(root);
        var you = $('<div class="battle-luck-meter-readout"/>').appendTo(readouts);
        $('<span class="battle-luck-meter-side-name"/>').text('You ').appendTo(you);
        var ours = $('<span class="battle-luck-meter-percent"/>').appendTo(you);
        var enemy = $('<div class="battle-luck-meter-readout"/>').appendTo(readouts);
        $('<span class="battle-luck-meter-side-name"/>').text('Enemy ').appendTo(enemy);
        var theirs = $('<span class="battle-luck-meter-percent"/>').appendTo(enemy);
        root.appendTo(container);
        try { root.bindTooltip({contentType: 'msu-generic', modId: 'mod_battle_luck_meter', elementId: 'Luck'}); }
        catch (error) { root.remove(); throw error; }
        return {root: root, track: track, marker: marker, readouts: readouts,
            oursPercent: ours, theirsPercent: theirs, id: ++views, last: null};
    }

    function renderPercent(element, percent, tone) {
        element.text(percent).toggleClass('battle-luck-meter-good', tone === 'good').toggleClass('battle-luck-meter-bad', tone === 'bad');
    }

    function render(view, data) {
        if (!view || !data) return;
        var showPercentages = data.enabled && data.show_percentages;
        view.root.css('display', data.enabled ? '' : 'none');
        view.root.toggleClass('battle-luck-meter-show-percentages', showPercentages);
        view.readouts.css('display', showPercentages ? '' : 'none');
        view.marker.css('left', data.marker + '%');
        view.track.css('opacity', data.emphasis);
        renderPercent(view.oursPercent, data.ours_percent, data.ours_tone);
        renderPercent(view.theirsPercent, data.theirs_percent, data.theirs_tone);
    }

    var uiSequence = 0;
    function report(data) {
        try {
            var line = '[BattleLuckMeterUI] schema=3 ui_seq=' + (++uiSequence) + ' battle=' + data.origin_battle + ' event=ui';
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
            SQ.call(connection.mSQHandle, 'battleLuckMeterLog', line);
        } catch (error) { console.error('Battle Luck Meter UI report failed: ' + error); }
    }

    function receipt(module, data, status) {
        var view = module.battleLuckMeterView;
        var info = {origin_battle: data.battle, push: data.push, view: view ? view.id : 0, status: status, surface: data.surface};
        if (view && status === 'rendered') {
            info.emphasis = view.track.get(0).style.opacity;
            // The inline style is the pushed target, not the position the CSS transition
            // is currently interpolating through, so the receipt stays exact.
            info.left = view.marker.get(0).style.left;
            info.display = view.root.get(0).style.display;
            info.badges = view.readouts.get(0).style.display === 'none' ? 'hidden' : 'rendered';
            if (info.badges === 'rendered') {
                info.ours_percent = view.oursPercent.text();
                info.theirs_percent = view.theirsPercent.text();
                info.ours_tone = view.oursPercent.hasClass('battle-luck-meter-good') ? 'good' : view.oursPercent.hasClass('battle-luck-meter-bad') ? 'bad' : 'neutral';
                info.theirs_tone = view.theirsPercent.hasClass('battle-luck-meter-good') ? 'good' : view.theirsPercent.hasClass('battle-luck-meter-bad') ? 'bad' : 'neutral';
            }
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
            try { this.battleLuckMeterView = build(this.mContainer); }
            catch (error) { console.error('Battle Luck Meter create failed: ' + error); }
        };

        proto.destroyDIV = function () {
            var view = this.battleLuckMeterView;
            try {
                dispose(view);
                if (view && view.last) receipt(this, view.last, 'destroyed');
            }
            catch (error) { console.error('Battle Luck Meter cleanup failed: ' + error); }
            this.battleLuckMeterView = null;
            return destroyDIV.call(this);
        };

        proto.battleLuckMeterUpdate = function (data) {
            if (!data) return;
            if (!this.battleLuckMeterView) { receipt(this, data, 'missing_view'); return; }
            if (this.battleLuckMeterLastPush && data.push <= this.battleLuckMeterLastPush) { receipt(this, data, 'stale'); return; }
            try {
                render(this.battleLuckMeterView, data);
                this.battleLuckMeterLastPush = data.push;
                this.battleLuckMeterView.last = data;
                receipt(this, data, 'rendered');
            } catch (error) {
                report({origin_battle: data.battle, push: data.push, view: this.battleLuckMeterView.id, status: 'error', detail: String(error)});
                console.error('Battle Luck Meter render failed: ' + error);
            }
        };
    }

    if (typeof TacticalCombatResultScreen === 'undefined' ||
        typeof TacticalCombatResultScreenStatisticsPanel === 'undefined') return;

    function clearResult(panel) {
        try {
            var view = panel.battleLuckMeterView;
            dispose(view);
            if (view && view.last) receipt(panel, view.last, 'destroyed');
        }
        catch (error) { console.error('Battle Luck Meter result cleanup failed: ' + error); }
        panel.battleLuckMeterView = null;
        try {
            if (panel.mStatisticsContainer && panel.mStatisticsContainer.hasClass('battle-luck-meter-results-list')) {
                panel.mStatisticsContainer.removeClass('battle-luck-meter-results-list').removeClass('battle-luck-meter-results-overflow');
                panel.mListContainer.trigger('update', true);
            }
        } catch (error) { console.error('Battle Luck Meter result layout cleanup failed: ' + error); }
    }

    function refreshResults(panel) {
        if (!panel.battleLuckMeterView || !panel.mStatisticsContainer || !panel.mListContainer) return;
        // Vanilla removes the middle-card gaps for large parties to leave room
        // for its scrollbar. The summary can also make a twelve-brother list scroll.
        panel.mStatisticsContainer.toggleClass('battle-luck-meter-results-overflow',
            panel.mStatisticsContainer.outerHeight() > panel.mListContainer.height());
        panel.mListContainer.trigger('update', true);
    }

    function appendResult(panel) {
        var data = panel.battleLuckMeterData;
        panel.mStatisticsContainer.toggleClass('battle-luck-meter-results-list', !!data && data.enabled);
        panel.mStatisticsContainer.toggleClass('battle-luck-meter-results-overflow', false);
        if (!data || !data.enabled) {
            if (data) receipt(panel, data, 'suppressed');
            panel.mListContainer.trigger('update', true);
            return;
        }
        var view = build(panel.mStatisticsContainer);
        panel.battleLuckMeterView = view;
        view.root.addClass('battle-luck-meter-result-luck');
        view.readouts.removeClass('title-font-small').addClass('title-font-normal');
        view.verdict = $('<div class="battle-luck-meter-result-verdict text-font-normal font-bold font-color-title"/>')
            .text(data.text).prependTo(view.root);
        $('<div class="battle-luck-meter-result-title title-font-normal font-bold font-bottom-shadow font-color-subtitle"/>')
            .text('Battle luck').prependTo(view.root);
        var sides = $('<div class="battle-luck-meter-result-sides text-font-normal font-color-description"/>').appendTo(view.root);
        view.ours = $('<div class="battle-luck-meter-result-side"/>').text(data.ours).appendTo(sides);
        view.theirs = $('<div class="battle-luck-meter-result-side"/>').text(data.theirs).appendTo(sides);
        var context = $('<div class="battle-luck-meter-result-context text-font-normal font-color-description"/>').appendTo(view.root);
        view.swing = $('<div class="battle-luck-meter-result-swing"/>').text(data.swing).appendTo(context);
        view.sample = $('<div class="battle-luck-meter-result-sample"/>').text(data.sample).appendTo(context);
        render(view, data);
        view.last = data;
        receipt(panel, data, 'rendered');
        refreshResults(panel);
    }

    var screenProto = TacticalCombatResultScreen.prototype;
    var showResults = screenProto.show, resultsShown = screenProto.notifyBackendOnShown;
    screenProto.show = function (data) {
        // Set before native show synchronously loads the statistics datasource.
        this.mStatisticsPanel.battleLuckMeterData = data && data.battleLuckMeterLuck ? data.battleLuckMeterLuck : null;
        return showResults.call(this, data);
    };
    screenProto.notifyBackendOnShown = function () {
        try { refreshResults(this.mStatisticsPanel); }
        catch (error) { console.error('Battle Luck Meter result scroll failed: ' + error); }
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
            console.error('Battle Luck Meter result create failed: ' + error);
        }
        return result;
    };
    panelProto.destroyDIV = function () {
        clearResult(this);
        this.battleLuckMeterData = null;
        return destroyStatistics.call(this);
    };
}());
