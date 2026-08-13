import Foundation

/// Apps where tabs are the norm — the audience for the ⌃Tab card. Curated,
/// because "is a browser" is not something macOS exposes; PRs adding
/// missing browsers are always welcome.
public enum BrowserCatalog {
    public static let bundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", // Arc
        "com.kagi.kagi",              // Orion
    ]

    public static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}
