import AppKit
import ScreenSaver
import WebKit

private let saverNames = [
    "flying-toasters",
    "fish",
    "globe",
    "hard-rain",
    "bouncing-ball",
    "warp",
    "messages",
    "messages2",
    "fade-out",
    "logo",
    "rainstorm",
    "spotlight",
]

private let selectedSaverKey = "ScreenSaver"
private let frameRateKey = "FrameRate"
private let objectScaleKey = "ObjectScalePercent"
private let playbackSpeedKey = "PlaybackSpeedPercent"

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private let documentStateScript = """
JSON.stringify({
  ready: document.readyState,
  title: document.title,
  styles: document.styleSheets.length,
  children: document.body ? document.body.children.length : 0,
  font: document.body ? getComputedStyle(document.body).fontFamily : "",
  images: Array.prototype.every.call(document.images, function(image) {
    return image.complete && image.naturalWidth > 0;
  }),
  fonts: document.fonts ? document.fonts.status : "loaded"
})
"""

private func javaScriptString(_ script: String, in renderer: NSView) -> String? {
    if let webView = renderer as? WKWebView {
        var result: String?
        var finished = false
        webView.evaluateJavaScript(script) { value, _ in
            result = value as? String
            finished = true
        }

        let deadline = Date(timeIntervalSinceNow: 1)
        while !finished && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return result
    }

    let selector = NSSelectorFromString("stringByEvaluatingJavaScriptFromString:")
    guard renderer.responds(to: selector) else {
        return nil
    }
    return renderer.perform(selector, with: script)?.takeUnretainedValue() as? String
}

private func documentState(in renderer: NSView) -> String? {
    javaScriptString(documentStateScript, in: renderer)
}

private func documentIsReady(_ state: String) -> Bool {
    guard let data = state.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let values = object as? [String: Any] else {
        return false
    }

    return values["ready"] as? String == "complete"
        && !(values["title"] as? String ?? "").isEmpty
        && (values["styles"] as? Int ?? 0) > 0
        && (values["children"] as? Int ?? 0) > 0
        && (values["font"] as? String ?? "").contains("ChicagoFLF")
        && values["images"] as? Bool == true
        && values["fonts"] as? String == "loaded"
}

private func legacyJavaScript(_ script: String, in renderer: NSView) -> String? {
    guard NSStringFromClass(type(of: renderer)) == "WebView" else {
        return nil
    }
    return javaScriptString(script, in: renderer)
}

private func legacyAnimationTransform(in renderer: NSView) -> String? {
    legacyJavaScript("getComputedStyle(document.querySelector('.toaster')).transform", in: renderer)
}

private func legacyAnimationTime(in renderer: NSView) -> String? {
    legacyJavaScript("""
    window.__sadAnimations && window.__sadAnimations.length
      ? String(window.__sadAnimations[0].currentTime)
      : "missing"
    """, in: renderer)
}

private func runLoop(for duration: TimeInterval) {
    let deadline = Date(timeIntervalSinceNow: duration)
    while Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }
}

private func waitForLoad(in view: ScreenSaverView, expectedName: String) {
    let deadline = Date(timeIntervalSinceNow: 3)
    var loadedRenderer: NSView?

    while Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))

        if let webView = view.subviews.first as? WKWebView,
           !webView.isLoading,
           webView.url?.lastPathComponent == "\(expectedName).html" {
            loadedRenderer = webView
            break
        }

        if let renderer = view.subviews.first,
           NSStringFromClass(type(of: renderer)) == "WebView" {
            let isLoading = renderer.value(forKey: "loading") as? Bool ?? true
            let URLString = renderer.value(forKey: "mainFrameURL") as? String ?? ""
            if !isLoading,
               URL(string: URLString)?.lastPathComponent == "\(expectedName).html" {
                loadedRenderer = renderer
                break
            }
        }
    }

    guard let renderer = loadedRenderer else {
        fail("Timed out loading \(expectedName).html")
    }

    let readinessDeadline = Date(timeIntervalSinceNow: 3)
    while Date() < readinessDeadline {
        if let state = documentState(in: renderer), documentIsReady(state) {
            return
        }
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    fail("\(expectedName).html loaded without a complete styled document")
}

