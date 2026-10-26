// Applies the Object size and Motion speed options to a loaded saver page.
//
// Native hosts evaluate this function expression followed by an argument list:
// (scalePercent, speedPercent, controlsSpeed). Hosts that drive the animation
// timeline themselves pass false for controlsSpeed and scale time natively.
(function (scalePercent, speedPercent, controlsSpeed) {
    var animations = document.getAnimations ? document.getAnimations() : [];
    var scaleTargets = window.__sadScaleTargets;
    if (!scaleTargets && innerWidth > 0 && innerHeight > 0) {
        var seen = [];
        scaleTargets = [];
        animations.forEach(function (animation) {
            var target = animation.effect && animation.effect.target;
            if (!target || !target.style || seen.indexOf(target) >= 0) return;
            seen.push(target);
            var forcedForeground = target.matches && target.matches(
                '.toaster, .toast, .fish, .bubbles, .r, .message');
            var fullScreenEffect = target === document.body || target === document.documentElement
                || (target.matches && target.matches('.stars, .rain, .dim, .spotlight'))
                || (target.offsetWidth >= innerWidth * 0.9
                    && target.offsetHeight >= innerHeight * 0.9);
            if (forcedForeground || !fullScreenEffect) scaleTargets.push(target);
        });
        window.__sadScaleTargets = scaleTargets;
    }
    if (!scaleTargets) scaleTargets = [];
    var scale = scalePercent / 100;
    var supportsIndependentScale = window.CSS && CSS.supports && CSS.supports('scale', '1.25');
    scaleTargets.forEach(function (target) {
        target.style.setProperty('transform-origin', 'center center', 'important');
        target.style.setProperty('image-rendering', 'pixelated', 'important');
        if (supportsIndependentScale) {
            target.style.removeProperty('zoom');
            target.style.setProperty('scale', String(scale), 'important');
        } else {
            target.style.removeProperty('scale');
            target.style.setProperty('zoom', String(scale), 'important');
        }
    });
    var speed = speedPercent / 100;
    if (controlsSpeed) {
        var timedAnimations = document.getAnimations ? document.getAnimations() : animations;
        timedAnimations.forEach(function (animation) {
            var currentTime = animation.currentTime;
            if (animation.startTime !== null && currentTime !== null
                && !animation.pending && animation.updatePlaybackRate) {
                animation.updatePlaybackRate(speed);
            } else {
                animation.playbackRate = speed;
                if (currentTime !== null) animation.currentTime = currentTime;
            }
        });
    }
    document.documentElement.dataset.sadObjectScale = String(scalePercent);
    document.documentElement.dataset.sadPlaybackSpeed = String(speedPercent);
    document.documentElement.dataset.sadScaleTargetCount = String(scaleTargets.length);
    return JSON.stringify({scale: scalePercent, speed: speedPercent,
        targets: scaleTargets.length});
})
