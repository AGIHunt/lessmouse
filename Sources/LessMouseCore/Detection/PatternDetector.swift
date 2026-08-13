import Foundation

/// Detects the burst patterns of PatternLibrary over a sliding window of
/// recent keystrokes.
///
/// Semantics, pinned by tests:
///
/// - A spec fires when ≥ N presses of its family land within T seconds
///   (inclusive — the T-second boundary still counts; burst fixing is not a
///   stopwatch sport).
/// - Firing *drains* that spec's window: six backspaces are one burst, not
///   two. The next burst must build its own count.
/// - Unrelated keys do NOT interrupt a window — "backspace, type a letter,
///   backspace" is still word-fixing by hand, just clumsier. The time window
///   alone decides when a burst is over. (`interruptedByOtherKey` exists on
///   the drawing board if the line ever needs to move.)
/// - A long hold is invisible here before it starts: autorepeats are dropped
///   by the signature filter, so a burst is always N distinct presses.
public final class PatternDetector {
    private let lock = NSLock()
    private var counters: [String: SlidingWindowCounter]
    /// spec.id → spec, for the fire path.
    private let specsByID: [String: PatternSpec]
    /// signature → spec ids watching it (one signature can feed several).
    private let specIDsBySignature: [String: [String]]

    public init(specs: [PatternSpec]) {
        var counters: [String: SlidingWindowCounter] = [:]
        var byID: [String: PatternSpec] = [:]
        var bySignature: [String: [String]] = [:]
        for spec in specs {
            counters[spec.id] = SlidingWindowCounter(count: spec.count, window: spec.window)
            byID[spec.id] = spec
            for signature in spec.signatures {
                bySignature[signature, default: []].append(spec.id)
            }
        }
        self.counters = counters
        self.specsByID = byID
        self.specIDsBySignature = bySignature
    }

    /// Feed one counted signature; returns the specs that just fired.
    public func feed(signature: String, at timestamp: TimeInterval) -> [PatternSpec] {
        var fired: [PatternSpec] = []
        lock.lock()
        defer { lock.unlock() }

        guard let specIDs = specIDsBySignature[signature] else { return fired }
        for specID in specIDs {
            guard let counter = counters[specID] else { continue }
            if counter.record(timestamp) {
                fired.append(specsByID[specID]!)
            }
        }
        return fired
    }

    /// Clear every window. Called on pause/resume and when the frontmost app
    /// changes: bursts must not be stitched together across boundaries the
    /// user would experience as separate.
    public func resetAll() {
        lock.lock()
        for counter in counters.values { counter.reset() }
        lock.unlock()
    }
}

/// Ring of timestamps for one spec. Small by construction — it never holds
/// more than `count` entries, because reaching `count` empties it.
final class SlidingWindowCounter {
    private var timestamps: [TimeInterval] = []
    private let count: Int
    private let window: TimeInterval

    init(count: Int, window: TimeInterval) {
        self.count = count
        self.window = window
    }

    /// Record a press at `t`. True the moment the threshold is met.
    func record(_ t: TimeInterval) -> Bool {
        timestamps.append(t)
        // An entry is in-window while no more than `window` seconds separate
        // it from now — inclusive, so a 4-press burst spanning exactly 2.0s
        // fires a 4/2s spec.
        while let first = timestamps.first, t - first > window {
            timestamps.removeFirst()
        }
        if timestamps.count >= count {
            timestamps.removeAll()
            return true
        }
        return false
    }

    func reset() {
        timestamps.removeAll()
    }
}