private func waitForPresentationSettings(
    in view: ScreenSaverView,
    scalePercent: Int,
    speedPercent: Int
) {
    let expected = "\(scalePercent):\(speedPercent)"
    let deadline = Date(timeIntervalSinceNow: 3)
    while Date() < deadline {
        if let renderer = view.subviews.first {
            let value = javaScriptString("""
            document.documentElement.dataset.sadObjectScale + ":" +
              document.documentElement.dataset.sadPlaybackSpeed
            """, in: renderer)
            if value == expected {
                return
            }
        }
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    fail("Timed out applying scale \(scalePercent)% and speed \(speedPercent)%")
}

private func waitForScaleTargetCount(_ expectedCount: Int, in view: ScreenSaverView) {
    let deadline = Date(timeIntervalSinceNow: 3)
    while Date() < deadline {
        if let renderer = view.subviews.first,
           javaScriptString(
               "document.documentElement.dataset.sadScaleTargetCount || '-1'",
               in: renderer
           ) == String(expectedCount) {
            return
        }
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    fail("Timed out classifying \(expectedCount) scalable targets")
}

private func firstToasterWidth(in renderer: NSView) -> Double? {
    javaScriptString(
        "String(document.querySelector('.toaster').getBoundingClientRect().width)",
        in: renderer
    ).flatMap(Double.init)
}

private func firstAnimationTime(in renderer: NSView) -> Double? {
    javaScriptString("""
    (function () {
      var animations = window.__sadAnimations ||
        (document.getAnimations ? document.getAnimations() : []);
      return animations.length ? String(animations[0].currentTime) : "";
    })()
    """, in: renderer).flatMap(Double.init)
}

private func firstAnimationPlaybackRate(in renderer: NSView) -> Double? {
    javaScriptString("""
    (function () {
      var animations = document.getAnimations ? document.getAnimations() : [];
      return animations.length ? String(animations[0].playbackRate) : "";
    })()
    """, in: renderer).flatMap(Double.init)
}

private func waitForAnimationPlaybackRate(_ expectedRate: Double, in renderer: NSView) {
    let deadline = Date(timeIntervalSinceNow: 2)
    while Date() < deadline {
        if let playbackRate = firstAnimationPlaybackRate(in: renderer),
           abs(playbackRate - expectedRate) < 0.01 {
            return
        }
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    fail("Timed out applying animation playback rate \(expectedRate)")
}

private func verifyLegacyAnimationDelta(
    in renderer: NSView,
    wallDuration: TimeInterval,
    minimumDelta: Double,
    maximumDelta: Double,
    context: String
) {
    guard let initialTime = firstAnimationTime(in: renderer) else {
        fail("Could not sample legacy animation time while \(context)")
    }
    runLoop(for: wallDuration)
    guard let finalTime = firstAnimationTime(in: renderer),
          finalTime - initialTime > minimumDelta,
          finalTime - initialTime < maximumDelta else {
        fail("Legacy animation speed was incorrect while \(context)")
    }
}

private func allSubviews(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
}

private func identifiedSubview<T: NSView>(
    _ type: T.Type,
    identifier: String,
    in view: NSView
) -> T? {
    allSubviews(of: view).compactMap { $0 as? T }.first {
        $0.identifier?.rawValue == identifier
    }
}

private func sendControlAction(_ control: NSControl) {
    guard let action = control.action,
          NSApp.sendAction(action, to: control.target, from: control) else {
        fail("Could not send action for \(control.identifier?.rawValue ?? "control")")
    }
    runLoop(for: 0.05)
}

private func integerProperty(_ key: String, in view: ScreenSaverView) -> Int? {
    (view.value(forKey: key) as? NSNumber)?.intValue
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: runtime-smoke-test.swift /path/to/Slightly After Dark.saver")
}

let bundlePath = CommandLine.arguments[1]
_ = NSApplication.shared

guard let bundle = Bundle(path: bundlePath) else {
    fail("Could not create bundle for \(bundlePath)")
}

do {
    try bundle.loadAndReturnError()
} catch {
    fail("Could not load bundle: \(error)")
}

guard let bundleIdentifier = bundle.bundleIdentifier,
      let saverType = bundle.principalClass as? ScreenSaverView.Type else {
    fail("Bundle has no ScreenSaverView principal class")
}

let defaultsModule = "\(bundleIdentifier).runtime-tests.\(ProcessInfo.processInfo.processIdentifier)"
setenv("SAD_DEFAULTS_MODULE", defaultsModule, 1)

guard let defaults = ScreenSaverDefaults(forModuleWithName: defaultsModule) else {
    fail("Could not open ScreenSaverDefaults")
}

defer {
    for key in [selectedSaverKey, frameRateKey, objectScaleKey, playbackSpeedKey] {
        defaults.removeObject(forKey: key)
    }
    defaults.synchronize()
}

for (index, name) in saverNames.enumerated() {
    defaults.set(index, forKey: selectedSaverKey)
    defaults.synchronize()

    let saverSize = name == "flying-toasters"
        ? NSSize(width: 5120, height: 1440)
        : NSSize(width: 800, height: 600)

    guard let view = saverType.init(
        frame: NSRect(origin: .zero, size: saverSize),
        isPreview: true
    ) else {
        fail("Could not initialize saver index \(index)")
    }

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: saverSize),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = view

    view.startAnimation()
    waitForLoad(in: view, expectedName: name)
    waitForPresentationSettings(in: view, scalePercent: 100, speedPercent: 100)

    guard let renderer = view.subviews.first else {
        fail("Renderer disappeared while running \(name)")
    }
    view.layoutSubtreeIfNeeded()
    guard renderer.frame.size == view.bounds.size else {
        fail("Renderer for \(name) did not fill the saver view")
    }

    var stoppedLegacyTransform: String?
    if name == "flying-toasters",
       let initialTransform = legacyAnimationTransform(in: renderer) {
        let hasVisibleObject = legacyJavaScript("""
        Array.prototype.some.call(document.querySelectorAll('.toaster, .toast'), function (element) {
          var rect = element.getBoundingClientRect();
          return rect.right > 0 && rect.bottom > 0
              && rect.left < innerWidth && rect.top < innerHeight;
        }) ? "yes" : "no"
        """, in: renderer)
        guard hasVisibleObject == "yes" else {
            fail("Flying Toasters had no visible objects at 5120×1440")
        }

        runLoop(for: 0.4)
        guard let advancedTransform = legacyAnimationTransform(in: renderer),
              advancedTransform != initialTransform else {
            fail("Legacy renderer loaded Flying Toasters but did not animate it")
        }
        stoppedLegacyTransform = advancedTransform
    }

    view.stopAnimation()
    guard renderer.superview === view else {
        fail("Renderer disappeared when \(name) was stopped")
    }
    if let stoppedTransform = stoppedLegacyTransform {
        runLoop(for: 0.2)
        guard legacyAnimationTransform(in: renderer) == stoppedTransform else {
            fail("Legacy renderer continued advancing after stopAnimation")
        }

        // Force a timer tick between a same-page navigation request and its
        // commit. The new document must replace the outgoing animation cache.
        view.startAnimation()
        view.animateOneFrame()
        waitForLoad(in: view, expectedName: name)
        guard let reloadedTime = legacyAnimationTime(in: renderer),
              reloadedTime != "missing" else {
            fail("Legacy renderer lost its animation cache during reload")
        }
        runLoop(for: 0.3)
        guard let advancedReloadTime = legacyAnimationTime(in: renderer),
              advancedReloadTime != reloadedTime else {
            fail("Legacy renderer did not animate after a same-page reload")
        }
        view.stopAnimation()
    }
    if name == "flying-toasters", renderer is WKWebView {
        // WKWebView owns its compositor clock, so stopAnimation must pause the
        // document explicitly rather than relying on ScreenSaverView's timer.
        runLoop(for: 0.1)
        guard let pausedTime = firstAnimationTime(in: renderer) else {
            fail("Could not sample the stopped modern animation")
        }
        runLoop(for: 0.2)
        guard let stillPausedTime = firstAnimationTime(in: renderer),
              abs(stillPausedTime - pausedTime) < 2.0 else {
            fail("Modern animations continued advancing after stopAnimation")
        }
    }

    if name == "fade-out" {
        view.startAnimation()
        waitForLoad(in: view, expectedName: name)
        view.stopAnimation()
    }

    if index == 0 {
        guard view.hasConfigureSheet, let sheet = view.configureSheet else {
            fail("Configuration sheet is unavailable")
        }
        let contentView = sheet.contentView ?? NSView()
        guard let popUp = identifiedSubview(
                  NSPopUpButton.self,
                  identifier: "SADSaverPopUp",
                  in: contentView
              ),
              let frameRateSlider = identifiedSubview(
                  NSSlider.self,
                  identifier: "SADFrameRateSlider",
                  in: contentView
              ),
              let objectScaleSlider = identifiedSubview(
                  NSSlider.self,
                  identifier: "SADObjectScaleSlider",
                  in: contentView
              ),
              let playbackSpeedSlider = identifiedSubview(
                  NSSlider.self,
                  identifier: "SADPlaybackSpeedSlider",
                  in: contentView
              ),
              popUp.numberOfItems == saverNames.count,
              popUp.indexOfSelectedItem == 0,
              frameRateSlider.minValue == 15,
              frameRateSlider.maxValue == 60,
              frameRateSlider.integerValue == 30,
              frameRateSlider.isEnabled
                  == (NSStringFromClass(type(of: renderer)) == "WebView"),
              objectScaleSlider.minValue == 50,
              objectScaleSlider.maxValue == 200,
              objectScaleSlider.integerValue == 100,
              playbackSpeedSlider.minValue == 50,
              playbackSpeedSlider.maxValue == 200,
              playbackSpeedSlider.integerValue == 100 else {
            fail("Configuration sheet selection is invalid")
        }
    }
}

// The macOS 26 System Settings preview can initialize a legacy module at zero
// size and resize it only after installation in its remote view hierarchy.
defaults.set(0, forKey: selectedSaverKey)
defaults.synchronize()
guard let lateSizedView = saverType.init(frame: .zero, isPreview: true) else {
    fail("Could not initialize a zero-sized preview")
}
guard lateSizedView.bounds.width > 0, lateSizedView.bounds.height > 0 else {
    fail("Zero-sized preview did not receive a nominal rendering canvas")
}
lateSizedView.layoutSubtreeIfNeeded()
guard let initialPreviewRenderer = lateSizedView.subviews.first,
      initialPreviewRenderer.frame.size == lateSizedView.bounds.size else {
    fail("Zero-sized preview renderer did not fill its nominal canvas")
}

guard let zeroFullScreenView = saverType.init(frame: .zero, isPreview: false),
      zeroFullScreenView.frame == .zero else {
    fail("Nominal preview sizing unexpectedly changed a full-screen view")
}
let lateSizedWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
lateSizedWindow.contentView = lateSizedView
lateSizedView.startAnimation()
waitForLoad(in: lateSizedView, expectedName: saverNames[0])
lateSizedView.layoutSubtreeIfNeeded()
guard let lateSizedRenderer = lateSizedView.subviews.first,
      lateSizedRenderer.frame.size == lateSizedView.bounds.size,
      lateSizedRenderer.frame.size.width > 0,
      lateSizedRenderer.frame.size.height > 0 else {
    fail("Renderer did not recover from a zero-sized preview frame")
}
lateSizedView.stopAnimation()

// A full-screen host is allowed to size the saver after its first document has
// loaded. Scalable targets must be classified again when that zero viewport
// becomes usable instead of caching an empty result forever.
defaults.set(2, forKey: selectedSaverKey)
defaults.set(150, forKey: objectScaleKey)
defaults.synchronize()
guard let lateSizedFullScreenView = saverType.init(frame: .zero, isPreview: false) else {
    fail("Could not initialize a late-sized full-screen saver")
}
lateSizedFullScreenView.startAnimation()
waitForLoad(in: lateSizedFullScreenView, expectedName: saverNames[2])
waitForPresentationSettings(
    in: lateSizedFullScreenView,
    scalePercent: 150,
    speedPercent: 100
)
let fullScreenWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
fullScreenWindow.contentView = lateSizedFullScreenView
lateSizedFullScreenView.layoutSubtreeIfNeeded()
waitForScaleTargetCount(1, in: lateSizedFullScreenView)
lateSizedFullScreenView.stopAnimation()

defaults.set(0, forKey: selectedSaverKey)
defaults.removeObject(forKey: objectScaleKey)
defaults.synchronize()

// Release views while their asynchronous initial navigation is still pending.
// This catches stale WebKit delegate callbacks during rapid host teardown.
for _ in 0..<5 {
    autoreleasepool {
        guard let transientView = saverType.init(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            isPreview: true
        ) else {
            fail("Could not initialize a transient saver view")
        }
        transientView.startAnimation()
        transientView.stopAnimation()
    }
    runLoop(for: 0.05)
}

for invalidIndex in [-1, saverNames.count] {
    defaults.set(invalidIndex, forKey: selectedSaverKey)
    defaults.synchronize()

    guard let view = saverType.init(
        frame: NSRect(x: 0, y: 0, width: 800, height: 600),
        isPreview: true
    ) else {
        fail("Could not initialize saver with invalid default \(invalidIndex)")
    }

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = view

    view.startAnimation()
    waitForLoad(in: view, expectedName: saverNames[0])
    view.stopAnimation()
}

// Initial previews are intentionally rendered as a static poster before their
// host starts animation. Opening and cancelling Options must not rewind that
// stopped document's timeline.
defaults.set(1, forKey: selectedSaverKey)
for key in [frameRateKey, objectScaleKey, playbackSpeedKey] {
    defaults.removeObject(forKey: key)
}
defaults.synchronize()
guard let stoppedPosterView = saverType.init(
    frame: NSRect(x: 0, y: 0, width: 800, height: 600),
    isPreview: true
) else {
    fail("Could not initialize the stopped-poster test view")
}
let stoppedPosterWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
stoppedPosterWindow.contentView = stoppedPosterView
waitForLoad(in: stoppedPosterView, expectedName: saverNames[1])
waitForPresentationSettings(in: stoppedPosterView, scalePercent: 100, speedPercent: 100)
runLoop(for: 0.1)
guard let stoppedPosterRenderer = stoppedPosterView.subviews.first,
      let posterTime = firstAnimationTime(in: stoppedPosterRenderer),
      let stoppedPosterSheet = stoppedPosterView.configureSheet,
      let stoppedPosterContent = stoppedPosterSheet.contentView,
      let stoppedPosterCancel = identifiedSubview(
          NSButton.self,
          identifier: "SADCancelButton",
          in: stoppedPosterContent
      ) else {
    fail("Could not inspect the stopped-poster configuration")
}
if NSStringFromClass(type(of: stoppedPosterRenderer)) == "WebView",
   !(posterTime > 1_900 && posterTime < 2_100) {
    fail("The compatibility renderer did not retain its stopped poster phase")
}
stoppedPosterWindow.beginSheet(stoppedPosterSheet) { _ in }
stoppedPosterCancel.performClick(nil)
runLoop(for: 0.1)
guard let cancelledPosterTime = firstAnimationTime(in: stoppedPosterRenderer),
      abs(cancelledPosterTime - posterTime) < 2.0 else {
    fail("Cancel rewound a stopped preview")
}

let invalidNumericPreferences = [
    (key: frameRateKey, value: 14, property: "frameRate", expected: 30),
    (key: frameRateKey, value: 61, property: "frameRate", expected: 30),
    (key: objectScaleKey, value: 49, property: "objectScalePercent", expected: 100),
    (key: objectScaleKey, value: 201, property: "objectScalePercent", expected: 100),
    (key: playbackSpeedKey, value: 49, property: "playbackSpeedPercent", expected: 100),
    (key: playbackSpeedKey, value: 201, property: "playbackSpeedPercent", expected: 100),
]

for testCase in invalidNumericPreferences {
    for key in [frameRateKey, objectScaleKey, playbackSpeedKey] {
        defaults.removeObject(forKey: key)
    }
    defaults.set(0, forKey: selectedSaverKey)
    defaults.set(testCase.value, forKey: testCase.key)
    defaults.synchronize()

    autoreleasepool {
        guard let view = saverType.init(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            isPreview: true
        ) else {
            fail("Could not initialize saver with invalid \(testCase.key)")
        }
        guard integerProperty(testCase.property, in: view) == testCase.expected else {
            fail("Invalid \(testCase.key) value \(testCase.value) did not use its default")
        }
        view.stopAnimation()
    }
    runLoop(for: 0.05)
}

// Exercise non-default values through both the rendered page and the native
// configuration sheet. This uses isolated preferences and offscreen windows;
// it does not inspect or capture the user's display.
defaults.set(0, forKey: selectedSaverKey)
defaults.set(60, forKey: frameRateKey)
defaults.set(150, forKey: objectScaleKey)
defaults.set(200, forKey: playbackSpeedKey)
defaults.synchronize()

guard let settingsView = saverType.init(
    frame: NSRect(x: 0, y: 0, width: 800, height: 600),
    isPreview: true
) else {
    fail("Could not initialize the settings test view")
}
let settingsWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
settingsWindow.contentView = settingsView
settingsView.startAnimation()
waitForLoad(in: settingsView, expectedName: saverNames[0])
waitForPresentationSettings(in: settingsView, scalePercent: 150, speedPercent: 200)

guard integerProperty("frameRate", in: settingsView) == 60,
      integerProperty("objectScalePercent", in: settingsView) == 150,
      integerProperty("playbackSpeedPercent", in: settingsView) == 200,
      let settingsRenderer = settingsView.subviews.first,
      let scaledToasterWidth = firstToasterWidth(in: settingsRenderer),
      abs(scaledToasterWidth - 96.0) < 1.0 else {
    fail("Persisted non-default settings were not applied to Flying Toasters")
}

let usesLegacyRenderer = NSStringFromClass(type(of: settingsRenderer)) == "WebView"
if usesLegacyRenderer {
    guard abs(settingsView.animationTimeInterval - 1.0 / 60.0) < 0.001,
          let initialAnimationTime = firstAnimationTime(in: settingsRenderer) else {
        fail("The compatibility renderer did not apply the 60 FPS setting")
    }
    runLoop(for: 0.4)
    guard let advancedAnimationTime = firstAnimationTime(in: settingsRenderer),
          advancedAnimationTime - initialAnimationTime > 450,
          advancedAnimationTime - initialAnimationTime < 1_200 else {
        fail("The compatibility renderer did not apply 200% motion speed")
    }
} else {
    guard abs(settingsView.animationTimeInterval - 1.0) < 0.001 else {
        fail("The modern renderer unexpectedly used the compatibility timer")
    }
    waitForAnimationPlaybackRate(2.0, in: settingsRenderer)
}

guard let settingsSheet = settingsView.configureSheet,
      let settingsContentView = settingsSheet.contentView,
      let saverPopUp = identifiedSubview(
          NSPopUpButton.self,
          identifier: "SADSaverPopUp",
          in: settingsContentView
      ),
      let frameRateSlider = identifiedSubview(
          NSSlider.self,
          identifier: "SADFrameRateSlider",
          in: settingsContentView
      ),
      let objectScaleSlider = identifiedSubview(
          NSSlider.self,
          identifier: "SADObjectScaleSlider",
          in: settingsContentView
      ),
      let playbackSpeedSlider = identifiedSubview(
          NSSlider.self,
          identifier: "SADPlaybackSpeedSlider",
          in: settingsContentView
      ),
      let cancelButton = identifiedSubview(
          NSButton.self,
          identifier: "SADCancelButton",
          in: settingsContentView
      ),
      let doneButton = identifiedSubview(
          NSButton.self,
          identifier: "SADDoneButton",
          in: settingsContentView
      ) else {
    fail("Could not find the configuration controls")
}

settingsWindow.beginSheet(settingsSheet) { _ in }
frameRateSlider.integerValue = 45
objectScaleSlider.integerValue = 200
playbackSpeedSlider.integerValue = 50
sendControlAction(objectScaleSlider)
waitForPresentationSettings(in: settingsView, scalePercent: 200, speedPercent: 50)
guard let liveToasterWidth = firstToasterWidth(in: settingsRenderer),
      abs(liveToasterWidth - 128.0) < 1.0 else {
    fail("The configuration sheet did not preview object size changes")
}
if usesLegacyRenderer {
    verifyLegacyAnimationDelta(
        in: settingsRenderer,
        wallDuration: 0.4,
        minimumDelta: 80,
        maximumDelta: 500,
        context: "previewing 50% speed"
    )
} else {
    waitForAnimationPlaybackRate(0.5, in: settingsRenderer)
}

cancelButton.performClick(nil)
runLoop(for: 0.1)
waitForPresentationSettings(in: settingsView, scalePercent: 150, speedPercent: 200)
guard defaults.integer(forKey: selectedSaverKey) == 0,
      defaults.integer(forKey: frameRateKey) == 60,
      defaults.integer(forKey: objectScaleKey) == 150,
      defaults.integer(forKey: playbackSpeedKey) == 200,
      integerProperty("frameRate", in: settingsView) == 60,
      let restoredToasterWidth = firstToasterWidth(in: settingsRenderer),
      abs(restoredToasterWidth - 96.0) < 1.0 else {
    fail("Cancel did not restore the original settings without persisting changes")
}
if usesLegacyRenderer {
    verifyLegacyAnimationDelta(
        in: settingsRenderer,
        wallDuration: 0.3,
        minimumDelta: 300,
        maximumDelta: 900,
        context: "restoring 200% speed with Cancel"
    )
} else {
    waitForAnimationPlaybackRate(2.0, in: settingsRenderer)
}

guard settingsView.configureSheet === settingsSheet else {
    fail("The configuration sheet was not reused")
}
settingsWindow.beginSheet(settingsSheet) { _ in }
saverPopUp.selectItem(at: 1)
frameRateSlider.integerValue = 45
objectScaleSlider.integerValue = 200
playbackSpeedSlider.integerValue = 50
sendControlAction(saverPopUp)
waitForLoad(in: settingsView, expectedName: saverNames[1])
waitForPresentationSettings(in: settingsView, scalePercent: 200, speedPercent: 50)
doneButton.performClick(nil)
runLoop(for: 0.1)

guard defaults.integer(forKey: selectedSaverKey) == 1,
      defaults.integer(forKey: frameRateKey) == 45,
      defaults.integer(forKey: objectScaleKey) == 200,
      defaults.integer(forKey: playbackSpeedKey) == 50 else {
    fail("Done did not persist the selected settings")
}

guard let persistedView = saverType.init(
    frame: NSRect(x: 0, y: 0, width: 800, height: 600),
    isPreview: true
) else {
    fail("Could not initialize a view from persisted settings")
}
let persistedWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
persistedWindow.contentView = persistedView
persistedView.startAnimation()
waitForLoad(in: persistedView, expectedName: saverNames[1])
waitForPresentationSettings(in: persistedView, scalePercent: 200, speedPercent: 50)
guard integerProperty("frameRate", in: persistedView) == 45,
      integerProperty("objectScalePercent", in: persistedView) == 200,
      integerProperty("playbackSpeedPercent", in: persistedView) == 50,
      abs(persistedView.animationTimeInterval - (usesLegacyRenderer ? 1.0 / 45.0 : 1.0)) < 0.001 else {
    fail("A new view did not restore the persisted settings")
}
guard let persistedRenderer = persistedView.subviews.first else {
    fail("The persisted view lost its renderer")
}
if usesLegacyRenderer {
    verifyLegacyAnimationDelta(
        in: persistedRenderer,
        wallDuration: 0.4,
        minimumDelta: 80,
        maximumDelta: 500,
        context: "restoring persisted 50% speed"
    )
} else {
    waitForAnimationPlaybackRate(0.5, in: persistedRenderer)
}

settingsView.stopAnimation()
persistedView.stopAnimation()

let rendererName = ProcessInfo.processInfo.environment["SAD_WEB_RENDERER"] ?? "automatic"
print("[\(rendererName)] Loaded all \(saverNames.count) screen savers and verified animation, lifecycle, late sizing, validated defaults, live settings, Cancel, Done, and persistence.")
