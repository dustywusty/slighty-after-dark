import AppKit
import Darwin
import ScreenSaver

// Run in a separate process for each bundle so WebKit caches and loaded classes
// cannot contaminate a before/after comparison. Defaults never touch user settings.
private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private func runLoop(for duration: TimeInterval) {
    let deadline = Date(timeIntervalSinceNow: duration)
    while Date() < deadline {
        autoreleasepool {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
    }
}

private func footprintMiB() -> Double {
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
    }
    guard result == 0 else { fail("Could not read process memory footprint") }
    return Double(usage.ri_phys_footprint) / 1_048_576
}

private func evaluate(_ script: String, in renderer: NSView) -> String? {
    renderer.perform(NSSelectorFromString("stringByEvaluatingJavaScriptFromString:"),
                     with: script)?.takeUnretainedValue() as? String
}

guard (2...4).contains(CommandLine.arguments.count) else {
    fail("usage: memory-soak-test.swift bundle.saver [seconds=600] [max-growth-MiB=32]")
}
let duration = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 0 : 600
let maximumGrowth = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) ?? 0 : 32
guard duration >= 60, duration.isFinite, maximumGrowth > 0, maximumGrowth.isFinite else {
    fail("Use at least 60 seconds and a positive memory growth limit")
}

setenv("SAD_WEB_RENDERER", "legacy", 1)
setenv("SAD_DEFAULTS_MODULE", "SAD.memory-test.\(UUID().uuidString)", 1)
_ = NSApplication.shared
guard let bundle = Bundle(path: CommandLine.arguments[1]) else { fail("Invalid bundle path") }
try bundle.loadAndReturnError()
guard let saverType = bundle.principalClass as? ScreenSaverView.Type,
      let view = saverType.init(frame: NSRect(x: 0, y: 0, width: 5120, height: 1440),
                                isPreview: false) else { fail("Could not create saver") }
let window = NSWindow(contentRect: view.frame, styleMask: .borderless,
                      backing: .buffered, defer: false)
window.contentView = view
view.startAnimation()
guard let renderer = view.subviews.first,
      renderer.responds(to: NSSelectorFromString("stringByEvaluatingJavaScriptFromString:")) else {
    fail("Expected the compatibility renderer")
}
defer { view.stopAnimation() }

// Like the remote screen saver host, this window is hidden, but its native
// timer must still advance CSS animations. Allow initial caches to settle.
runLoop(for: 30)
guard evaluate("document.readyState", in: renderer) == "complete",
      evaluate("document.title", in: renderer)?.isEmpty == false else {
    fail("The animation document did not load")
}
let initialTransform = evaluate("getComputedStyle(document.querySelector('.toaster')).transform",
                                in: renderer)
runLoop(for: 0.3)
guard let initialTransform,
      evaluate("getComputedStyle(document.querySelector('.toaster')).transform", in: renderer)
        != initialTransform else { fail("The compatibility renderer is not animating") }

let baseline = footprintMiB()
var peak = baseline
let start = ProcessInfo.processInfo.systemUptime
print(String(format: "PID %d: baseline %.1f MiB after 30s warmup", getpid(), baseline))
fflush(stdout)
while ProcessInfo.processInfo.systemUptime - start < duration {
    runLoop(for: min(10, duration - (ProcessInfo.processInfo.systemUptime - start)))
    autoreleasepool {
        view.displayIfNeeded()
        let memory = footprintMiB()
        peak = max(peak, memory)
        print(String(format: "%.0fs: %.1f MiB (growth %+.1f MiB)",
                     ProcessInfo.processInfo.systemUptime - start, memory, memory - baseline))
        fflush(stdout)
    }
}
guard peak - baseline <= maximumGrowth else {
    fail(String(format: "Memory grew %.1f MiB; limit is %.1f MiB", peak - baseline, maximumGrowth))
}
print(String(format: "Passed: peak growth %.1f MiB over %.0fs", peak - baseline, duration))
