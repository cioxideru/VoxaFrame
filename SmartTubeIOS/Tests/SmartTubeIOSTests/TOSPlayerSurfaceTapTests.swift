#if !os(tvOS)
import JavaScriptCore
import Testing

@testable import SmartTubeIOS

/// Execute the production injected script against a small DOM/event fixture.
/// The downstream listener represents YouTube's surface-to-playback handler.
@Suite("TOS player surface taps")
struct TOSPlayerSurfaceTapTests {
    private func context() throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript(Self.fixture)
        context.evaluateScript(TOSPlayerSurfaceTapScript.source)
        #expect(context.exception == nil)
        return context
    }

    @Test("Surface clicks show/hide controls without toggling playing or paused video", arguments: [false, true])
    func surfaceClicks(paused: Bool) throws {
        let js = try context()
        js.evaluateScript("video.paused = \(paused); fire('click', video); fire('click', video);")
        #expect(js.evaluateScript("video.paused")?.toBool() == paused)
        #expect(js.evaluateScript("messages.map(m => m.controlsVisible).join(',')")?.toString() == "true,false")
        #expect(js.evaluateScript("downstreamCalls")?.toInt32() == 0)
    }

    @Test("Touch taps cancel delivery to the embed and suppress synthesized clicks")
    func touchTap() throws {
        let js = try context()
        js.evaluateScript("fire('touchstart', video); var end = fire('touchend', video);")
        #expect(js.evaluateScript("end.defaultPrevented && end.stopped")?.toBool() == true)
        #expect(js.evaluateScript("messages.length")?.toInt32() == 1)
        #expect(js.evaluateScript("video.paused")?.toBool() == false)
    }

    @Test("Actual controls remain interactive", arguments: ["playButton", "scrubber", "menu", "link", "replay"])
    func controlsPassThrough(target: String) throws {
        let js = try context()
        js.evaluateScript("fire('click', \(target));")
        #expect(js.evaluateScript("downstreamCalls")?.toInt32() == 1)
        #expect(js.evaluateScript("messages.length")?.toInt32() == 0)
        if target == "playButton" {
            #expect(js.evaluateScript("video.paused")?.toBool() == true)
            js.evaluateScript("fire('click', video);")
            #expect(js.evaluateScript("video.paused")?.toBool() == true)
        }
    }

    @Test("Drags returning to their origin and cancelled touches are not taps")
    func dragsAndCancellation() throws {
        let js = try context()
        js.evaluateScript(
            """
            fire('touchstart', video);
            fire('touchmove', video, 90);
            fire('touchmove', video, 0);
            var dragEnd = fire('touchend', video);
            fire('touchstart', video);
            fire('touchcancel', video);
            var cancelledEnd = fire('touchend', video);
            """)
        #expect(js.evaluateScript("messages.length")?.toInt32() == 0)
        #expect(js.evaluateScript("dragEnd.defaultPrevented || cancelledEnd.defaultPrevented")?.toBool() == false)
    }

    @Test("Multitouch and non-cancellable touch events pass through")
    func multipleTouches() throws {
        let js = try context()
        js.evaluateScript(
            """
            fire('touchstart', video);
            fire('touchstart', video, 0, 2);
            fire('touchend', video);
            fire('touchstart', video);
            fire('touchend', video, 0, 1, false);
            """)
        #expect(js.evaluateScript("messages.length")?.toInt32() == 0)
    }

    @Test(
        "Unready, ended, fullscreen and unsupported players retain native behavior",
        arguments: [
            "video.readyState = 0", "video.ended = true", "document.fullscreenElement = video",
            "player.hideControls = undefined", "player.showControls = undefined", "player = null",
        ])
    func unsupportedPlayer(setup: String) throws {
        let js = try context()
        js.evaluateScript("\(setup); fire('click', video);")
        #expect(js.evaluateScript("downstreamCalls")?.toInt32() == 1)
        #expect(js.evaluateScript("messages.length")?.toInt32() == 0)
        #expect(js.exception == nil)
    }

    @Test(
        "Recorded iPad overlay surfaces toggle controls without changing playback",
        arguments: ["mobileBackground", "mobileMiddle", "mobile", "video"])
    func mobileSurfaceClicks(target: String) throws {
        let js = try context()
        js.evaluateScript("enableMobile(); fire('touchstart', \(target)); var end = fire('touchend', \(target));")
        // YouTube must finish its touch cleanup before we consume the click.
        #expect(js.evaluateScript("end.stopped")?.toBool() == false)
        js.evaluateScript("fire('click', \(target)); fire('click', \(target));")
        #expect(js.evaluateScript("video.paused")?.toBool() == false)
        #expect(js.evaluateScript("messages.map(m => m.controlsVisible).join(',')")?.toString() == "false,true")
        #expect(js.evaluateScript("mobile.classList.contains('fadein')")?.toBool() == true)
        #expect(js.exception == nil)
    }

    @Test("Mobile controls remain usable and deliberate pauses survive surface taps")
    func mobileButtons() throws {
        let js = try context()
        js.evaluateScript("enableMobile(); fire('click', playButton); fire('click', mobileBackground);")
        #expect(js.evaluateScript("video.paused")?.toBool() == true)
        #expect(js.evaluateScript("messages.length")?.toInt32() == 1)
        js.evaluateScript("fire('click', scrubber); fire('click', menu); fire('click', link);")
        #expect(js.evaluateScript("messages.length")?.toInt32() == 1)
        #expect(js.exception == nil)
    }

    @Test("Revealed mobile controls auto-hide and notify the native toolbar")
    func mobileAutoHide() throws {
        let js = try context()
        js.evaluateScript(
            "enableMobile(); fire('click', mobileBackground); fire('click', mobileBackground); runTimers();")
        #expect(js.evaluateScript("mobile.classList.contains('fadein')")?.toBool() == false)
        #expect(js.evaluateScript("messages.map(m => m.controlsVisible).join(',')")?.toString() == "false,true,false")
        #expect(js.evaluateScript("video.paused")?.toBool() == false)
    }

    private static let fixture = """
        var listeners = {}, messages = [], downstreamCalls = 0;
        var video = {readyState: 4, ended: false, paused: false, matches: () => true};
        var mobile = null, mobileBackground, mobileMiddle, mobileVisible = true;
        var timers = {}, nextTimer = 0;
        function setTimeout(fn) { timers[++nextTimer] = fn; return nextTimer; }
        function clearTimeout(id) { delete timers[id]; }
        function runTimers() { var pending = timers; timers = {}; Object.values(pending).forEach(fn => fn()); }
        function enableMobile() {
            mobile = {
                matches: selector => selector.includes('#player-control-overlay'),
                contains: target => [mobile, mobileBackground, mobileMiddle, playButton, scrubber, menu, link].includes(target),
                classList: {
                    contains: name => name === 'fadein' && mobileVisible,
                    toggle: (name, value) => { if (name === 'fadein') mobileVisible = value; },
                    remove: name => { if (name === 'fadein') mobileVisible = false; }
                }
            };
            // These are siblings of movie_player on the physical iPad, not
            // descendants of its video container (the original missed case).
            mobileBackground = {matches: selector => selector.includes('.player-controls-background')};
            mobileMiddle = {matches: selector => selector.includes('.player-controls-middle')};
        }
        var playButton = {matches: () => false};
        var scrubber = {matches: () => false};
        var menu = {matches: () => false};
        var link = {matches: () => false};
        var replay = {matches: () => false};
        var hidden = true;
        var player = {
            contains: target => target === video || target === player,
            querySelector: () => video,
            classList: {contains: () => hidden},
            showControls: () => { hidden = false; },
            hideControls: () => { hidden = true; }
        };
        var document = {
            fullscreenElement: null,
            getElementById: id => id === 'movie_player' ? player : id === 'player-control-overlay' ? mobile : null,
            addEventListener: (type, handler) => { listeners[type] = handler; }
        };
        var window = {__nativeYTCallback: {postMessage: body => messages.push(JSON.parse(body))}};
        function fire(type, target, x = 0, count = 1, cancelable = true) {
            var touch = {identifier: 1, clientX: x, clientY: 0};
            var event = {
                target, button: 0, cancelable, defaultPrevented: false, stopped: false,
                touches: type === 'touchend' ? [] : Array(count).fill(touch),
                changedTouches: [touch],
                preventDefault() { this.defaultPrevented = true; },
                stopImmediatePropagation() { this.stopped = true; }
            };
            if (listeners[type]) listeners[type](event);
            if (!event.stopped && (type === 'click' || type === 'touchend')) {
                downstreamCalls++;
                if (target === playButton || ((target === video || target === mobileBackground || target === mobileMiddle) && (!mobile || type === 'click'))) video.paused = !video.paused;
            }
            return event;
        }
        """
}

#endif
