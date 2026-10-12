/// Previously, a video-surface tap revealed the app toolbar and also reached
/// YouTube, toggling playback. This iOS script intercepts blank-surface taps
/// to show/hide controls instead, while actual player controls keep their taps.
enum TOSPlayerSurfaceTapScript {
    static let source = """
        (function() {
            var touchStart = null;
            // Fingers can drift slightly during an intentional tap. Allow up to
            // 10 CSS pixels from the starting position on either axis; larger
            // movement cancels tap tracking so a swipe isn't handled as a tap.
            var maxTapMovementInCSSPixels = 10;
            var mobileHideTimer = null;

            function mobileControls() {
                return document.getElementById('player-control-overlay');
            }

            function reportVisibility(visible) {
                var callback = window.__nativeYTCallback;
                if (callback) callback.postMessage(JSON.stringify({type: 'surfaceTap', controlsVisible: visible}));
            }

            // Return the player for a supported surface, or null otherwise.
            // Callers can use this as a truthiness guard before handling a tap.
            function surfacePlayer(target) {
                var player = document.getElementById('movie_player');
                if (!player || !target || !target.matches) return null;
                // Match known blank backgrounds/containers in YouTube's DOM.
                // matches() checks only the tapped element: a button, icon, or
                // scrubber inside these containers must still receive its tap.
                // Do not use closest(), which would also match their ancestors.
                // These selectors may need updating if YouTube changes its markup.
                var mobile = mobileControls();
                var mobileSurface = mobile && mobile.contains(target) &&
                    target.matches('#player-control-overlay, .player-controls-background, ' +
                        '.player-controls-background-container, .player-controls-content, ' +
                        '.player-controls-middle, .fullscreen-controls, .top-full-screen-controls');
                var videoSurface = player.contains(target) && (target === player ||
                    target.matches('video.html5-main-video, .html5-video-container'));
                if (!mobileSurface && !videoSurface) return null;
                var video = player.querySelector('video');
                if (!video || video.readyState < 2 || video.ended) return null;
                // Leave system fullscreen and unfamiliar player variants alone.
                if (document.fullscreenElement === video) return null;
                if (!mobile && (typeof player.showControls !== 'function' || typeof player.hideControls !== 'function')) return null;
                return player;
            }

            function toggleControls(event, player) {
                event.preventDefault();
                event.stopImmediatePropagation();
                var mobile = mobileControls();
                var visible;
                if (mobile) {
                    // The mobile overlay can be a sibling of movie_player. Its
                    // content is shown by fadein, not the desktop ytp-autohide API.
                    visible = !mobile.classList.contains('fadein');
                    mobile.classList.toggle('fadein', visible);
                    clearTimeout(mobileHideTimer);
                    if (visible) mobileHideTimer = setTimeout(function() {
                        mobile.classList.remove('fadein');
                        reportVisibility(false);
                    }, 4000);
                } else {
                    visible = player.classList.contains('ytp-autohide');
                    if (visible) player.showControls();
                    else player.hideControls();
                }
                reportVisibility(visible);
            }

            // Do not cancel touchstart/move: UIKit must still receive swipe
            // navigation and brightness/volume drags. Track maximum displacement,
            // so a drag that returns to its starting point is not mistaken for a tap.
            document.addEventListener('touchstart', function(event) {
                touchStart = null;
                if (event.touches.length !== 1 || !surfacePlayer(event.target)) return;
                var touch = event.touches[0];
                touchStart = {id: touch.identifier, x: touch.clientX, y: touch.clientY};
            }, {capture: true, passive: true});

            document.addEventListener('touchmove', function(event) {
                if (!touchStart) return;
                if (event.touches.length !== 1) { touchStart = null; return; }
                var touch = event.touches[0];
                if (touch.identifier !== touchStart.id ||
                    Math.abs(touch.clientX - touchStart.x) > maxTapMovementInCSSPixels ||
                    Math.abs(touch.clientY - touchStart.y) > maxTapMovementInCSSPixels) touchStart = null;
            }, {capture: true, passive: true});

            document.addEventListener('touchcancel', function() { touchStart = null; }, true);
            document.addEventListener('touchend', function(event) {
                var start = touchStart;
                touchStart = null;
                if (!start || event.touches.length !== 0 || event.changedTouches.length !== 1) return;
                var touch = event.changedTouches[0];
                if (touch.identifier !== start.id ||
                    Math.abs(touch.clientX - start.x) > maxTapMovementInCSSPixels ||
                    Math.abs(touch.clientY - start.y) > maxTapMovementInCSSPixels) return;
                var player = surfacePlayer(event.target);
                // Cancelling touchend also suppresses the synthesized mouse click,
                // so one physical tap toggles the controls exactly once.
                // Mobile touchend cleans up YouTube's long-press/drag state.
                // Let it finish, then intercept the synthesized click that the
                // TV user agent otherwise treats as a mouse playback toggle.
                if (player && !mobileControls() && event.cancelable) toggleControls(event, player);
            }, {capture: true, passive: false});

            // Pointer/trackpad clicks and accessibility activation without a touch.
            document.addEventListener('click', function(event) {
                if (event.button !== 0) return;
                var player = surfacePlayer(event.target);
                if (player) toggleControls(event, player);
            }, true);
        })();
        """
}
