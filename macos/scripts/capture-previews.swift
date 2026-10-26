import AppKit
import Foundation
import WebKit

private struct SaverPreview {
    let slug: String
    let startTime: TimeInterval
    let duration: TimeInterval
}

private let previews = [
    SaverPreview(slug: "flying-toasters", startTime: 22.0, duration: 3.0),
    SaverPreview(slug: "fish", startTime: 8.5, duration: 3.0),
    SaverPreview(slug: "globe", startTime: 0.7, duration: 3.0),
    SaverPreview(slug: "hard-rain", startTime: 0.5, duration: 4.5),
    SaverPreview(slug: "bouncing-ball", startTime: 0.5, duration: 3.0),
    SaverPreview(slug: "warp", startTime: 4.1, duration: 2.0),
    SaverPreview(slug: "messages", startTime: 1.0, duration: 3.0),
    SaverPreview(slug: "messages2", startTime: 0.5, duration: 3.0),
    SaverPreview(slug: "fade-out", startTime: 0.0, duration: 3.0),
    SaverPreview(slug: "logo", startTime: 0.5, duration: 3.0),
    SaverPreview(slug: "rainstorm", startTime: 4.1, duration: 4.5),
    SaverPreview(slug: "spotlight", startTime: 0.5, duration: 3.0),
]

private enum CaptureError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message): message
        }
    }
}

private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var result: Result<Void, Error>?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        result = .success(())
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        result = .failure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        result = .failure(error)
    }
}

private func runLoop(until predicate: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !predicate() && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return predicate()
}

private func evaluateJavaScript(_ script: String, in webView: WKWebView) throws -> Any? {
    var result: Result<Any?, Error>?
    webView.evaluateJavaScript(script) { value, error in
        if let error {
            result = .failure(error)
        } else {
            result = .success(value)
        }
    }
    guard runLoop(until: { result != nil }, timeout: 5), let result else {
        throw CaptureError.message("Timed out evaluating JavaScript")
    }
    return try result.get()
}

private func waitForDocument(in webView: WKWebView) throws {
    let readinessScript = """
    (function () {
      var imagesReady = Array.prototype.every.call(document.images, function (image) {
        return image.complete && image.naturalWidth > 0;
      });
      var fontsReady = !document.fonts || document.fonts.status === 'loaded';
      return document.readyState === 'complete' && imagesReady && fontsReady;
    })()
    """
    let ready = runLoop(until: {
        (try? evaluateJavaScript(readinessScript, in: webView) as? Bool) == true
    }, timeout: 5)
    if !ready {
        throw CaptureError.message("Timed out waiting for images and fonts")
    }
}

private func setAnimationTime(_ milliseconds: Double, in webView: WKWebView) throws {
    let script = """
    (function (time) {
      if (!window.__sadPreviewAnimations) {
        window.__sadPreviewAnimations = document.getAnimations();
        window.__sadPreviewAnimations.forEach(function (animation) {
          animation.pause();
        });
      }
      window.__sadPreviewAnimations.forEach(function (animation) {
        animation.currentTime = time;
      });
      void document.documentElement.offsetWidth;
      return window.__sadPreviewAnimations.length;
    })(\(milliseconds))
    """
    guard let count = try evaluateJavaScript(script, in: webView) as? Int, count > 0 else {
        throw CaptureError.message("The page exposed no Web Animations")
    }
}

private func snapshot(_ webView: WKWebView) throws -> Data {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = webView.bounds
    configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width))

    var result: Result<NSImage, Error>?
    webView.takeSnapshot(with: configuration) { image, error in
        if let image {
            result = .success(image)
        } else {
            result = .failure(error ?? CaptureError.message("WebKit returned no snapshot"))
        }
    }
    guard runLoop(until: { result != nil }, timeout: 5), let result else {
        throw CaptureError.message("Timed out taking a WebKit snapshot")
    }

    let image = try result.get()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CaptureError.message("Could not encode a snapshot as PNG")
    }
    return png
}

private func capture(
    _ preview: SaverPreview,
    assetRoot: URL,
    framesRoot: URL,
    width: Int,
    height: Int,
    framesPerSecond: Int
) throws {
    let pageURL = assetRoot
        .appendingPathComponent("all", isDirectory: true)
        .appendingPathComponent(preview.slug)
        .appendingPathExtension("html")
    guard FileManager.default.fileExists(atPath: pageURL.path) else {
        throw CaptureError.message("Missing page: \(pageURL.path)")
    }

    let frameDirectory = framesRoot.appendingPathComponent(preview.slug, isDirectory: true)
    try FileManager.default.createDirectory(
        at: frameDirectory,
        withIntermediateDirectories: true
    )

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.suppressesIncrementalRendering = true
    let frame = NSRect(x: 0, y: 0, width: width, height: height)
    let webView = WKWebView(frame: frame, configuration: configuration)
    webView.underPageBackgroundColor = .black
    let window = NSWindow(
        contentRect: frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.backgroundColor = .black
    window.contentView = webView

    let navigationWaiter = NavigationWaiter()
    webView.navigationDelegate = navigationWaiter
    webView.loadFileURL(pageURL, allowingReadAccessTo: assetRoot)
    guard runLoop(until: { navigationWaiter.result != nil }, timeout: 10),
          let navigationResult = navigationWaiter.result else {
        throw CaptureError.message("Timed out loading \(preview.slug)")
    }
    try navigationResult.get()
    try waitForDocument(in: webView)

    let frameCount = Int((preview.duration * Double(framesPerSecond)).rounded())
    for frameIndex in 0..<frameCount {
        let time = preview.startTime + Double(frameIndex) / Double(framesPerSecond)
        try setAnimationTime(time * 1_000, in: webView)
        let data = try snapshot(webView)
        let filename = String(format: "%04d.png", frameIndex)
        try data.write(to: frameDirectory.appendingPathComponent(filename), options: .atomic)
    }
    webView.navigationDelegate = nil
    webView.stopLoading()
    print("Captured \(preview.slug): \(frameCount) frames")
}

private func main() throws {
    guard CommandLine.arguments.count == 6,
          let width = Int(CommandLine.arguments[3]), width > 0,
          let height = Int(CommandLine.arguments[4]), height > 0,
          let framesPerSecond = Int(CommandLine.arguments[5]), framesPerSecond > 0 else {
        throw CaptureError.message(
            "usage: capture-previews.swift ASSET_ROOT FRAMES_ROOT WIDTH HEIGHT FPS"
        )
    }

    let assetRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let framesRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: framesRoot, withIntermediateDirectories: true)

    _ = NSApplication.shared
    for preview in previews {
        try autoreleasepool {
            try capture(
                preview,
                assetRoot: assetRoot,
                framesRoot: framesRoot,
                width: width,
                height: height,
                framesPerSecond: framesPerSecond
            )
        }
    }
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
