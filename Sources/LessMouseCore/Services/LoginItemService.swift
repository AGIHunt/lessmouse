import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService. Only meaningful when running from a real
/// .app bundle — `swift run` builds a bare executable, and the settings row
/// degrades to a disabled switch with an explanation there.
public enum LoginItemService {
    public static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration races with System Settings; the toggle re-reads
            // isEnabled on next render and rights itself.
        }
    }
}
