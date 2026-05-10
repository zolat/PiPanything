import Cocoa

@main
enum PiPanythingApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            // Hold a strong reference for the lifetime of the run loop.
            objc_setAssociatedObject(app, "PiPanythingDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            app.run()
        }
    }
}
