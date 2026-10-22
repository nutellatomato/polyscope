import QtQuick 2.4
import QtQuick.Controls 2.3
import QtQuick.Controls.Material 2.3
import QtQuick.Window 2.2

Item {
    id: scopeView
    width: 1280
    height: 620

    property string effect: "scope1"
    property string scopeBuild: "v3f-t1"   // shown in SETUP so the running build is verifiable
    property string uiPage: "main"        // "main" | "setup" | "channel" | "fullscreen" | "tuner"
    property int activeChannel: 0          // 0..3, channel shown on the channel page
    property bool autoTrigger: false       // auto-track the trigger threshold to the SYNC'd channel midpoint
    function applyAutoTrigger() {
        if (!autoTrigger || freeze) {
            return
        }
        var ch = Math.max(0, Math.min(3, triggerSource - 1))
        var tr = rawTraces[ch]
        if (!tr || tr.length === 0) {
            return
        }
        var mid = (minValue(tr) + maxValue(tr)) * 0.5
        knobs.ui_knob_change(effect, "trigger_level", Math.max(-1.0, Math.min(1.0, mid)))
    }
    function openPage(p) { uiPage = p }
    function openChannel(ch) { activeChannel = ch; uiPage = "channel" }
    function backToMain() { showCursors = false; uiPage = "main" }
    function stepTimebase(delta) {
        setIntControl("timebase", Math.max(0, Math.min(timebaseLabels.length - 1, timebaseIndex + delta)))
    }
    function stepVoltsDiv(delta) {
        setIntControl("volts_div", Math.max(0, Math.min(voltsDivLabels.length - 1, voltsDivIndex + delta)))
    }
    property bool hasEffect: !!currentEffects[effect] && !!currentEffects[effect]["controls"]
    property string notifyBroadcastEffect: ""
    property bool freeze: boolControlValue("freeze", false)
    property int timebaseIndex: boundedIntControlValue("timebase", 4, 0, timebaseLabels.length - 1)
    property int voltsDivIndex: boundedIntControlValue("volts_div", 2, 0, voltsDivLabels.length - 1)
    property int triggerSource: boundedIntControlValue("trigger_source", 1, 1, 4)
    property int triggerMode: boundedIntControlValue("trigger_mode", 0, 0, triggerModeLabels.length - 1)
    property real triggerLevel: controlValue("trigger_level", 0.0)
    property int viewMode: boundedIntControlValue("view_mode", 0, 0, viewModeLabels.length - 1)
    property int persistenceIndex: boundedIntControlValue("persistence", 0, 0, persistenceLabels.length - 1)
    property int intensityIndex: boundedIntControlValue("intensity", 2, 0, intensityLabels.length - 1)
    property int coupling1: boundedIntControlValue("coupling_1", 0, 0, couplingLabels.length - 1)
    property int coupling2: boundedIntControlValue("coupling_2", 0, 0, couplingLabels.length - 1)
    property int coupling3: boundedIntControlValue("coupling_3", 0, 0, couplingLabels.length - 1)
    property int coupling4: boundedIntControlValue("coupling_4", 0, 0, couplingLabels.length - 1)
    property bool visible1: boolControlValue("visible_1", true)
    property bool visible2: boolControlValue("visible_2", true)
    property bool visible3: boolControlValue("visible_3", true)
    property bool visible4: boolControlValue("visible_4", true)
    property int focusChannel: 0
    property bool showEnvelope: true
    property bool showCursors: false
    property int selectedCursor: 0
    property real cursorTimeA: 0.18
    property real cursorTimeB: 0.68
    property real cursorVoltA: 0.35
    property real cursorVoltB: -0.25
    property var rawTraces: [[], [], [], []]
    property var frameHistory: []
    property var processedTraces: [[], [], [], []]
    property var processedHistory: []
    property var traceStats: [
        {"peak": 0.0, "minimum": 0.0, "maximum": 0.0, "pp": 0.0, "mean": 0.0, "rms": 0.0, "frequency": 0.0},
        {"peak": 0.0, "minimum": 0.0, "maximum": 0.0, "pp": 0.0, "mean": 0.0, "rms": 0.0, "frequency": 0.0},
        {"peak": 0.0, "minimum": 0.0, "maximum": 0.0, "pp": 0.0, "mean": 0.0, "rms": 0.0, "frequency": 0.0},
        {"peak": 0.0, "minimum": 0.0, "maximum": 0.0, "pp": 0.0, "mean": 0.0, "rms": 0.0, "frequency": 0.0}
    ]
    property var holdMarkers: [null, null, null, null]
    property var envelopeCache: [null, null, null, null]
    property var channelColors: ["#28E1B3", "#FFD166", "#FF6B6B", "#6FB6FF"]
    property var dimChannelColors: ["#1B6B59", "#8E7236", "#8A4545", "#436B8A"]
    property var channelLabels: ["CH1", "CH2", "CH3", "CH4"]
    property var timebaseLabels: ["0.5 ms/div", "1 ms/div", "2 ms/div", "5 ms/div", "10 ms/div", "20 ms/div", "50 ms/div", "100 ms/div"]
    property var timebaseMsValues: [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]
    property var voltsDivLabels: ["0.5 V/div", "1 V/div", "2 V/div", "5 V/div", "10 V/div"]
    property var triggerModeLabels: ["AUTO", "RISE", "FALL", "ROLL"]
    property var viewModeLabels: ["STACK", "OVERLAY", "XY 1-2", "XY 3-4"]
    property var persistenceLabels: ["OFF", "LOW", "MED", "HIGH", "MAX"]
    property var persistenceDepths: [1, 2, 3, 4, 6]
    property var intensityLabels: ["DIM", "SOFT", "MED", "HOT", "MAX"]
    property var intensityAlphas: [0.28, 0.42, 0.58, 0.76, 1.0]
    property var couplingLabels: ["DC", "AC"]
    property var displayGains: [3.2, 2.0, 1.0, 0.45, 0.22]
    property bool hasFrame: rawTraces[0].length > 0 || rawTraces[1].length > 0 || rawTraces[2].length > 0 || rawTraces[3].length > 0
    property bool isXYView: viewMode >= 2
    property real xyCorrelation: 0.0       // refreshed with traceStats (XY header readout)
    // v2 packets: per-bucket min/max envelope (honest under-sampling display)
    // and plugin-measured alias-free frequencies. Null/zero on v1 packets.
    property var hfMin: [null, null, null, null]
    property var hfMax: [null, null, null, null]
    property var pluginFreqs: [0.0, 0.0, 0.0, 0.0]

    // ── Tuner ──────────────────────────────────────────────────────
    // Reads the plugin-measured frequency (sub-sample, alias-free) straight
    // from each packet, so it updates at the frame rate rather than on the
    // slower stats beat. The reference pitch lives only in the UI (no plugin
    // port), so it resets to 440 Hz when the scope is reloaded.
    property int tunerChannel: 0
    property real tunerA4: 440.0
    property real tunerInTuneCents: 3.0
    property var tunerNoteNames: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    function tunerValid(hz) { return hz >= 16.0 && hz <= 8000.0 }
    // fractional MIDI note number (A4 = 69)
    function tunerMidi(hz) { return 69.0 + 12.0 * Math.log(hz / tunerA4) / Math.LN2 }
    function tunerCents(hz) {
        if (!tunerValid(hz)) {
            return 0.0
        }
        var m = tunerMidi(hz)
        return (m - Math.round(m)) * 100.0
    }
    function tunerNoteName(hz) {
        if (!tunerValid(hz)) {
            return "—"
        }
        var n = Math.round(tunerMidi(hz))
        return tunerNoteNames[((n % 12) + 12) % 12] + (Math.floor(n / 12) - 1)
    }
    function tunerTargetHz(hz) {
        return tunerA4 * Math.pow(2.0, (Math.round(tunerMidi(hz)) - 69) / 12.0)
    }
    function formatCents(c) { return (c >= 0.05 ? "+" : (c <= -0.05 ? "−" : "±")) + Math.abs(c).toFixed(1) + " ¢" }
    function stepTunerA4(delta) { tunerA4 = Math.max(400.0, Math.min(480.0, tunerA4 + delta)) }
    property bool hfDetail: true           // SETUP toggle: draw the envelope
    property var hfSignificant: [false, false, false, false]
    property var holdoffValues: [0, 1, 2, 5, 10, 20, 50, 100, 200, 500]
    property var holdoffLabels: ["OFF", "1", "2", "5", "10", "20", "50", "100", "200", "500"]
    property real holdoffMs: controlValue("holdoff", 0.0)
    property int holdoffIndex: nearestHoldoffIndex(holdoffMs)
    // perf6 tried running gc() on the stats beat to spread collection cost;
    // on-device logs showed a full QV4 collection costs ~250 ms HERE, and it
    // ran every frame — collapsing the UI to ~4 fps (proc_ms 236-266 in the
    // perf6 log). Default OFF; the perf5 stutter was the screen-grab, whose
    // removal stands.
    property bool gcOnStatsBeat: false

    function nearestHoldoffIndex(ms) {
        var best = 0
        var bestDistance = 1e9
        for (var index = 0; index < holdoffValues.length; ++index) {
            var distance = Math.abs(holdoffValues[index] - ms)
            if (distance < bestDistance) {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    function shiftTrace(trace, delta) {
        // Float32Array: one heap object + unboxed storage, vs a JS array
        // whose slots feed the QV4 GC churn this build is eliminating.
        var output = new Float32Array(trace.length)
        for (var index = 0; index < trace.length; ++index) {
            output[index] = trace[index] + delta
        }
        return output
    }

    // Render on a fixed beat instead of on every frame arrival: setFrames() and
    // control changes call requestRender() (sets the flag); the Timer does the
    // single real repaint at ~25 FPS only when something changed. This caps
    // redraw cost and prevents a frame backlog from building up.
    //
    // perf4: the display is layered. gridCanvas holds everything static
    // (background, graticule, rulers) and repaints only on control/layout
    // changes; chart holds only the per-frame content (traces, envelope,
    // markers, cursors) over a transparent clear. Numeric readouts are QML
    // Text elements fed from traceStats, which updates on its own slower
    // beat (statsIntervalMs) — like a bench scope's measurement refresh.
    property bool _paintDirty: false
    property bool _gridDirty: false
    property int statsIntervalMs: 200      // numeric readout / envelope refresh beat
    property double _lastStatsAtMs: 0
    // Escape hatch: if the threaded canvas misbehaves on a device Qt build,
    // set false to fall back to the perf2 single-thread paint path.
    property bool threadedTracePaint: true
    function requestRender() { _paintDirty = true }
    // Persistence-ghost vertex decimation: the newest trace (historyIndex 0)
    // always strokes at full resolution; faded ghosts stroke every 2nd
    // vertex, deep ghosts every 3rd. On MED persistence this removes ~a
    // third of the stroked segments per paint, on MAX about half.
    function ghostStride(historyIndex) {
        return historyIndex === 0 ? 1 : (historyIndex >= 3 ? 3 : 2)
    }
    function requestGridRender() { _gridDirty = true }

    property int _lastFrameRev: -1

    Timer {
        interval: 33        // ~30 FPS cap
        repeat: true
        running: true
        onTriggered: {
            // v3e: poll for fresh frames instead of receiving them through a
            // per-frame signal. frameRevision() returns an int (primitive —
            // no container conversion); new data is pulled as a JSON string
            // and JSON.parse builds pure JS objects entirely inside the JS
            // engine. The v3b/v3d logs proved the ~0.5 ms/s live-set growth
            // follows frame delivery however the payload crosses the bridge
            // as QVariant containers; this removes that path completely.
            var rev = scopeFrames.frameRevision(scopeView.effect)
            if (rev !== scopeView._lastFrameRev) {
                scopeView._lastFrameRev = rev
                if (!scopeView.freeze) {
                    var pulled = JSON.parse(scopeFrames.takeFramesJson(scopeView.effect))
                    if (!pulled || pulled.length < 4) {
                        scopeView.resetTraceState()
                    } else {
                        scopeView.setFrames(pulled)
                    }
                }
            }
            if (scopeView._gridDirty) {
                scopeView._gridDirty = false
                gridCanvas.requestPaint()
            }
            // The trace is hidden behind the tuner page; keep the dirty flag
            // and repaint on return instead of drawing an unseen canvas.
            if (scopeView._paintDirty && scopeView.uiPage !== "tuner") {
                scopeView._paintDirty = false
                chart.requestPaint()
            }
        }
    }

    Timer {
        // DIAGNOSTIC (v3c): both v3a and v3b logs show the engine's GC pause
        // growing linearly with uptime (~0.5 ms/s, same curve in both builds),
        // i.e. the live set or heap footprint grows without bound. Forcing a
        // collection on a fixed beat and timing it turns that growth into a
        // clean curve in the perf log (qgc_ms), independent of when the
        // organic GC happens to fire.
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            var gcStart = Date.now()
            gc()
            scopeFrames.noteQmlGc(Date.now() - gcStart)
        }
    }

    Timer {
        interval: 500       // auto-trigger threshold tracking, ~2x/sec (throttled)
        repeat: true
        running: scopeView.autoTrigger && !scopeView.freeze
        onTriggered: scopeView.applyAutoTrigger()
    }
    property int xyStartChannel: viewMode === 2 ? 0 : 2
    // XY plot geometry, shared by the grid layer, the trace layer and the
    // readout overlays so all three agree without re-deriving it per paint.
    property real xyPlotSize: Math.min(gridCanvas.width - 36, gridCanvas.height - 36)
    property real xyPlotLeft: (gridCanvas.width - xyPlotSize) / 2
    property real xyPlotTop: (gridCanvas.height - xyPlotSize) / 2
    property real displayGain: displayGains[Math.max(0, Math.min(displayGains.length - 1, voltsDivIndex))]
    property real traceIntensity: intensityAlphas[Math.max(0, Math.min(intensityAlphas.length - 1, intensityIndex))]
    property real refreshHzEstimate: 0.0
    property double lastFrameAtMs: 0
    property int frameSampleCount: 0

    function controlValue(name, fallback) {
        var effectState = currentEffects[effect]
        if (!effectState || !effectState["controls"] || !effectState["controls"][name]) {
            return fallback
        }

        var value = effectState["controls"][name]["value"]
        return value === undefined || value === null ? fallback : value
    }

    function intControlValue(name, fallback) {
        return Math.round(controlValue(name, fallback))
    }

    function boundedIntControlValue(name, fallback, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, intControlValue(name, fallback)))
    }

    function boolControlValue(name, fallback) {
        return Boolean(controlValue(name, fallback ? 1 : 0))
    }

    function emptyFrames() {
        return [[], [], [], []]
    }

    function makeTraceStats() {
        return {"peak": 0.0, "minimum": 0.0, "maximum": 0.0, "pp": 0.0, "mean": 0.0, "rms": 0.0, "frequency": 0.0}
    }

    function emptyStats() {
        return [makeTraceStats(), makeTraceStats(), makeTraceStats(), makeTraceStats()]
    }

    function normalizeFrames(frames) {
        var normalized = emptyFrames()
        if (!frames) {
            return normalized
        }

        for (var channel = 0; channel < 4; ++channel) {
            if (frames.length > channel && frames[channel]) {
                normalized[channel] = frames[channel]
            }
        }
        return normalized
    }

    function traceLength(frames) {
        var maximum = 0
        for (var channel = 0; channel < 4; ++channel) {
            if (frames.length > channel && frames[channel]) {
                maximum = Math.max(maximum, frames[channel].length)
            }
        }
        return maximum
    }

    function minArrayValue(values) {
        if (!values || values.length === 0) {
            return 0.0
        }
        var minimum = values[0]
        for (var index = 1; index < values.length; ++index) {
            minimum = Math.min(minimum, values[index])
        }
        return minimum
    }

    function maxArrayValue(values) {
        if (!values || values.length === 0) {
            return 0.0
        }
        var maximum = values[0]
        for (var index = 1; index < values.length; ++index) {
            maximum = Math.max(maximum, values[index])
        }
        return maximum
    }

    function channelStats(channel) {
        return (traceStats.length > channel && traceStats[channel]) ? traceStats[channel] : makeTraceStats()
    }

    function persistenceDepth() {
        return persistenceDepths[Math.max(0, Math.min(persistenceDepths.length - 1, persistenceIndex))]
    }

    function visibleWindowMs() {
        return timebaseMsValues[timebaseIndex] * 10.0
    }

    function registerFrameArrival(sampleCount) {
        var now = Date.now()
        frameSampleCount = sampleCount
        if (lastFrameAtMs > 0) {
            var deltaMs = Math.max(1, now - lastFrameAtMs)
            var instantHz = 1000.0 / deltaMs
            refreshHzEstimate = refreshHzEstimate > 0.0 ? (refreshHzEstimate * 0.82) + (instantHz * 0.18) : instantHz
        }
        lastFrameAtMs = now
    }

    function setFrames(frames) {
        rawTraces = normalizeFrames(frames)
        registerFrameArrival(traceLength(rawTraces))

        // v2/v3 payloads carry the envelope and plugin-measured frequencies
        // after the 4 point traces; a cleared frame ([]) leaves these unset.
        if (frames.length >= 12) {
            var nextMin = [frames[4], frames[5], frames[6], frames[7]]
            var nextMax = [frames[8], frames[9], frames[10], frames[11]]
            for (var envChannel = 0; envChannel < 4; ++envChannel) {
                // AC coupling shifts the point trace by its mean; shift the
                // envelope identically so the band hugs the displayed trace.
                // (Entries may be null: the decoder suppresses channels whose
                // min/max carry no information beyond the point trace.)
                if (couplingMode(envChannel) === 1 && rawTraces[envChannel].length > 0 && nextMin[envChannel]) {
                    var acOffset = -meanValue(rawTraces[envChannel])
                    nextMin[envChannel] = shiftTrace(nextMin[envChannel], acOffset)
                    nextMax[envChannel] = shiftTrace(nextMax[envChannel], acOffset)
                }
            }
            hfMin = nextMin
            hfMax = nextMax
            pluginFreqs = frames.length >= 13 ? frames[12] : [0.0, 0.0, 0.0, 0.0]
        } else {
            hfMin = [null, null, null, null]
            hfMax = [null, null, null, null]
            pluginFreqs = [0.0, 0.0, 0.0, 0.0]
        }

        // Incremental: process ONLY the new frame; reuse the already-processed
        // history frames (shifted) instead of reprocessing all of them every
        // frame. A full reprocess only happens on control changes
        // (rebuildTraceCaches via the coupling/timebase/envelope handlers).
        var limit = persistenceDepth()
        var processedCurrent = emptyFrames()
        for (var channel = 0; channel < 4; ++channel) {
            processedCurrent[channel] = processTrace(rawTraces[channel], channel)
        }

        var nextRaw = [rawTraces]
        var nextProcessed = [processedCurrent]
        for (var index = 0;
             index < frameHistory.length && index < processedHistory.length && nextRaw.length < limit;
             ++index) {
            nextRaw.push(frameHistory[index])
            nextProcessed.push(processedHistory[index])
        }

        frameHistory = nextRaw
        processedHistory = nextProcessed
        processedTraces = processedCurrent

        // Stats, envelope and hold markers feed the numeric readouts and slow
        // overlays; refreshing them at every frame both burned JS time and made
        // the numbers an unreadable blur. They get their own slower beat.
        var now = Date.now()
        if (now - _lastStatsAtMs >= statsIntervalMs) {
            _lastStatsAtMs = now
            refreshDerivedState(processedCurrent, nextProcessed)
        }
        requestRender()
    }

    // Everything derived from the current frame that is allowed to lag a
    // beat behind the trace: numeric stats, persistence envelope, hold
    // markers, XY correlation.
    function refreshDerivedState(processedCurrent, historyFrames) {
        var nextStats = emptyStats()
        var nextEnvelopeCache = [null, null, null, null]
        var nextHoldMarkers = [null, null, null, null]
        var nextSignificant = [false, false, false, false]
        for (var channel = 0; channel < 4; ++channel) {
            nextStats[channel] = traceStatsFor(processedCurrent[channel])
            // Plugin-measured frequency (v2/v3) is alias-free; the JS estimate
            // from the decimated frame stays as the fallback when the plugin
            // reports 0 Hz.
            if (pluginFreqs.length > channel && pluginFreqs[channel] > 0.0) {
                nextStats[channel].frequency = pluginFreqs[channel]
            }
            nextEnvelopeCache[channel] = buildEnvelope(channel, historyFrames)
            nextHoldMarkers[channel] = buildHoldMarkers(processedCurrent[channel], nextEnvelopeCache[channel])
            // Draw the HF envelope only where it visibly diverges from the
            // point trace, so clean/slow signals pay nothing for it.
            var mins = hfMin[channel]
            var maxs = hfMax[channel]
            if (mins && maxs) {
                var pointCount = Math.min(mins.length, maxs.length)
                for (var sample = 0; sample < pointCount; ++sample) {
                    if (maxs[sample] - mins[sample] > 0.05) {
                        nextSignificant[channel] = true
                        break
                    }
                }
            }
        }
        traceStats = nextStats
        envelopeCache = nextEnvelopeCache
        holdMarkers = nextHoldMarkers
        hfSignificant = nextSignificant
        if (isXYView) {
            xyCorrelation = estimateCorrelation(
                processedCurrent[xyStartChannel], processedCurrent[xyStartChannel + 1])
        }
        if (gcOnStatsBeat) {
            gc()
        }
    }

    function resetTraceState() {
        rawTraces = emptyFrames()
        frameHistory = []
        processedTraces = emptyFrames()
        processedHistory = []
        traceStats = emptyStats()
        holdMarkers = [null, null, null, null]
        envelopeCache = [null, null, null, null]
        hfMin = [null, null, null, null]
        hfMax = [null, null, null, null]
        pluginFreqs = [0.0, 0.0, 0.0, 0.0]
        hfSignificant = [false, false, false, false]
        xyCorrelation = 0.0
        _lastStatsAtMs = 0        // next frame refreshes the readouts immediately
        refreshHzEstimate = 0.0
        lastFrameAtMs = 0
        frameSampleCount = 0
        requestRender()
    }

    function clearTraces() {
        resetTraceState()
        scopeFrames.clearEffect(effect)
    }

    function disableNotifyBroadcast() {
        if (notifyBroadcastEffect !== "") {
            knobs.set_port_broadcast(notifyBroadcastEffect, "notify", false)
            notifyBroadcastEffect = ""
        }
    }

    function syncNotifyBroadcast() {
        if (hasEffect && notifyBroadcastEffect === effect) {
            return
        }

        disableNotifyBroadcast()
        resetTraceState()

        if (hasEffect) {
            knobs.set_port_broadcast(effect, "notify", true)
            notifyBroadcastEffect = effect
        }
    }

    function refreshHistoryLimit() {
        var next = []
        var limit = persistenceDepth()
        if (hasFrame) {
            next.push(rawTraces)
        }
        for (var index = 0; index < frameHistory.length && next.length < limit; ++index) {
            if (frameHistory[index] !== rawTraces) {
                next.push(frameHistory[index])
            }
        }
        frameHistory = next
        rebuildTraceCaches()
    }

    function toggleFreeze() {
        knobs.ui_knob_change(effect, "freeze", freeze ? 0 : 1)
    }

    function setIntControl(name, value) {
        knobs.ui_knob_change(effect, name, Number(value))
    }

    function setBoolControl(name, value) {
        knobs.ui_knob_change(effect, name, value ? 1 : 0)
    }

    function stepIntControl(name, currentValue, minValue, maxValue, delta) {
        var next = Math.max(minValue, Math.min(maxValue, currentValue + delta))
        setIntControl(name, next)
    }

    function couplingMode(channel) {
        if (channel === 0) {
            return coupling1
        }
        if (channel === 1) {
            return coupling2
        }
        if (channel === 2) {
            return coupling3
        }
        return coupling4
    }

    function couplingName(channel) {
        return "coupling_" + (channel + 1)
    }

    function channelVisible(channel) {
        if (channel === 0) {
            return visible1
        }
        if (channel === 1) {
            return visible2
        }
        if (channel === 2) {
            return visible3
        }
        return visible4
    }

    function visibilityName(channel) {
        return "visible_" + (channel + 1)
    }

    function visibleCount() {
        var count = 0
        for (var channel = 0; channel < 4; ++channel) {
            if (channelVisible(channel)) {
                count += 1
            }
        }
        return count
    }

    function clampUnit(value) {
        return Math.max(-1.0, Math.min(1.0, value))
    }

    function clampFraction(value) {
        return Math.max(0.0, Math.min(1.0, value))
    }

    function toggleChannelVisible(channel) {
        setBoolControl(visibilityName(channel), !channelVisible(channel))
    }

    function setCursorValue(name, value, signedRange) {
        scopeView[name] = signedRange ? clampUnit(value) : clampFraction(value)
    }

    function stepCursorValue(name, delta, signedRange) {
        setCursorValue(name, scopeView[name] + delta, signedRange)
    }

    function cursorSignalValue(value) {
        return displayGain <= 0.0 ? 0.0 : value / displayGain
    }

    function cursorAbsoluteTimeMs(value) {
        return clampFraction(value) * visibleWindowMs()
    }

    function cursorAbsoluteVoltage(value) {
        return cursorSignalValue(clampUnit(value))
    }

    function cursorDeltaTimeMs() {
        return Math.abs(cursorTimeB - cursorTimeA) * visibleWindowMs()
    }

    function cursorDeltaVoltage() {
        return Math.abs(cursorSignalValue(cursorVoltB) - cursorSignalValue(cursorVoltA))
    }

    function cursorFrequencyHz() {
        var deltaMs = cursorDeltaTimeMs()
        return deltaMs > 0.0 ? 1000.0 / deltaMs : 0.0
    }

    function updateSelectedCursorFromPlot(x, y, drawWidth, drawHeight) {
        if (drawWidth <= 0 || drawHeight <= 0) {
            return
        }
        var nextTime = clampFraction(x / drawWidth)
        var focusTop = viewMode === 1 ? 0.0 : (drawHeight / 4.0) * focusChannel
        var focusHeight = viewMode === 1 ? drawHeight : drawHeight / 4.0
        var amplitude = focusHeight * 0.37
        var centerY = focusTop + focusHeight / 2.0
        var nextVolt = amplitude <= 0.0 ? 0.0 : clampUnit((centerY - y) / amplitude)

        if (selectedCursor === 0) {
            cursorTimeA = nextTime
            cursorVoltA = nextVolt
        } else {
            cursorTimeB = nextTime
            cursorVoltB = nextVolt
        }
        requestRender()
    }

    function buildEnvelope(channel, historyFrames) {
        if (!showEnvelope || historyFrames.length < 2) {
            return null
        }

        var sampleCount = 0
        for (var frameIndex = 0; frameIndex < historyFrames.length; ++frameIndex) {
            if (historyFrames[frameIndex].length > channel && historyFrames[frameIndex][channel]) {
                sampleCount = Math.max(sampleCount, historyFrames[frameIndex][channel].length)
            }
        }

        if (sampleCount === 0) {
            return null
        }

        var minimums = []
        var maximums = []
        for (var sampleIndex = 0; sampleIndex < sampleCount; ++sampleIndex) {
            minimums.push(9999.0)
            maximums.push(-9999.0)
        }

        var hadData = false
        for (frameIndex = 0; frameIndex < historyFrames.length; ++frameIndex) {
            var trace = historyFrames[frameIndex][channel]
            for (sampleIndex = 0; trace && sampleIndex < trace.length; ++sampleIndex) {
                minimums[sampleIndex] = Math.min(minimums[sampleIndex], trace[sampleIndex])
                maximums[sampleIndex] = Math.max(maximums[sampleIndex], trace[sampleIndex])
                hadData = true
            }
        }

        return hadData ? {"minimums": minimums, "maximums": maximums} : null
    }

    function buildHoldMarkers(trace, envelope) {
        if ((!trace || trace.length === 0) && !envelope) {
            return null
        }

        var minimum = minValue(trace)
        var maximum = maxValue(trace)
        if (envelope) {
            minimum = Math.min(minimum, minArrayValue(envelope.minimums))
            maximum = Math.max(maximum, maxArrayValue(envelope.maximums))
        }
        return {"minimum": minimum, "maximum": maximum}
    }

    function rebuildTraceCaches() {
        var nextCurrent = emptyFrames()
        var nextHistory = []

        for (var channel = 0; channel < 4; ++channel) {
            nextCurrent[channel] = processTrace(rawTraces[channel], channel)
        }

        for (var frameIndex = 0; frameIndex < frameHistory.length; ++frameIndex) {
            var sourceFrame = frameHistory[frameIndex]
            var processedFrame = emptyFrames()
            for (channel = 0; channel < 4; ++channel) {
                processedFrame[channel] = processTrace(sourceFrame[channel], channel)
            }
            nextHistory.push(processedFrame)
        }

        processedTraces = nextCurrent
        processedHistory = nextHistory
        // Control changes should reflect in the readouts immediately, so the
        // derived state refreshes now and restarts its beat from here.
        _lastStatsAtMs = Date.now()
        refreshDerivedState(nextCurrent, nextHistory)
        requestRender()
    }

    function processTrace(trace, channel) {
        if (!trace || trace.length === 0) {
            return []
        }

        // DC coupling applies no offset — return the frame as-is. Traces are
        // never mutated downstream, so skipping the 192-element copy per
        // channel per frame is safe.
        if (couplingMode(channel) !== 1) {
            return trace
        }

        var offset = 0.0
        for (var index = 0; index < trace.length; ++index) {
            offset += trace[index]
        }
        offset /= trace.length

        var output = new Float32Array(trace.length)
        for (index = 0; index < trace.length; ++index) {
            output[index] = trace[index] - offset
        }
        return output
    }

    function currentTrace(channel) {
        return (processedTraces.length > channel && processedTraces[channel]) ? processedTraces[channel] : []
    }

    function historyEnvelope(channel) {
        return showEnvelope && envelopeCache.length > channel ? envelopeCache[channel] : null
    }

    function peakValue(trace) {
        var peak = 0.0
        for (var index = 0; index < trace.length; ++index) {
            peak = Math.max(peak, Math.abs(trace[index]))
        }
        return peak
    }

    function minValue(trace) {
        if (trace.length === 0) {
            return 0.0
        }
        var minimum = trace[0]
        for (var index = 1; index < trace.length; ++index) {
            minimum = Math.min(minimum, trace[index])
        }
        return minimum
    }

    function maxValue(trace) {
        if (trace.length === 0) {
            return 0.0
        }
        var maximum = trace[0]
        for (var index = 1; index < trace.length; ++index) {
            maximum = Math.max(maximum, trace[index])
        }
        return maximum
    }

    function ppValue(trace) {
        return maxValue(trace) - minValue(trace)
    }

    function meanValue(trace) {
        if (trace.length === 0) {
            return 0.0
        }
        var total = 0.0
        for (var index = 0; index < trace.length; ++index) {
            total += trace[index]
        }
        return total / trace.length
    }

    function rmsValue(trace) {
        if (trace.length === 0) {
            return 0.0
        }
        var total = 0.0
        for (var index = 0; index < trace.length; ++index) {
            total += trace[index] * trace[index]
        }
        return Math.sqrt(total / trace.length)
    }

    function estimateFrequency(trace) {
        if (!trace || trace.length < 8) {
            return 0.0
        }

        var crossings = []
        for (var index = 1; index < trace.length; ++index) {
            if (trace[index - 1] <= 0.0 && trace[index] > 0.0) {
                crossings.push(index)
            }
        }

        if (crossings.length < 2) {
            return 0.0
        }

        var periodSamples = (crossings[crossings.length - 1] - crossings[0]) / (crossings.length - 1)
        if (periodSamples <= 0.0) {
            return 0.0
        }

        var samplesPerSecond = trace.length / (visibleWindowMs() / 1000.0)
        return samplesPerSecond / periodSamples
    }

    function estimateCorrelation(xTrace, yTrace) {
        var pointCount = Math.min(xTrace ? xTrace.length : 0, yTrace ? yTrace.length : 0)
        if (pointCount < 4) {
            return 0.0
        }

        var meanX = 0.0
        var meanY = 0.0
        for (var index = 0; index < pointCount; ++index) {
            meanX += xTrace[index]
            meanY += yTrace[index]
        }
        meanX /= pointCount
        meanY /= pointCount

        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for (index = 0; index < pointCount; ++index) {
            var centeredX = xTrace[index] - meanX
            var centeredY = yTrace[index] - meanY
            covariance += centeredX * centeredY
            varianceX += centeredX * centeredX
            varianceY += centeredY * centeredY
        }

        if (varianceX <= 0.0 || varianceY <= 0.0) {
            return 0.0
        }

        return covariance / Math.sqrt(varianceX * varianceY)
    }

    function traceStatsFor(trace) {
        if (!trace || trace.length === 0) {
            return makeTraceStats()
        }

        // Single pass over the samples (was six separate helper loops x 4
        // channels per refresh).
        var minimum = trace[0]
        var maximum = trace[0]
        var total = 0.0
        var totalSquares = 0.0
        for (var index = 0; index < trace.length; ++index) {
            var value = trace[index]
            if (value < minimum) {
                minimum = value
            }
            if (value > maximum) {
                maximum = value
            }
            total += value
            totalSquares += value * value
        }

        return {
            "peak": Math.max(Math.abs(minimum), Math.abs(maximum)),
            "minimum": minimum,
            "maximum": maximum,
            "pp": maximum - minimum,
            "mean": total / trace.length,
            "rms": Math.sqrt(totalSquares / trace.length),
            "frequency": estimateFrequency(trace)
        }
    }

    function formatMetric(value) {
        var absValue = Math.abs(value)
        return absValue >= 10.0 ? value.toFixed(1) : value.toFixed(2)
    }

    function formatTimeMetric(valueMs) {
        var absValue = Math.abs(valueMs)
        if (absValue >= 1000.0) {
            return (valueMs / 1000.0).toFixed(absValue >= 10000.0 ? 1 : 2) + " s"
        }
        if (absValue >= 1.0) {
            return valueMs.toFixed(absValue >= 100.0 ? 1 : 2) + " ms"
        }
        return (valueMs * 1000.0).toFixed(absValue >= 0.1 ? 1 : 2) + " us"
    }

    function formatVoltageMetric(value) {
        return formatMetric(value) + " V"
    }

    function formatFrequency(value) {
        if (!value || value < 0.2) {
            return "--"
        }
        if (value >= 1000.0) {
            return (value / 1000.0).toFixed(value >= 10000.0 ? 1 : 2) + " kHz"
        }
        return value.toFixed(value >= 100.0 ? 1 : 2) + " Hz"
    }

    function couplingLabel(channel) {
        return couplingMode(channel) === 1 ? "AC" : "DC"
    }

    function autosetScope() {
        var bestChannel = -1
        var bestPeak = 0.0
        var bestTrace = []

        for (var channel = 0; channel < 4; ++channel) {
            if (!channelVisible(channel)) {
                continue
            }
            var trace = currentTrace(channel)
            var peak = peakValue(trace)
            if (peak > bestPeak) {
                bestPeak = peak
                bestChannel = channel
                bestTrace = trace
            }
        }

        if (bestChannel < 0 || bestPeak <= 0.0001) {
            return
        }

        focusChannel = bestChannel
        setIntControl("trigger_source", bestChannel + 1)
        knobs.ui_knob_change(effect, "trigger_level", meanValue(bestTrace))

        var nextVoltsDiv = displayGains.length - 1
        for (var gainIndex = 0; gainIndex < displayGains.length; ++gainIndex) {
            if (bestPeak * displayGains[gainIndex] <= 0.78) {
                nextVoltsDiv = gainIndex
                break
            }
        }
        setIntControl("volts_div", nextVoltsDiv)

        var estimatedHz = (pluginFreqs.length > bestChannel && pluginFreqs[bestChannel] > 0.2)
            ? pluginFreqs[bestChannel]
            : estimateFrequency(bestTrace)
        if (estimatedHz > 0.2) {
            var desiredWindow = (1000.0 / estimatedHz) * 4.0
            var bestTimebase = 0
            var bestError = 999999.0
            for (var timeIndex = 0; timeIndex < timebaseMsValues.length; ++timeIndex) {
                var windowMs = timebaseMsValues[timeIndex] * 10.0
                var error = Math.abs(windowMs - desiredWindow)
                if (error < bestError) {
                    bestError = error
                    bestTimebase = timeIndex
                }
            }
            setIntControl("timebase", bestTimebase)
        }

        var gain = displayGains[nextVoltsDiv]
        cursorTimeA = 0.18
        cursorTimeB = 0.68
        cursorVoltA = clampUnit(maxValue(bestTrace) * gain)
        cursorVoltB = clampUnit(minValue(bestTrace) * gain)
    }

    function triggerGuideY(top, rowHeight) {
        var centerY = top + rowHeight / 2
        var amplitude = rowHeight * 0.37
        return centerY - (Math.max(-1.0, Math.min(1.0, triggerLevel * displayGain)) * amplitude)
    }

    function drawScopeGrid(ctx, top, rowHeight, drawWidth) {
        // Batch all faint grid lines into ONE path/stroke (was 16 separate
        // strokes per row); only the brighter centre line is a second stroke.
        ctx.save()
        ctx.lineWidth = 1
        ctx.strokeStyle = "#172435"
        ctx.beginPath()
        for (var vertical = 0; vertical < 11; ++vertical) {
            var x = (drawWidth / 10) * vertical
            ctx.moveTo(x, top)
            ctx.lineTo(x, top + rowHeight)
        }
        for (var horizontal = 0; horizontal < 5; ++horizontal) {
            var y = top + (rowHeight / 4) * horizontal
            ctx.moveTo(0, y)
            ctx.lineTo(drawWidth, y)
        }
        ctx.stroke()
        ctx.strokeStyle = "#2B4865"
        ctx.beginPath()
        ctx.moveTo(0, top + rowHeight / 2)
        ctx.lineTo(drawWidth, top + rowHeight / 2)
        ctx.stroke()
        ctx.restore()
    }

    function drawXYGrid(ctx, left, top, plotWidth, plotHeight) {
        ctx.save()
        var centerX = left + plotWidth / 2
        var centerY = top + plotHeight / 2
        var radius = Math.min(plotWidth, plotHeight) * 0.5

        ctx.fillStyle = "#091018"
        ctx.fillRect(left, top, plotWidth, plotHeight)

        ctx.strokeStyle = "#172435"
        ctx.lineWidth = 1
        for (var vertical = 0; vertical < 9; ++vertical) {
            var x = left + (plotWidth / 8) * vertical
            ctx.beginPath()
            ctx.moveTo(x, top)
            ctx.lineTo(x, top + plotHeight)
            ctx.stroke()
        }
        for (var horizontal = 0; horizontal < 9; ++horizontal) {
            var y = top + (plotHeight / 8) * horizontal
            ctx.beginPath()
            ctx.moveTo(left, y)
            ctx.lineTo(left + plotWidth, y)
            ctx.stroke()
        }
        if (ctx.setLineDash) {
            ctx.setLineDash([4, 6])
        }
        ctx.strokeStyle = "#122131"
        ctx.beginPath()
        ctx.moveTo(left, top)
        ctx.lineTo(left + plotWidth, top + plotHeight)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(left + plotWidth, top)
        ctx.lineTo(left, top + plotHeight)
        ctx.stroke()
        if (ctx.setLineDash) {
            ctx.setLineDash([])
        }
        ctx.strokeStyle = "#163044"
        for (var ring = 1; ring <= 4; ++ring) {
            ctx.globalAlpha = ring === 4 ? 0.75 : 0.35
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius * (ring / 4.0), 0, Math.PI * 2)
            ctx.stroke()
        }
        ctx.globalAlpha = 1.0
        ctx.strokeStyle = "#2B4865"
        ctx.beginPath()
        ctx.moveTo(centerX, top)
        ctx.lineTo(centerX, top + plotHeight)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(left, centerY)
        ctx.lineTo(left + plotWidth, centerY)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(centerX, centerY, 4, 0, Math.PI * 2)
        ctx.stroke()
        ctx.restore()
    }

    function drawTriggerGuide(ctx, top, rowHeight, color, drawWidth) {
        // Always show the trigger threshold line on the SYNC'd channel so the
        // trigger point is legible at a glance (works with auto-threshold too).
        var y = triggerGuideY(top, rowHeight)
        ctx.save()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1
        if (ctx.setLineDash) {
            ctx.setLineDash([6, 6])
        }
        ctx.beginPath()
        ctx.moveTo(0, y)
        ctx.lineTo(drawWidth, y)
        ctx.stroke()
        if (ctx.setLineDash) {
            ctx.setLineDash([])
        }
        ctx.beginPath()
        ctx.moveTo(0, y)
        ctx.lineTo(10, y - 6)
        ctx.lineTo(10, y + 6)
        ctx.closePath()
        ctx.fill()
        ctx.font = "15px " + mainFont.name
        ctx.fillText("TRIG " + triggerLevel.toFixed(2), drawWidth - 86, Math.max(16, y - 5))
        ctx.restore()
    }

    function drawScopeEnvelope(ctx, envelope, top, rowHeight, color, alpha, drawWidth) {
        if (!envelope || envelope.minimums.length < 2 || envelope.maximums.length < 2) {
            return
        }

        var centerY = top + rowHeight / 2
        var amplitude = rowHeight * 0.37
        ctx.save()
        ctx.fillStyle = color
        ctx.globalAlpha = alpha * 0.12
        ctx.beginPath()
        for (var index = 0; index < envelope.maximums.length; ++index) {
            var x = envelope.maximums.length === 1 ? drawWidth / 2 : (drawWidth * index) / (envelope.maximums.length - 1)
            var y = centerY - (clampUnit(envelope.maximums[index] * displayGain) * amplitude)
            if (index === 0) {
                ctx.moveTo(x, y)
            } else {
                ctx.lineTo(x, y)
            }
        }
        for (index = envelope.minimums.length - 1; index >= 0; --index) {
            x = envelope.minimums.length === 1 ? drawWidth / 2 : (drawWidth * index) / (envelope.minimums.length - 1)
            y = centerY - (clampUnit(envelope.minimums[index] * displayGain) * amplitude)
            ctx.lineTo(x, y)
        }
        ctx.closePath()
        ctx.fill()
        ctx.restore()
    }

    function drawScopeTrace(ctx, trace, top, rowHeight, color, alpha, drawWidth, stride) {
        var centerY = top + rowHeight / 2
        var amplitude = rowHeight * 0.37

        if (trace.length === 0) {
            return
        }
        // stride > 1 = ghost decimation: faded persistence layers carry no
        // measurement information (stats/trigger/envelope always use the
        // full-resolution series), so halving their vertices halves their
        // stroke cost on the software rasteriser. Decimated points keep
        // their true x positions and the final sample is always drawn.
        var step = (stride === undefined || stride < 1) ? 1 : stride

        // Single thin stroke, tuned for the software rasteriser. Stroke cost is
        // arc-length x lineWidth, and round joins fill an arc at EVERY vertex
        // (192 x 4ch = 768 arcs/paint). On busy waveforms that is what collapsed
        // FPS. A 1.0px brush with bevel joins / butt caps roughly halves the
        // stroked pixel area and removes the per-vertex arc fills; the saving
        // grows with waveform complexity, which is exactly the failure mode.
        ctx.save()
        ctx.globalAlpha = Math.min(1.0, alpha + 0.1)
        ctx.strokeStyle = color
        ctx.lineWidth = 1.0
        ctx.lineJoin = "bevel"
        ctx.lineCap = "butt"
        ctx.beginPath()
        var last = trace.length - 1
        for (var index = 0; index <= last; index += step) {
            var x = last === 0 ? drawWidth / 2 : (drawWidth * index) / last
            var y = centerY - (Math.max(-1.0, Math.min(1.0, trace[index] * displayGain)) * amplitude)
            if (index === 0) {
                ctx.moveTo(x, y)
            } else {
                ctx.lineTo(x, y)
            }
        }
        if (step > 1 && last > 0 && last % step !== 0) {
            ctx.lineTo(drawWidth,
                       centerY - (Math.max(-1.0, Math.min(1.0, trace[last] * displayGain)) * amplitude))
        }
        ctx.stroke()
        ctx.restore()
    }

    function drawXYTrace(ctx, xTrace, yTrace, left, top, plotWidth, plotHeight, color, alpha, stride) {
        var pointCount = Math.min(xTrace.length, yTrace.length)
        if (pointCount < 2) {
            return
        }
        // stride > 1 = ghost decimation (see drawScopeTrace). XY stroke cost
        // is arc-length-bound, so ghosts gain the most here.
        var step = (stride === undefined || stride < 1) ? 1 : stride

        // Single pass (was a 3-pass 7px/2.1px/0.9px glow). Same software-canvas
        // cost rule as the time-domain trace: one thin bevel/butt stroke instead
        // of three wide round-capped ones.
        ctx.save()
        ctx.strokeStyle = color
        ctx.lineJoin = "bevel"
        ctx.lineCap = "butt"
        ctx.globalAlpha = Math.min(1.0, alpha + 0.1)
        // 1.0 like the time-domain trace: XY Lissajous figures have the
        // longest stroke arc-length of any view (stroke cost ~ width x
        // arc-length on the software rasteriser), which is why XY dropped
        // more frames than stack.
        ctx.lineWidth = 1.0
        ctx.beginPath()
        var x, y
        var lastPoint = pointCount - 1
        for (var index = 0; index <= lastPoint; index += step) {
            x = left + ((Math.max(-1.0, Math.min(1.0, xTrace[index] * displayGain)) + 1.0) * 0.5 * plotWidth)
            y = top + plotHeight - ((Math.max(-1.0, Math.min(1.0, yTrace[index] * displayGain)) + 1.0) * 0.5 * plotHeight)
            if (index === 0) {
                ctx.moveTo(x, y)
            } else {
                ctx.lineTo(x, y)
            }
        }
        if (step > 1 && lastPoint % step !== 0) {
            x = left + ((Math.max(-1.0, Math.min(1.0, xTrace[lastPoint] * displayGain)) + 1.0) * 0.5 * plotWidth)
            y = top + plotHeight - ((Math.max(-1.0, Math.min(1.0, yTrace[lastPoint] * displayGain)) + 1.0) * 0.5 * plotHeight)
            ctx.lineTo(x, y)
        }
        ctx.stroke()

        ctx.fillStyle = color
        ctx.globalAlpha = Math.min(1.0, alpha + 0.15)
        ctx.beginPath()
        ctx.arc(x, y, 2.8, 0, Math.PI * 2)
        ctx.fill()
        ctx.restore()
    }

    function drawHoldMarkers(ctx, top, rowHeight, markers, color, drawWidth, offset) {
        if (!markers) {
            return
        }

        var centerY = top + rowHeight / 2
        var amplitude = rowHeight * 0.37
        var rightOffset = offset === undefined ? 0 : offset
        var markerX = drawWidth - 4 - rightOffset
        var maxY = centerY - (clampUnit(markers.maximum * displayGain) * amplitude)
        var minY = centerY - (clampUnit(markers.minimum * displayGain) * amplitude)

        ctx.save()
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.2
        ctx.globalAlpha = 0.18
        ctx.fillRect(drawWidth - 10 - rightOffset, Math.min(maxY, minY), 6, Math.abs(maxY - minY))
        ctx.globalAlpha = 0.95

        ctx.beginPath()
        ctx.moveTo(markerX, maxY)
        ctx.lineTo(drawWidth - 20 - rightOffset, maxY)
        ctx.lineTo(drawWidth - 14 - rightOffset, maxY - 5)
        ctx.stroke()

        ctx.beginPath()
        ctx.moveTo(markerX, minY)
        ctx.lineTo(drawWidth - 20 - rightOffset, minY)
        ctx.lineTo(drawWidth - 14 - rightOffset, minY + 5)
        ctx.stroke()
        ctx.restore()
    }

    function drawBadge(ctx, text, x, y, fillColor, borderColor, textColor, maxWidth, maxHeight) {
        var padding = 6
        var badgeHeight = 16
        var textWidth = ctx.measureText ? ctx.measureText(text).width : text.length * 7
        var badgeWidth = Math.max(26, textWidth + padding * 2)
        var badgeX = Math.max(2, Math.min(maxWidth - badgeWidth - 2, x))
        var badgeY = Math.max(2, Math.min(maxHeight - badgeHeight - 2, y))

        ctx.save()
        ctx.globalAlpha = 0.78
        ctx.fillStyle = fillColor
        ctx.fillRect(badgeX, badgeY, badgeWidth, badgeHeight)
        ctx.globalAlpha = 1.0
        ctx.strokeStyle = borderColor
        ctx.lineWidth = 1
        ctx.strokeRect(badgeX + 0.5, badgeY + 0.5, badgeWidth - 1, badgeHeight - 1)
        ctx.fillStyle = textColor
        ctx.fillText(text, badgeX + padding, badgeY + 11)
        ctx.restore()
    }

    function drawMeasurementCursors(ctx, focusTop, focusHeight, drawWidth, drawHeight) {
        if (!showCursors) {
            return
        }

        var labels = ["A", "B"]
        var colors = ["#90E7D0", "#FFD166"]
        var timeValues = [cursorTimeA, cursorTimeB]
        var voltageValues = [cursorVoltA, cursorVoltB]
        var amplitude = focusHeight * 0.37
        var centerY = focusTop + focusHeight / 2
        var cursorXs = []
        var deltaTop = drawHeight - 32

        ctx.save()
        ctx.font = "11px " + mainFont.name
        for (var index = 0; index < 2; ++index) {
            var cursorX = drawWidth * clampFraction(timeValues[index])
            var cursorY = centerY - (clampUnit(voltageValues[index]) * amplitude)
            cursorXs.push(cursorX)

            ctx.strokeStyle = colors[index]
            ctx.fillStyle = colors[index]
            ctx.lineWidth = selectedCursor === index ? 1.4 : 1.0
            if (ctx.setLineDash) {
                ctx.setLineDash([4, 4])
            }
            ctx.beginPath()
            ctx.moveTo(cursorX, 0)
            ctx.lineTo(cursorX, drawHeight)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(0, cursorY)
            ctx.lineTo(drawWidth, cursorY)
            ctx.stroke()
            if (ctx.setLineDash) {
                ctx.setLineDash([])
            }

            ctx.globalAlpha = 0.16
            ctx.fillRect(cursorX - 11, 4, 22, 14)
            ctx.fillRect(drawWidth - 74, cursorY - 8, 66, 16)
            ctx.globalAlpha = 1.0
            ctx.beginPath()
            ctx.arc(cursorX, cursorY, selectedCursor === index ? 5.2 : 4.0, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(cursorX, cursorY, 1.6, 0, Math.PI * 2)
            ctx.fill()

            drawBadge(
                ctx,
                labels[index] + " " + formatTimeMetric(cursorAbsoluteTimeMs(timeValues[index])),
                cursorX - 26,
                focusTop + 6 + (index * 18),
                "#0F1822",
                colors[index],
                colors[index],
                drawWidth,
                drawHeight
            )
            drawBadge(
                ctx,
                formatVoltageMetric(cursorAbsoluteVoltage(voltageValues[index])),
                drawWidth - 108,
                cursorY - 8,
                "#0F1822",
                colors[index],
                colors[index],
                drawWidth,
                drawHeight
            )
        }

        var leftX = Math.min(cursorXs[0], cursorXs[1])
        var rightX = Math.max(cursorXs[0], cursorXs[1])
        ctx.fillStyle = "#0E1720"
        ctx.strokeStyle = "#2B4865"
        ctx.lineWidth = 1
        ctx.globalAlpha = 0.82
        ctx.fillRect(leftX, deltaTop, Math.max(10, rightX - leftX), 10)
        ctx.globalAlpha = 1.0
        ctx.strokeRect(leftX + 0.5, deltaTop + 0.5, Math.max(9, rightX - leftX) - 1, 9)
        ctx.fillStyle = "#D7E6F5"
        ctx.fillText("dT " + formatTimeMetric(cursorDeltaTimeMs()) + "   dV " + formatVoltageMetric(cursorDeltaVoltage()), Math.max(10, leftX), deltaTop - 4)
        ctx.restore()
    }

    onTimebaseIndexChanged: rebuildTraceCaches()
    onVoltsDivIndexChanged: requestRender()
    onTriggerLevelChanged: requestRender()
    onTriggerModeChanged: requestRender()
    onTriggerSourceChanged: requestRender()
    onViewModeChanged: { requestRender(); requestGridRender() }
    onPersistenceIndexChanged: refreshHistoryLimit()
    onIntensityIndexChanged: requestRender()
    onCoupling1Changed: rebuildTraceCaches()
    onCoupling2Changed: rebuildTraceCaches()
    onCoupling3Changed: rebuildTraceCaches()
    onCoupling4Changed: rebuildTraceCaches()
    onVisible1Changed: { requestRender(); requestGridRender() }
    onVisible2Changed: { requestRender(); requestGridRender() }
    onVisible3Changed: { requestRender(); requestGridRender() }
    onVisible4Changed: { requestRender(); requestGridRender() }
    onFocusChannelChanged: requestRender()
    onHasFrameChanged: requestRender()
    onShowEnvelopeChanged: rebuildTraceCaches()
    onShowCursorsChanged: requestRender()
    onSelectedCursorChanged: requestRender()
    onCursorTimeAChanged: requestRender()
    onCursorTimeBChanged: requestRender()
    onCursorVoltAChanged: requestRender()
    onCursorVoltBChanged: requestRender()
    onEffectChanged: syncNotifyBroadcast()
    onHasEffectChanged: syncNotifyBroadcast()

    Component.onCompleted: {
        syncNotifyBroadcast()
    }

    Component.onDestruction: {
        disableNotifyBroadcast()
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0A1016" }
            GradientStop { position: 0.55; color: "#090D12" }
            GradientStop { position: 1.0; color: "#06090E" }
        }
        border.color: "#17212E"
        border.width: 2
    }

    Rectangle {
        id: traceFrame
        x: 16
        y: 12
        width: parent.width - 16 - 168
        height: parent.height - 12 - 90
        visible: scopeView.uiPage === "main" || scopeView.uiPage === "fullscreen"
        radius: 12
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0D141D" }
            GradientStop { position: 1.0; color: "#0B1118" }
        }
        border.color: "#223140"
        border.width: 1
        states: [
            State {
                name: "fs"
                when: scopeView.uiPage === "fullscreen"
                PropertyChanges {
                    target: traceFrame
                    x: 8; y: 8
                    width: scopeView.width - 8 - 120
                    height: scopeView.height - 16
                }
            }
        ]

        // Static layer: background, graticule, row shading, ruler baseline.
        // Repaints only when a control or the layout changes — never per
        // frame. On the software rasteriser this removes the fixed
        // full-canvas cost (background fill + grids) from every trace paint.
        Canvas {
            id: gridCanvas
            x: 16
            y: 16
            width: parent.width - 32
            height: parent.height - 32
            // Software rasteriser: anti-aliasing computes coverage along every
            // stroke edge. Disabling it is a large win for line-heavy content
            // (the whole scope is strokes) at the cost of slightly harder edges.
            antialiasing: false
            smooth: false
            onWidthChanged: scopeView.requestGridRender()
            onHeightChanged: scopeView.requestGridRender()

            onPaint: {
                var ctx = getContext("2d")
                var drawWidth = width
                var drawHeight = height

                // Opaque full-canvas fill IS the clear (covers every pixel).
                ctx.fillStyle = "#0C1016"
                ctx.fillRect(0, 0, drawWidth, drawHeight)

                if (scopeView.isXYView) {
                    scopeView.drawXYGrid(ctx, scopeView.xyPlotLeft, scopeView.xyPlotTop,
                                         scopeView.xyPlotSize, scopeView.xyPlotSize)
                    return
                }

                if (scopeView.viewMode === 1) {
                    scopeView.drawScopeGrid(ctx, 0, drawHeight, drawWidth)
                } else {
                    var rowHeight = drawHeight / 4
                    for (var channel = 0; channel < 4; ++channel) {
                        var top = rowHeight * channel
                        ctx.fillStyle = channel % 2 === 0 ? "#0D141C" : "#0F1721"
                        ctx.fillRect(0, top, drawWidth, rowHeight)
                        scopeView.drawScopeGrid(ctx, top, rowHeight, drawWidth)
                        ctx.fillStyle = scopeView.channelVisible(channel) ? scopeView.channelColors[channel] : scopeView.dimChannelColors[channel]
                        ctx.fillRect(0, top, 4, rowHeight)
                    }
                }

                // Time-ruler baseline (the labels are Text overlays now).
                ctx.strokeStyle = "#1D2B3B"
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(0, drawHeight - 18)
                ctx.lineTo(drawWidth, drawHeight - 18)
                ctx.stroke()
            }
        }

        // Dynamic layer: traces, envelope, hold markers, trigger guide,
        // cursors — over a transparent clear, composited onto the static
        // grid. Threaded render strategy moves the stroke rasterisation (the
        // measured 130-195 ms cost on busy 4-channel content) off the GUI
        // thread, so a slow paint no longer freezes knobs, touch and pages.
        Canvas {
            id: chart
            anchors.fill: gridCanvas
            antialiasing: false
            smooth: false
            renderStrategy: scopeView.threadedTracePaint ? Canvas.Threaded : Canvas.Immediate

            onPaint: {
                var ctx = getContext("2d")
                var drawWidth = width
                var drawHeight = height

                ctx.clearRect(0, 0, drawWidth, drawHeight)
                scopeFrames.notePainted(scopeView.effect)

                if (!scopeView.hasFrame) {
                    return
                }

                var historyFrames = scopeView.processedHistory

                if (scopeView.isXYView) {
                    var xChannel = scopeView.xyStartChannel
                    var yChannel = scopeView.xyStartChannel + 1
                    if (!scopeView.channelVisible(xChannel) || !scopeView.channelVisible(yChannel)) {
                        return   // the "enable both channels" hint is a Text overlay
                    }

                    for (var historyIndex = historyFrames.length - 1; historyIndex >= 0; --historyIndex) {
                        var alpha = scopeView.traceIntensity * Math.pow(0.56, historyIndex)
                        var frame = historyFrames[historyIndex]
                        scopeView.drawXYTrace(
                            ctx,
                            frame[xChannel],
                            frame[yChannel],
                            scopeView.xyPlotLeft,
                            scopeView.xyPlotTop,
                            scopeView.xyPlotSize,
                            scopeView.xyPlotSize,
                            scopeView.channelColors[xChannel],
                            alpha,
                            scopeView.ghostStride(historyIndex)
                        )
                    }
                } else if (scopeView.viewMode === 1) {
                    if (scopeView.channelVisible(scopeView.triggerSource - 1)) {
                        scopeView.drawTriggerGuide(ctx, 0, drawHeight, scopeView.channelColors[Math.max(0, scopeView.triggerSource - 1)], drawWidth)
                    }

                    if (scopeView.showEnvelope) {
                        for (var envelopeChannel = 0; envelopeChannel < 4; ++envelopeChannel) {
                            if (!scopeView.channelVisible(envelopeChannel)) {
                                continue
                            }
                            scopeView.drawScopeEnvelope(
                                ctx,
                                scopeView.historyEnvelope(envelopeChannel),
                                0,
                                drawHeight,
                                scopeView.channelColors[envelopeChannel],
                                scopeView.traceIntensity,
                                drawWidth
                            )
                        }
                    }

                    // HF envelope (v2): min/max extremes recorded at full rate,
                    // drawn dim under the point trace where they diverge.
                    for (var hfChannel = 0; hfChannel < 4; ++hfChannel) {
                        if (!scopeView.hfDetail || !scopeView.hfSignificant[hfChannel]
                                || !scopeView.channelVisible(hfChannel) || !scopeView.hfMin[hfChannel]) {
                            continue
                        }
                        scopeView.drawScopeTrace(ctx, scopeView.hfMin[hfChannel], 0, drawHeight,
                            scopeView.channelColors[hfChannel], scopeView.traceIntensity * 0.35, drawWidth)
                        scopeView.drawScopeTrace(ctx, scopeView.hfMax[hfChannel], 0, drawHeight,
                            scopeView.channelColors[hfChannel], scopeView.traceIntensity * 0.35, drawWidth)
                    }

                    for (historyIndex = historyFrames.length - 1; historyIndex >= 0; --historyIndex) {
                        alpha = scopeView.traceIntensity * Math.pow(0.56, historyIndex)
                        frame = historyFrames[historyIndex]
                        for (var overlayChannel = 0; overlayChannel < 4; ++overlayChannel) {
                            if (!scopeView.channelVisible(overlayChannel)) {
                                continue
                            }
                            scopeView.drawScopeTrace(
                                ctx,
                                frame[overlayChannel],
                                0,
                                drawHeight,
                                scopeView.channelColors[overlayChannel],
                                alpha,
                                drawWidth,
                                scopeView.ghostStride(historyIndex)
                            )
                        }
                    }

                    for (overlayChannel = 0; overlayChannel < 4; ++overlayChannel) {
                        if (!scopeView.channelVisible(overlayChannel)) {
                            continue
                        }
                        scopeView.drawHoldMarkers(ctx, 0, drawHeight, scopeView.holdMarkers[overlayChannel], scopeView.channelColors[overlayChannel], drawWidth, overlayChannel * 16)
                    }
                    scopeView.drawMeasurementCursors(ctx, 0, drawHeight, drawWidth, drawHeight)
                } else {
                    var rowHeight = drawHeight / 4
                    for (var channel = 0; channel < 4; ++channel) {
                        if (!scopeView.channelVisible(channel)) {
                            continue
                        }
                        var top = rowHeight * channel

                        if ((channel + 1) === scopeView.triggerSource) {
                            scopeView.drawTriggerGuide(ctx, top, rowHeight, scopeView.channelColors[channel], drawWidth)
                        }

                        if (scopeView.showEnvelope) {
                            scopeView.drawScopeEnvelope(
                                ctx,
                                scopeView.historyEnvelope(channel),
                                top,
                                rowHeight,
                                scopeView.channelColors[channel],
                                scopeView.traceIntensity,
                                drawWidth
                            )
                        }

                        // HF envelope (v2), dim, under the point trace
                        if (scopeView.hfDetail && scopeView.hfSignificant[channel] && scopeView.hfMin[channel]) {
                            scopeView.drawScopeTrace(ctx, scopeView.hfMin[channel], top, rowHeight,
                                scopeView.channelColors[channel], scopeView.traceIntensity * 0.35, drawWidth)
                            scopeView.drawScopeTrace(ctx, scopeView.hfMax[channel], top, rowHeight,
                                scopeView.channelColors[channel], scopeView.traceIntensity * 0.35, drawWidth)
                        }

                        for (historyIndex = historyFrames.length - 1; historyIndex >= 0; --historyIndex) {
                            alpha = scopeView.traceIntensity * Math.pow(0.56, historyIndex)
                            scopeView.drawScopeTrace(
                                ctx,
                                historyFrames[historyIndex][channel],
                                top,
                                rowHeight,
                                scopeView.channelColors[channel],
                                alpha,
                                drawWidth,
                                scopeView.ghostStride(historyIndex)
                            )
                        }
                        scopeView.drawHoldMarkers(ctx, top, rowHeight, scopeView.holdMarkers[channel], scopeView.channelColors[channel], drawWidth, 0)
                    }
                    scopeView.drawMeasurementCursors(ctx, rowHeight * scopeView.focusChannel, rowHeight, drawWidth, drawHeight)
                }
            }
        }

        MouseArea {
            anchors.fill: chart
            enabled: scopeView.showCursors && !scopeView.isXYView
            preventStealing: true
            onPressed: scopeView.updateSelectedCursorFromPlot(mouse.x, mouse.y, chart.width, chart.height)
            onPositionChanged: {
                if (pressed) {
                    scopeView.updateSelectedCursorFromPlot(mouse.x, mouse.y, chart.width, chart.height)
                }
            }
        }

        // Tap the trace (on the main page) to open the fullscreen viewer.
        MouseArea {
            anchors.fill: chart
            enabled: scopeView.uiPage === "main"
            onClicked: scopeView.openPage("fullscreen")
        }

        // ── Readout overlays ─────────────────────────────────────────
        // Scene-graph Text instead of canvas fillText: glyphs are cached and
        // composited, so the numbers no longer cost a software re-rasterise
        // on every trace frame. They refresh with traceStats (~5 Hz), which
        // also stops the readouts flickering faster than they can be read.
        Item {
            id: chartOverlay
            anchors.fill: gridCanvas

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: !scopeView.hasFrame
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Waiting for notify stream"
                       color: "#7C92AE"; font.family: mainFont.name; font.pixelSize: 26 }
                Text { anchors.horizontalCenter: parent.horizontalCenter
                       text: "Patch a signal into any channel to populate the frame buffer."
                       color: "#7C92AE"; font.family: mainFont.name; font.pixelSize: 18 }
            }

            // XY view: hint when one channel of the pair is hidden
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: scopeView.hasFrame && scopeView.isXYView
                         && !(scopeView.channelVisible(scopeView.xyStartChannel) && scopeView.channelVisible(scopeView.xyStartChannel + 1))
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Enable both channels for XY view"
                       color: "#7C92AE"; font.family: mainFont.name; font.pixelSize: 24 }
                Text { anchors.horizontalCenter: parent.horizontalCenter
                       text: "Current pair: " + scopeView.channelLabels[scopeView.xyStartChannel] + " / " + scopeView.channelLabels[scopeView.xyStartChannel + 1]
                       color: "#7C92AE"; font.family: mainFont.name; font.pixelSize: 18 }
            }

            // STACK view: per-row channel label, frequency, pp/rms
            Repeater {
                model: 4
                delegate: Item {
                    visible: scopeView.hasFrame && !scopeView.isXYView && scopeView.viewMode === 0
                    x: 0
                    y: (chartOverlay.height / 4) * index
                    width: chartOverlay.width
                    height: chartOverlay.height / 4
                    Text { x: 16; y: 6; text: scopeView.channelLabels[index]
                           color: scopeView.channelVisible(index) ? scopeView.channelColors[index] : scopeView.dimChannelColors[index]
                           font.family: mainFont.name; font.pixelSize: 19 }
                    Text { x: 16; y: 30; text: scopeView.formatFrequency(scopeView.channelStats(index).frequency)
                           color: scopeView.channelVisible(index) ? scopeView.channelColors[index] : scopeView.dimChannelColors[index]
                           font.family: mainFont.name; font.pixelSize: 14 }
                    Text { x: parent.width - 98; y: 10; text: "pp " + scopeView.formatMetric(scopeView.channelStats(index).pp)
                           color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 14 }
                    Text { x: parent.width - 108; y: 28; text: "rms " + scopeView.formatMetric(scopeView.channelStats(index).rms)
                           color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 14 }
                    Text { x: parent.width - 64; y: 10; text: "hidden"; visible: !scopeView.channelVisible(index)
                           color: "#546678"; font.family: mainFont.name; font.pixelSize: 16 }
                }
            }

            // OVERLAY view: legend (one line per visible channel)
            Column {
                x: 16
                y: 10
                spacing: 6
                visible: scopeView.hasFrame && scopeView.viewMode === 1
                Repeater {
                    model: 4
                    delegate: Text {
                        visible: scopeView.channelVisible(index)
                        text: scopeView.channelLabels[index] + "  " + scopeView.couplingLabel(index)
                              + "  pp " + scopeView.formatMetric(scopeView.channelStats(index).pp)
                              + "  rms " + scopeView.formatMetric(scopeView.channelStats(index).rms)
                        color: scopeView.channelColors[index]
                        font.family: mainFont.name; font.pixelSize: 15
                    }
                }
            }

            // OVERLAY view: bold floating readout for the SYNC'd channel
            Rectangle {
                property int fch: Math.max(0, Math.min(3, scopeView.triggerSource - 1))
                visible: scopeView.hasFrame && scopeView.viewMode === 1 && scopeView.channelVisible(fch)
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: focusBadgeText.width + 40
                height: 56
                color: "#D1070B10"
                Text {
                    id: focusBadgeText
                    anchors.centerIn: parent
                    text: scopeView.channelLabels[parent.fch]
                          + "    pp " + scopeView.formatMetric(scopeView.channelStats(parent.fch).pp)
                          + "    rms " + scopeView.formatMetric(scopeView.channelStats(parent.fch).rms)
                          + "    " + scopeView.formatFrequency(scopeView.channelStats(parent.fch).frequency)
                    color: scopeView.channelColors[parent.fch]
                    font.family: mainFont.name; font.pixelSize: 36; font.bold: true
                }
            }

            // XY view: big readout panels either side of the square plot
            Column {
                x: 20
                y: scopeView.xyPlotTop + 16
                spacing: 10
                visible: scopeView.hasFrame && scopeView.isXYView
                         && scopeView.channelVisible(scopeView.xyStartChannel) && scopeView.channelVisible(scopeView.xyStartChannel + 1)
                property var st: scopeView.channelStats(scopeView.xyStartChannel)
                Text { text: "X · " + scopeView.channelLabels[scopeView.xyStartChannel]
                       color: scopeView.channelColors[scopeView.xyStartChannel]
                       font.family: mainFont.name; font.pixelSize: 44; font.bold: true }
                Text { text: "pp   " + scopeView.formatMetric(parent.st.pp); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "freq " + scopeView.formatFrequency(parent.st.frequency); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "per  " + (parent.st.frequency > 0 ? scopeView.formatTimeMetric(1000.0 / parent.st.frequency) : "—"); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "rms  " + scopeView.formatMetric(parent.st.rms); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "min " + scopeView.formatMetric(parent.st.minimum); color: "#9fb6cc"; font.family: mainFont.name; font.pixelSize: 32 }
                Text { text: "max " + scopeView.formatMetric(parent.st.maximum); color: "#9fb6cc"; font.family: mainFont.name; font.pixelSize: 32 }
                Text { text: "XY  " + scopeView.channelLabels[scopeView.xyStartChannel] + " / " + scopeView.channelLabels[scopeView.xyStartChannel + 1]
                             + "    corr " + scopeView.xyCorrelation.toFixed(2)
                       color: "#90E7D0"; font.family: mainFont.name; font.pixelSize: 22; font.bold: true }
                Text { text: scopeView.timebaseLabels[scopeView.timebaseIndex] + "  /  "
                             + scopeView.voltsDivLabels[scopeView.voltsDivIndex] + "   ·   persist "
                             + scopeView.persistenceLabels[scopeView.persistenceIndex]
                       color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 16 }
            }
            Column {
                x: scopeView.xyPlotLeft + scopeView.xyPlotSize + 24
                y: scopeView.xyPlotTop + 16
                spacing: 10
                visible: scopeView.hasFrame && scopeView.isXYView
                         && scopeView.channelVisible(scopeView.xyStartChannel) && scopeView.channelVisible(scopeView.xyStartChannel + 1)
                property var st: scopeView.channelStats(scopeView.xyStartChannel + 1)
                Text { text: "Y · " + scopeView.channelLabels[scopeView.xyStartChannel + 1]
                       color: scopeView.channelColors[scopeView.xyStartChannel + 1]
                       font.family: mainFont.name; font.pixelSize: 44; font.bold: true }
                Text { text: "pp   " + scopeView.formatMetric(parent.st.pp); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "freq " + scopeView.formatFrequency(parent.st.frequency); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "per  " + (parent.st.frequency > 0 ? scopeView.formatTimeMetric(1000.0 / parent.st.frequency) : "—"); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "rms  " + scopeView.formatMetric(parent.st.rms); color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 40 }
                Text { text: "min " + scopeView.formatMetric(parent.st.minimum); color: "#9fb6cc"; font.family: mainFont.name; font.pixelSize: 32 }
                Text { text: "max " + scopeView.formatMetric(parent.st.maximum); color: "#9fb6cc"; font.family: mainFont.name; font.pixelSize: 32 }
            }

            // Time ruler labels + frame info (non-XY views)
            Text { x: 10; y: parent.height - 19; text: "0"; visible: scopeView.hasFrame && !scopeView.isXYView
                   color: "#607286"; font.family: mainFont.name; font.pixelSize: 16 }
            Text { x: parent.width * 0.5 - 26; y: parent.height - 19
                   text: (scopeView.visibleWindowMs() * 0.5).toFixed(1) + " ms"
                   visible: scopeView.hasFrame && !scopeView.isXYView
                   color: "#607286"; font.family: mainFont.name; font.pixelSize: 16 }
            Text { x: parent.width - 62; y: parent.height - 19
                   text: scopeView.visibleWindowMs().toFixed(1) + " ms"
                   visible: scopeView.hasFrame && !scopeView.isXYView
                   color: "#607286"; font.family: mainFont.name; font.pixelSize: 16 }
            Text { x: 10; y: parent.height - 36
                   text: scopeView.frameSampleCount + " pts"
                   visible: scopeView.hasFrame && !scopeView.isXYView && scopeView.frameSampleCount > 0
                   color: "#4D657B"; font.family: mainFont.name; font.pixelSize: 14 }
            Text { anchors.right: parent.right; anchors.rightMargin: 8; y: parent.height - 36
                   text: scopeView.refreshHzEstimate.toFixed(1) + " Hz"
                   visible: scopeView.hasFrame && !scopeView.isXYView && scopeView.refreshHzEstimate > 0.0
                   color: "#4D657B"; font.family: mainFont.name; font.pixelSize: 14 }
        }

    }

    // ── Bottom control bar (main page) ──────────────────────────────
    Row {
        id: bottomBar
        x: 16
        y: scopeView.height - 74
        height: 62
        spacing: 8
        visible: scopeView.uiPage === "main"

        Rectangle {
            width: 124; height: 62; radius: 10
            color: scopeView.freeze ? "#24374C" : "#16302a"
            border.color: scopeView.freeze ? "#FFD166" : "#4a9"; border.width: 1
            Text { anchors.centerIn: parent; text: scopeView.freeze ? "FREEZE" : "RUN"
                   color: scopeView.freeze ? "#FFD166" : "#9fe7d0"; font.family: mainFont.name
                   font.pixelSize: 23; font.capitalization: Font.AllUppercase }
            MouseArea { anchors.fill: parent; onClicked: scopeView.toggleFreeze() }
        }
        Rectangle {
            width: 108; height: 62; radius: 10; color: "#13212E"; border.color: "#284055"; border.width: 1
            Text { anchors.centerIn: parent; text: "CLEAR"; color: "#D7E6F5"; font.family: mainFont.name
                   font.pixelSize: 20; font.capitalization: Font.AllUppercase }
            MouseArea { anchors.fill: parent; onClicked: scopeView.clearTraces() }
        }
        Rectangle {
            width: 250; height: 62; radius: 10; color: "#0e1a25"; border.color: "#284055"; border.width: 1
            Row {
                anchors.fill: parent; anchors.margins: 5; spacing: 6
                Rectangle { width: 56; height: 52; radius: 8; color: "#13212E"; border.color: "#355"; border.width: 1
                    Text { anchors.centerIn: parent; text: "−"; color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 30 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.stepTimebase(-1) } }
                Column { width: 116; anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "TIME"
                           color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter
                           text: scopeView.timebaseLabels[scopeView.timebaseIndex]; color: "#cfe"
                           font.family: mainFont.name; font.pixelSize: 22 } }
                Rectangle { width: 56; height: 52; radius: 8; color: "#13212E"; border.color: "#355"; border.width: 1
                    Text { anchors.centerIn: parent; text: "+"; color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 30 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.stepTimebase(1) } }
            }
        }
        Rectangle {
            width: 250; height: 62; radius: 10; color: "#0e1a25"; border.color: "#284055"; border.width: 1
            Row {
                anchors.fill: parent; anchors.margins: 5; spacing: 6
                Rectangle { width: 56; height: 52; radius: 8; color: "#13212E"; border.color: "#355"; border.width: 1
                    Text { anchors.centerIn: parent; text: "−"; color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 30 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.stepVoltsDiv(-1) } }
                Column { width: 116; anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "SCALE"
                           color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter
                           text: scopeView.voltsDivLabels[scopeView.voltsDivIndex]; color: "#cfe"
                           font.family: mainFont.name; font.pixelSize: 22 } }
                Rectangle { width: 56; height: 52; radius: 8; color: "#13212E"; border.color: "#355"; border.width: 1
                    Text { anchors.centerIn: parent; text: "+"; color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 30 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.stepVoltsDiv(1) } }
            }
        }
        Rectangle {
            width: 322; height: 62; radius: 10; color: "#0e1a25"; border.color: "#284055"; border.width: 1
            Row {
                anchors.fill: parent; anchors.margins: 4; spacing: 0
                Repeater {
                    model: ["STACK","OVR","XY12","XY34"]
                    delegate: Rectangle {
                        width: 62; height: 54; radius: 7
                        color: scopeView.viewMode === index ? "#24374C" : "transparent"
                        Text { anchors.centerIn: parent; text: modelData
                               color: scopeView.viewMode === index ? "#90E7D0" : "#D7E6F5"
                               font.family: mainFont.name; font.pixelSize: 16; font.capitalization: Font.AllUppercase }
                        MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("view_mode", index) }
                    }
                }
                // Not a view_mode value: the tuner is its own page, so the
                // plugin's view_mode port range stays as it is.
                Rectangle {
                    width: 62; height: 54; radius: 7; color: "transparent"
                    border.color: "#355"; border.width: 1
                    Text { anchors.centerIn: parent; text: "TUNE"; color: "#D7E6F5"
                           font.family: mainFont.name; font.pixelSize: 16; font.capitalization: Font.AllUppercase }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.openPage("tuner") }
                }
            }
        }
        Rectangle {
            width: 120; height: 62; radius: 10; color: "#13212E"; border.color: "#284055"; border.width: 1
            Text { anchors.centerIn: parent; text: "SETUP ▸"; color: "#D7E6F5"; font.family: mainFont.name
                   font.pixelSize: 19; font.capitalization: Font.AllUppercase }
            MouseArea { anchors.fill: parent; onClicked: scopeView.openPage("setup") }
        }
    }

    // ── Wide channel column (main page) ─────────────────────────────
    Column {
        id: channelColumn
        x: scopeView.width - 156
        y: 12
        width: 144
        spacing: 8
        visible: scopeView.uiPage === "main"
        Repeater {
            model: 4
            delegate: Rectangle {
                width: 144
                height: (scopeView.height - 12 - 74 - 12 - 3 * 8) / 4
                radius: 8
                color: scopeView.channelVisible(index) ? "#11231d" : "#13212E"
                border.width: 1
                border.color: scopeView.channelVisible(index) ? scopeView.channelColors[index] : "#284055"
                Column {
                    anchors.fill: parent; anchors.margins: 8; spacing: 5
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter
                           text: "CH" + (index + 1); color: scopeView.channelColors[index]
                           font.family: mainFont.name; font.pixelSize: 19; font.bold: true }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter
                           text: "IN" + (index + 1) + " · THRU" + (index + 1); color: "#8fb"
                           font.family: mainFont.name; font.pixelSize: 10; font.capitalization: Font.AllUppercase }
                    Row {
                        width: parent.width; spacing: 6
                        Rectangle { width: (parent.width - 6) / 2; height: 30; radius: 6
                            color: scopeView.channelVisible(index) ? "#24374C" : "#13212E"
                            border.color: scopeView.channelVisible(index) ? scopeView.channelColors[index] : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: scopeView.channelVisible(index) ? "ON" : "OFF"
                                   color: scopeView.channelVisible(index) ? scopeView.channelColors[index] : "#7e93a8"
                                   font.family: mainFont.name; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.toggleChannelVisible(index) } }
                        Rectangle { width: (parent.width - 6) / 2; height: 30; radius: 6
                            color: (scopeView.triggerSource === index + 1) ? "#2a3a26" : "#13212E"
                            border.color: (scopeView.triggerSource === index + 1) ? "#9be77a" : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: "SYNC"
                                   color: (scopeView.triggerSource === index + 1) ? "#9be77a" : "#7e93a8"
                                   font.family: mainFont.name; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("trigger_source", index + 1) } }
                    }
                    Rectangle { width: parent.width; height: 30; radius: 6; color: "#13212E"; border.color: "#284055"; border.width: 1
                        Text { anchors.centerIn: parent; text: "OPTIONS ▸"; color: "#9fb6cc"
                               font.family: mainFont.name; font.pixelSize: 13; font.capitalization: Font.AllUppercase }
                        MouseArea { anchors.fill: parent; onClicked: scopeView.openChannel(index) } }
                }
            }
        }
    }



    // ── SETUP sub-page ──────────────────────────────────────────────
    Item {
        id: setupPage
        anchors.fill: parent
        visible: scopeView.uiPage === "setup"

        Rectangle { anchors.fill: parent; color: "#080C11" }

        Rectangle {
            x: 16; y: 14; width: 190; height: 64; radius: 10; color: "#13212E"; border.color: "#284055"; border.width: 1
            Text { anchors.centerIn: parent; text: "‹ BACK"; color: "#D7E6F5"; font.family: mainFont.name
                   font.pixelSize: 26; font.capitalization: Font.AllUppercase }
            MouseArea { anchors.fill: parent; onClicked: scopeView.backToMain() }
        }
        Text { x: 230; y: 30; text: "SETUP"; color: "#90E7D0"; font.family: mainFont.name
               font.pixelSize: 26; font.capitalization: Font.AllUppercase }

        Column {
            x: 24; y: 100; width: 580; spacing: 18
            Column { spacing: 6
                Text { text: "TRIGGER MODE"; color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                Row { spacing: 6
                    Repeater { model: scopeView.triggerModeLabels
                        delegate: Rectangle { width: 120; height: 44; radius: 8
                            color: scopeView.triggerMode === index ? "#24374C" : "#13212E"
                            border.color: scopeView.triggerMode === index ? "#90E7D0" : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: modelData
                                   color: scopeView.triggerMode === index ? "#90E7D0" : "#D7E6F5"
                                   font.family: mainFont.name; font.pixelSize: 16 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("trigger_mode", index) } } }
                }
            }
            Column { spacing: 6
                Text { text: "TRIGGER SOURCE"; color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                Row { spacing: 6
                    Repeater { model: 4
                        delegate: Rectangle { width: 90; height: 44; radius: 8
                            color: scopeView.triggerSource === index + 1 ? "#24374C" : "#13212E"
                            border.color: scopeView.triggerSource === index + 1 ? scopeView.channelColors[index] : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: "CH" + (index + 1)
                                   color: scopeView.triggerSource === index + 1 ? scopeView.channelColors[index] : "#D7E6F5"
                                   font.family: mainFont.name; font.pixelSize: 16 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("trigger_source", index + 1) } } }
                }
            }
            Column { spacing: 6
                Row { spacing: 14
                    Text { text: "TRIGGER LEVEL   " + scopeView.triggerLevel.toFixed(2); color: "#7e93a8"
                           font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase
                           anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 92; height: 34; radius: 8
                        color: scopeView.autoTrigger ? "#24374C" : "#13212E"
                        border.color: scopeView.autoTrigger ? "#9be77a" : "#284055"; border.width: 1
                        Text { anchors.centerIn: parent; text: scopeView.autoTrigger ? "AUTO ✓" : "AUTO"
                               color: scopeView.autoTrigger ? "#9be77a" : "#D7E6F5"
                               font.family: mainFont.name; font.pixelSize: 15; font.capitalization: Font.AllUppercase }
                        MouseArea { anchors.fill: parent; onClicked: scopeView.autoTrigger = !scopeView.autoTrigger } }
                }
                Slider { width: 560; from: -1.0; to: 1.0; value: scopeView.triggerLevel
                    enabled: !scopeView.autoTrigger
                    opacity: scopeView.autoTrigger ? 0.45 : 1.0
                    onMoved: knobs.ui_knob_change(scopeView.effect, "trigger_level", value) }
            }
            Column { spacing: 6
                Text { text: "TRIGGER HOLDOFF (ms) — ignore further edges after a trigger"; color: "#7e93a8"
                       font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                Row { spacing: 6
                    Repeater { model: scopeView.holdoffLabels
                        delegate: Rectangle { width: 51; height: 44; radius: 8
                            color: scopeView.holdoffIndex === index ? "#24374C" : "#13212E"
                            border.color: scopeView.holdoffIndex === index ? "#90E7D0" : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: modelData
                                   color: scopeView.holdoffIndex === index ? "#90E7D0" : "#D7E6F5"
                                   font.family: mainFont.name; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("holdoff", scopeView.holdoffValues[index]) } } }
                }
            }
        }

        Column {
            x: 650; y: 100; width: 580; spacing: 18
            Column { spacing: 6
                Text { text: "PERSISTENCE"; color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                Row { spacing: 6
                    Repeater { model: scopeView.persistenceLabels
                        delegate: Rectangle { width: 100; height: 44; radius: 8
                            color: scopeView.persistenceIndex === index ? "#24374C" : "#13212E"
                            border.color: scopeView.persistenceIndex === index ? "#90E7D0" : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: modelData
                                   color: scopeView.persistenceIndex === index ? "#90E7D0" : "#D7E6F5"
                                   font.family: mainFont.name; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("persistence", index) } } }
                }
            }
            Column { spacing: 6
                Text { text: "INTENSITY"; color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                Row { spacing: 6
                    Repeater { model: scopeView.intensityLabels
                        delegate: Rectangle { width: 100; height: 44; radius: 8
                            color: scopeView.intensityIndex === index ? "#24374C" : "#13212E"
                            border.color: scopeView.intensityIndex === index ? "#90E7D0" : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: modelData
                                   color: scopeView.intensityIndex === index ? "#90E7D0" : "#D7E6F5"
                                   font.family: mainFont.name; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("intensity", index) } } }
                }
            }
            Column { spacing: 6
                Text { text: "HF DETAIL — min/max envelope for under-sampled signals"; color: "#7e93a8"
                       font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                Rectangle { width: 130; height: 44; radius: 8
                    color: scopeView.hfDetail ? "#24374C" : "#13212E"
                    border.color: scopeView.hfDetail ? "#90E7D0" : "#284055"; border.width: 1
                    Text { anchors.centerIn: parent; text: scopeView.hfDetail ? "ON" : "OFF"
                           color: scopeView.hfDetail ? "#90E7D0" : "#D7E6F5"
                           font.family: mainFont.name; font.pixelSize: 16 }
                    MouseArea { anchors.fill: parent
                        onClicked: { scopeView.hfDetail = !scopeView.hfDetail; scopeView.requestRender() } }
                }
            }
            Rectangle { width: 200; height: 48; radius: 8; color: "#13212E"; border.color: "#90E7D0"; border.width: 1
                Text { anchors.centerIn: parent; text: "AUTOSET"; color: "#90E7D0"; font.family: mainFont.name
                       font.pixelSize: 16; font.capitalization: Font.AllUppercase }
                MouseArea { anchors.fill: parent; onClicked: scopeView.autosetScope() }
            }
        }

        Text { x: 24; y: parent.height - 30; text: "polyscope " + scopeView.scopeBuild
               color: "#5f7387"; font.family: mainFont.name; font.pixelSize: 13 }
    }


    // ── Per-channel sub-page ────────────────────────────────────────
    Item {
        id: channelPage
        anchors.fill: parent
        visible: scopeView.uiPage === "channel"
        property int ch: scopeView.activeChannel
        property var st: scopeView.channelStats(channelPage.ch)
        property color chColor: scopeView.channelColors[channelPage.ch]

        Rectangle { anchors.fill: parent; color: "#080C11" }
        // accent strip in the channel colour
        Rectangle { x: 0; y: 0; width: parent.width; height: 4; color: channelPage.chColor }

        Rectangle {
            x: 16; y: 16; width: 190; height: 64; radius: 10; color: "#13212E"; border.color: "#284055"; border.width: 1
            Text { anchors.centerIn: parent; text: "‹ BACK"; color: "#D7E6F5"; font.family: mainFont.name
                   font.pixelSize: 26; font.capitalization: Font.AllUppercase }
            MouseArea { anchors.fill: parent; onClicked: scopeView.backToMain() }
        }
        Text { x: 230; y: 30
               text: "CHANNEL " + (channelPage.ch + 1) + "   ·   IN" + (channelPage.ch + 1) + "   ·   THRU" + (channelPage.ch + 1)
               color: channelPage.chColor; font.family: mainFont.name; font.pixelSize: 24; font.capitalization: Font.AllUppercase }

        // Left: controls
        Column {
            x: 24; y: 100; spacing: 16
            Rectangle { width: 300; height: 64; radius: 10
                color: scopeView.channelVisible(channelPage.ch) ? "#24374C" : "#13212E"
                border.color: scopeView.channelVisible(channelPage.ch) ? channelPage.chColor : "#284055"; border.width: 1
                Text { anchors.centerIn: parent; text: scopeView.channelVisible(channelPage.ch) ? "CHANNEL ON" : "CHANNEL OFF"
                       color: scopeView.channelVisible(channelPage.ch) ? channelPage.chColor : "#7e93a8"
                       font.family: mainFont.name; font.pixelSize: 20; font.capitalization: Font.AllUppercase }
                MouseArea { anchors.fill: parent; onClicked: scopeView.toggleChannelVisible(channelPage.ch) } }
            Column { spacing: 8
                Text { text: "COUPLING"; color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 15; font.capitalization: Font.AllUppercase }
                Row { spacing: 10
                    Repeater { model: ["DC","AC"]
                        delegate: Rectangle { width: 145; height: 64; radius: 10
                            color: scopeView.couplingMode(channelPage.ch) === index ? "#24374C" : "#13212E"
                            border.color: scopeView.couplingMode(channelPage.ch) === index ? "#90E7D0" : "#284055"; border.width: 1
                            Text { anchors.centerIn: parent; text: modelData
                                   color: scopeView.couplingMode(channelPage.ch) === index ? "#90E7D0" : "#D7E6F5"
                                   font.family: mainFont.name; font.pixelSize: 22 }
                            MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("coupling_" + (channelPage.ch + 1), index) } } }
                }
            }
            Rectangle { width: 300; height: 56; radius: 10
                color: (scopeView.triggerSource === channelPage.ch + 1) ? "#2a3a26" : "#13212E"
                border.color: (scopeView.triggerSource === channelPage.ch + 1) ? "#9be77a" : "#284055"; border.width: 1
                Text { anchors.centerIn: parent
                       text: (scopeView.triggerSource === channelPage.ch + 1) ? "TRIGGER SOURCE ✓" : "SET AS TRIGGER"
                       color: (scopeView.triggerSource === channelPage.ch + 1) ? "#9be77a" : "#D7E6F5"
                       font.family: mainFont.name; font.pixelSize: 17; font.capitalization: Font.AllUppercase }
                MouseArea { anchors.fill: parent; onClicked: scopeView.setIntControl("trigger_source", channelPage.ch + 1) } }
        }

        // Right: styled measurement cards
        Grid {
            x: 372; y: 100; columns: 2; columnSpacing: 16; rowSpacing: 16
            Repeater {
                model: [
                    ["PP", scopeView.formatMetric(channelPage.st.pp)],
                    ["RMS", scopeView.formatMetric(channelPage.st.rms)],
                    ["FREQ", scopeView.formatFrequency(channelPage.st.frequency)],
                    ["PERIOD", channelPage.st.frequency > 0 ? scopeView.formatTimeMetric(1000.0 / channelPage.st.frequency) : "—"],
                    ["MIN", scopeView.formatMetric(channelPage.st.minimum)],
                    ["MAX", scopeView.formatMetric(channelPage.st.maximum)]
                ]
                delegate: Rectangle {
                    width: 280; height: 96; radius: 10; color: "#0E1822"
                    border.color: "#223140"; border.width: 1
                    Rectangle { x: 0; y: 0; width: 4; height: parent.height; color: channelPage.chColor }
                    Column {
                        x: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { text: modelData[0]; color: "#7e93a8"; font.family: mainFont.name
                               font.pixelSize: 16; font.capitalization: Font.AllUppercase }
                        Text { text: modelData[1]; color: "#FFFFFF"; font.family: mainFont.name; font.pixelSize: 34 }
                    }
                }
            }
        }
    }


    // ── Tuner sub-page ──────────────────────────────────────────────
    Item {
        id: tunerPage
        anchors.fill: parent
        visible: scopeView.uiPage === "tuner"
        property int ch: scopeView.tunerChannel
        property real hz: scopeView.pluginFreqs.length > ch ? scopeView.pluginFreqs[ch] : 0.0
        property bool valid: scopeView.tunerValid(hz)
        property real cents: scopeView.tunerCents(hz)
        property bool inTune: valid && Math.abs(cents) <= scopeView.tunerInTuneCents
        property color chColor: scopeView.channelColors[ch]

        Rectangle { anchors.fill: parent; color: "#080C11" }
        Rectangle { x: 0; y: 0; width: parent.width; height: 4; color: tunerPage.chColor }

        Rectangle {
            x: 16; y: 16; width: 190; height: 64; radius: 10; color: "#13212E"; border.color: "#284055"; border.width: 1
            Text { anchors.centerIn: parent; text: "‹ BACK"; color: "#D7E6F5"; font.family: mainFont.name
                   font.pixelSize: 26; font.capitalization: Font.AllUppercase }
            MouseArea { anchors.fill: parent; onClicked: scopeView.backToMain() }
        }
        Text { x: 230; y: 32; text: "TUNER"; color: "#90E7D0"; font.family: mainFont.name
               font.pixelSize: 26; font.capitalization: Font.AllUppercase }

        // reference pitch
        Rectangle {
            x: tunerPanel.x + tunerPanel.width - width; y: 16; width: 330; height: 64; radius: 10
            color: "#0e1a25"; border.color: "#284055"; border.width: 1
            Row {
                anchors.fill: parent; anchors.margins: 6; spacing: 6
                Rectangle { width: 64; height: 52; radius: 8; color: "#13212E"; border.color: "#355"; border.width: 1
                    Text { anchors.centerIn: parent; text: "−"; color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 30 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.stepTunerA4(-1.0) } }
                Column { width: 178; anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "REFERENCE"
                           color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 14; font.capitalization: Font.AllUppercase }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter
                           text: "A4 = " + scopeView.tunerA4.toFixed(0) + " Hz"; color: "#cfe"
                           font.family: mainFont.name; font.pixelSize: 22 } }
                Rectangle { width: 64; height: 52; radius: 8; color: "#13212E"; border.color: "#355"; border.width: 1
                    Text { anchors.centerIn: parent; text: "+"; color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 30 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.stepTunerA4(1.0) } }
            }
            MouseArea { x: 76; width: 178; height: parent.height; onDoubleClicked: scopeView.tunerA4 = 440.0 }
        }

        // ── main readout for the selected channel ──
        Rectangle {
            id: tunerPanel
            x: 16; y: 96
            width: parent.width - 16 - 12 - 200 - 16
            height: parent.height - 96 - 16
            radius: 12; color: "#0D141D"
            border.color: tunerPage.inTune ? "#9be77a" : "#223140"; border.width: tunerPage.inTune ? 2 : 1

            Text {
                id: noteText
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                text: scopeView.tunerNoteName(tunerPage.hz)
                color: !tunerPage.valid ? "#3d4f61" : (tunerPage.inTune ? "#9be77a" : "#D7E6F5")
                font.family: mainFont.name; font.pixelSize: 190; font.bold: true
            }

            // cents meter, −50 … +50
            Item {
                id: meter
                x: 48; y: 250
                width: parent.width - 96; height: 96
                property real centerX: width / 2

                // in-tune zone
                Rectangle {
                    x: meter.centerX - (scopeView.tunerInTuneCents / 50.0) * meter.centerX
                    width: (scopeView.tunerInTuneCents / 50.0) * meter.width
                    y: 0; height: meter.height; radius: 4
                    color: tunerPage.inTune ? "#2a4a2a" : "#15241c"
                }
                // baseline
                Rectangle { x: 0; y: meter.height / 2 - 1; width: meter.width; height: 2; color: "#284055" }
                // ticks every 10 cents
                Repeater {
                    model: 11
                    delegate: Rectangle {
                        property int c: -50 + index * 10
                        width: c === 0 ? 4 : 2
                        height: c === 0 ? meter.height : (c % 50 === 0 ? 56 : 32)
                        x: meter.centerX + (c / 50.0) * meter.centerX - width / 2
                        y: (meter.height - height) / 2
                        color: c === 0 ? "#7e93a8" : "#355"
                    }
                }
                Text { x: 0; y: meter.height + 4; text: "−50"; color: "#546678"; font.family: mainFont.name; font.pixelSize: 16 }
                Text { x: meter.width - width; y: meter.height + 4; text: "+50"; color: "#546678"; font.family: mainFont.name; font.pixelSize: 16 }
                Text { x: meter.centerX - width / 2; y: meter.height + 4; text: "0"; color: "#546678"; font.family: mainFont.name; font.pixelSize: 16 }

                // marker
                Rectangle {
                    visible: tunerPage.valid
                    width: 10; height: meter.height + 12; radius: 3
                    y: -6
                    x: meter.centerX + (Math.max(-50.0, Math.min(50.0, tunerPage.cents)) / 50.0) * meter.centerX - width / 2
                    color: tunerPage.inTune ? "#9be77a" : tunerPage.chColor
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: meter.y + meter.height + 44
                spacing: 48
                visible: tunerPage.valid
                Text { text: scopeView.formatCents(tunerPage.cents)
                       color: tunerPage.inTune ? "#9be77a" : "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 34 }
                Text { text: tunerPage.hz.toFixed(2) + " Hz"; color: "#D7E6F5"; font.family: mainFont.name; font.pixelSize: 34 }
                Text { y: 9; text: "target " + scopeView.tunerTargetHz(tunerPage.hz).toFixed(2) + " Hz"
                       color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 22 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: meter.y + meter.height + 44
                visible: !tunerPage.valid
                text: scopeView.freeze ? "The scope is frozen. Tap RUN to measure again."
                                       : "No pitch on " + scopeView.channelLabels[tunerPage.ch] + ". Patch an oscillator into it."
                color: "#7e93a8"; font.family: mainFont.name; font.pixelSize: 24
            }
            Rectangle {
                visible: scopeView.freeze
                anchors.horizontalCenter: parent.horizontalCenter
                y: meter.y + meter.height + 88; width: 160; height: 52; radius: 10
                color: "#24374C"; border.color: "#FFD166"; border.width: 1
                Text { anchors.centerIn: parent; text: "RUN"; color: "#FFD166"; font.family: mainFont.name
                       font.pixelSize: 22; font.capitalization: Font.AllUppercase }
                MouseArea { anchors.fill: parent; onClicked: scopeView.toggleFreeze() }
            }
        }

        // ── all four channels; tap one to show it above ──
        Column {
            x: scopeView.width - 200 - 16; y: 96; width: 200; spacing: 8
            Repeater {
                model: 4
                delegate: Rectangle {
                    property real hz: scopeView.pluginFreqs.length > index ? scopeView.pluginFreqs[index] : 0.0
                    property bool valid: scopeView.tunerValid(hz)
                    property real cents: scopeView.tunerCents(hz)
                    property bool inTune: valid && Math.abs(cents) <= scopeView.tunerInTuneCents
                    property bool selected: scopeView.tunerChannel === index
                    width: 200
                    height: (scopeView.height - 96 - 16 - 3 * 8) / 4
                    radius: 8
                    color: selected ? "#24374C" : "#13212E"
                    border.color: selected ? scopeView.channelColors[index] : "#284055"
                    border.width: selected ? 2 : 1
                    Text { x: 12; y: 10; text: scopeView.channelLabels[index]; color: scopeView.channelColors[index]
                           font.family: mainFont.name; font.pixelSize: 17; font.bold: true }
                    Text { x: 12; y: 40; text: scopeView.tunerNoteName(parent.hz)
                           color: !parent.valid ? "#3d4f61" : (parent.inTune ? "#9be77a" : "#D7E6F5")
                           font.family: mainFont.name; font.pixelSize: 40; font.bold: true }
                    Text { anchors.right: parent.right; anchors.rightMargin: 12; y: 10
                           visible: parent.valid; text: scopeView.formatCents(parent.cents)
                           color: parent.inTune ? "#9be77a" : "#9fb6cc"; font.family: mainFont.name; font.pixelSize: 17 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.tunerChannel = index }
                }
            }
        }
    }


    // ── Fullscreen trace viewer ─────────────────────────────────────
    Item {
        id: fullscreenPage
        anchors.fill: parent
        visible: scopeView.uiPage === "fullscreen"

        Rectangle {
            x: 12; y: 10; width: 180; height: 60; radius: 10; color: "#13212E"; border.color: "#284055"; border.width: 1; z: 5
            Text { anchors.centerIn: parent; text: "‹ BACK"; color: "#D7E6F5"; font.family: mainFont.name
                   font.pixelSize: 24; font.capitalization: Font.AllUppercase }
            MouseArea { anchors.fill: parent; onClicked: scopeView.backToMain() }
        }

        Column {
            x: scopeView.width - 112; y: 10; width: 104; spacing: 6
            Repeater {
                model: 4
                delegate: Rectangle {
                    width: 104; height: 64; radius: 6; visible: scopeView.channelVisible(index)
                    color: "#11231d"; border.color: scopeView.channelColors[index]; border.width: 1
                    Column {
                        anchors.fill: parent; anchors.margins: 6; spacing: 1
                        Text { text: "CH" + (index + 1); color: scopeView.channelColors[index]
                               font.family: mainFont.name; font.pixelSize: 13; font.bold: true }
                        Text { text: "pp " + scopeView.formatMetric(scopeView.channelStats(index).pp); color: "#cfe"
                               font.family: mainFont.name; font.pixelSize: 11 }
                        Text { text: scopeView.formatFrequency(scopeView.channelStats(index).frequency); color: "#cfe"
                               font.family: mainFont.name; font.pixelSize: 11 }
                    }
                }
            }
            Rectangle {
                width: 104; height: 40; radius: 6
                color: scopeView.showCursors ? "#24374C" : "#13212E"
                border.color: scopeView.showCursors ? "#90E7D0" : "#284055"; border.width: 1
                Text { anchors.centerIn: parent; text: scopeView.showCursors ? "CURSORS ON" : "CURSORS"
                       color: scopeView.showCursors ? "#90E7D0" : "#D7E6F5"
                       font.family: mainFont.name; font.pixelSize: 12; font.capitalization: Font.AllUppercase }
                MouseArea { anchors.fill: parent; onClicked: scopeView.showCursors = !scopeView.showCursors }
            }
            Row {
                spacing: 5; visible: scopeView.showCursors
                Rectangle { width: 49; height: 34; radius: 6
                    color: scopeView.selectedCursor === 0 ? "#24374C" : "#13212E"
                    border.color: scopeView.selectedCursor === 0 ? "#90E7D0" : "#284055"; border.width: 1
                    Text { anchors.centerIn: parent; text: "A"; color: scopeView.selectedCursor === 0 ? "#90E7D0" : "#D7E6F5"
                           font.family: mainFont.name; font.pixelSize: 14 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.selectedCursor = 0 } }
                Rectangle { width: 49; height: 34; radius: 6
                    color: scopeView.selectedCursor === 1 ? "#24374C" : "#13212E"
                    border.color: scopeView.selectedCursor === 1 ? "#90E7D0" : "#284055"; border.width: 1
                    Text { anchors.centerIn: parent; text: "B"; color: scopeView.selectedCursor === 1 ? "#90E7D0" : "#D7E6F5"
                           font.family: mainFont.name; font.pixelSize: 14 }
                    MouseArea { anchors.fill: parent; onClicked: scopeView.selectedCursor = 1 } }
            }
        }
    }

}