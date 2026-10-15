#if !os(tvOS)
import WebKit

extension TOSPlayerViewModel {
    // MARK: - WKUserScripts

    /// Injected at atDocumentStart into every frame. Hides window.webkit before any page
    /// script runs so YouTube's player can't detect the WKWebView environment. Stores
    /// the native ytCallback reference as window.__nativeYTCallback for stateDetectionJS.
    static let webkitHiderJS: String = """
        (function() {
            try {
                var wk = window.webkit;
                if (!wk) return;
                var mh = wk.messageHandlers;
                window.__nativeYTCallback = (mh && mh.ytCallback) ? mh.ytCallback : null;
                Object.defineProperty(window, 'webkit', {
                    get: function() { return undefined; },
                    set: function() {},
                    configurable: true,
                    enumerable: false
                });
            } catch(e) {}
        })();
        """

    /// JavaScript injected at document-end into the YouTube embed page.
    /// Polls the `<video>` element and relays state via window.__nativeYTCallback
    /// (saved by webkitHiderJS before window.webkit was hidden).
    static let stateDetectionJS: String = """
        (function() {
            try {
                var _cb = window.__nativeYTCallback;
                if (_cb) _cb.postMessage('{"type":"ping"}');
            } catch(e) {}

            var _prevState = -2;
            var _playAttempts = 0;
            var _autoUnmuted = false;
            var _pausedCandidate = false;
            var _prevMuted = null;
            // Set to true by visibilitychange when the page hides (app backgrounds).
            // Cleared when we detect a mute→true transition caused by the hide, so the
            // subsequent false→true mute is attributed to iOS, not to the user.
            var _wasHidden = false;
            // When > 0, pollVideo re-applies unmute each tick and decrements.
            // Started when we detect iOS re-muted the video after a background event.
            // Cap of 12 polls ≈ 3 seconds — enough for YouTube's player to finish
            // re-initialising after setAllMediaPlaybackSuspended(false), but short enough
            // that we don't fight a user-intentional mute forever.
            var _bgRemutePollRetries = 0;

            function postMsg(obj) {
                try {
                    var cb = window.__nativeYTCallback;
                    if (cb) cb.postMessage(JSON.stringify(obj));
                } catch(e) {}
            }

            // Page Visibility API — fires when the app backgrounds (hidden=true) or
            // returns to foreground (hidden=false). Used to distinguish iOS background
            // re-muting from a user-intentional mute: if video.muted flips to true
            // within a poll or two of becoming hidden, it's the OS, not the user.
            //
            // Also: when the WKWebView becomes visible again, iOS often leaves the
            // <video> element paused (the WKWebView was hidden briefly during
            // XCUITest's UI query or system events; iOS pauses HTML5 video on view
            // hide and doesn't auto-resume). We call video.play() on the
            // visible transition to recover — without this, the video stays
            // stuck in buffering state=3 at t=0 and `timeadvanced` never fires,
            // which breaks TOSPlayerIOSUITests.testTOSPlayerIOSSmoke's strict
            // "video is actually playing" assertion. The play() is silent
            // (catch-swallowed) because iOS may reject the call if no user
            // gesture has been seen for several minutes — that's fine, the
            // user will be tapping the screen and play() will work then.
            document.addEventListener('visibilitychange', function() {
                if (document.hidden) {
                    _wasHidden = true;
                    postMsg({type: 'pageHidden'});
                } else {
                    postMsg({type: 'pageVisible', wasHidden: _wasHidden});
                    // Page just became visible — reset the play-attempt counter so the
                    // poll loop's uncapped play() retries have a fresh budget. The cap
                    // was already removed (the test simulator's cover-present animation
                    // routinely takes >5s to finish), but resetting the counter here
                    // also ensures we don't keep trying to play forever after the page
                    // stabilised in a paused state.
                    _playAttempts = 0;
                    var v = document.querySelector('video');
                    if (v && v.paused) {
                        var p = v.play();
                        if (p && p['catch']) { p['catch'](function() {}); }
                    }
                }
            }, false);

            // Watch for YouTube's error overlay appearing in the DOM. This fires when
            // the player shows "Error 153 - Video player configuration error" (or similar)
            // instead of loading the video. MutationObserver is used so the check runs
            // asynchronously on DOM changes, not inside the pollVideo hot-path.
            var _errorReported = false;
            function checkErrorOverlay(node) {
                if (_errorReported || node.nodeType !== 1) return;
                var errEl = null;
                if (node.classList && node.classList.contains('ytp-error')) {
                    errEl = node;
                } else if (node.querySelector && node.querySelector('.ytp-error')) {
                    errEl = node.querySelector('.ytp-error');
                } else if (node.closest) {
                    // Content filled into an overlay that was already in the DOM (#158).
                    errEl = node.closest('.ytp-error');
                }
                if (!errEl) return;
                _errorReported = true;
                // Let the overlay finish filling in before reading its text.
                setTimeout(function() {
                    var txt = (errEl.textContent || '').trim();
                    var m = txt.match(/Error\\s+(\\d+)/i);
                    // -2 = sign-in / bot check (#158), handled as signInRequired natively.
                    var code = m ? parseInt(m[1], 10) : (/sign in|not a bot/i.test(txt) ? -2 : 153);
                    postMsg({type: 'error', code: code, text: txt.substring(0, 200)});
                }, 300);
            }
            var _observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var added = mutations[i].addedNodes;
                    for (var j = 0; j < added.length; j++) { checkErrorOverlay(added[j]); }
                }
            });
            _observer.observe(document.documentElement, {childList: true, subtree: true});

            function pollVideo() {
                var video = document.querySelector('video');
                if (!video) return;

                // video.paused can flicker true→false within a single poll interval right
                // after a resume (confirmed via live device log on the Shorts copy of this
                // poll — see ShortsEmbedJS.swift's stateDetectionJS for the full story).
                // Debounce: only commit to the paused state on the 2nd consecutive poll
                // observing it after a playing state, so a transient blip doesn't get
                // broadcast as a real pause. Already-paused readings (and ended) report
                // immediately.
                var rawPaused = video.paused;
                var s;
                if (video.ended) {
                    s = 0;
                    _pausedCandidate = false;
                } else if (rawPaused) {
                    var wasActivelyPlaying = (_prevState === 1 || _prevState === 3);
                    if (wasActivelyPlaying && !_pausedCandidate) {
                        _pausedCandidate = true;
                        s = _prevState;
                    } else {
                        s = 2;
                    }
                } else {
                    _pausedCandidate = false;
                    s = (video.readyState >= 3) ? 1 : 3;
                }

                var t = video.currentTime || 0;

                if (_prevState === -2) {
                    _prevState = s;
                    postMsg({type: 'ready', duration: video.duration || 0,
                             readyState: video.readyState, buffered: video.buffered.length});
                }

                // Kick off playback if YouTube's own autoplay didn't fire (common in WKWebView).
                // Retry every poll, no cap — when the WKWebView finally becomes visible
                // (cover-present animation completes, app returns from background, etc.)
                // the next play() will succeed. The 20-poll cap that used to be here was
                // removed because the test simulator's cover-present animation can take
                // >5s on the first run, leaving the page hidden long enough to exhaust
                // the old cap and leave the video stuck at t=0 indefinitely.
                if (video.paused && t === 0) {
                    _playAttempts++;
                    video.muted = true;
                    var p = video.play();
                    if (p && p['catch']) { p['catch'](function() {}); }
                }

                // Auto-unmute once playback is CONFIRMED actively progressing. Loading
                // muted (URL's mute=1 + the video.muted=true nudge above) exists solely
                // to satisfy WebKit's autoplay policy — autoplay is only ever guaranteed
                // to fire unmuted after a recent user gesture, so a muted start is the
                // only reliable way to avoid landing on a frozen first frame. Once we can
                // SEE forward progress (t advancing past startup), drop the mute exactly
                // once. Gated by _autoUnmuted so a later user-initiated mute (via
                // YouTube's own controls=1 chrome) is never fought/overridden.
                //
                // Both video.muted AND #movie_player.unMute() are needed: YouTube's
                // player object keeps its own internal mute flag (seeded true from the
                // mute=1 URL param) and periodically re-applies it onto video.muted,
                // undoing a DOM-only override ~250ms later. unMute() updates that
                // internal flag directly.
                if (!_autoUnmuted && !video.paused && t > 0.1) {
                    _autoUnmuted = true;
                    video.muted = false;
                    var ytPlayer = document.getElementById('movie_player');
                    if (ytPlayer && typeof ytPlayer.unMute === 'function') { ytPlayer.unMute(); }
                    postMsg({type: 'autoUnmuted', t: t, muted: video.muted});
                }

                // Track video.muted transitions. When we see false→true AFTER _autoUnmuted
                // and the page was recently hidden, iOS re-muted the video during background.
                // Start the retry cycle to fight it from inside the iframe (correct frame,
                // always has access to movie_player) rather than from a Swift eval.
                if (_prevMuted !== null && video.muted !== _prevMuted) {
                    if (video.muted && _autoUnmuted && _wasHidden) {
                        // iOS re-muted after background — arm the retry loop.
                        _wasHidden = false;
                        _bgRemutePollRetries = 12;
                        postMsg({type: 'bgRemute', t: t, retriesArmed: _bgRemutePollRetries});
                    } else if (video.muted && _autoUnmuted) {
                        // Muted without a preceding background event — treat as user action.
                        postMsg({type: 'userMute', t: t});
                    }
                    postMsg({type: 'muteChange', muted: video.muted, t: t, prevMuted: _prevMuted});
                }
                _prevMuted = video.muted;

                // Self-healing unmute: re-apply every poll tick until the counter runs out.
                // Runs entirely inside the iframe's document so movie_player is always
                // reachable — no embedFrameInfo needed, no cross-origin issues.
                if (_bgRemutePollRetries > 0) {
                    _bgRemutePollRetries--;
                    video.muted = false;
                    var ytp = document.getElementById('movie_player');
                    if (ytp && typeof ytp.unMute === 'function') { ytp.unMute(); }
                    postMsg({type: 'pollUnmuted', t: t, retriesLeft: _bgRemutePollRetries, muted: video.muted});
                }

                postMsg({type: 'tick', t: t, state: s, duration: video.duration || 0});

                if (s !== _prevState) {
                    _prevState = s;
                    postMsg({type: 'stateChange', state: s});
                }
            }

            setInterval(pollVideo, 250);
        })();
        """
}
#endif
