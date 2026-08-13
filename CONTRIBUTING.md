# Contributing to LessMouse

Thanks for helping — this project exists to be forked, ported, and argued
with.

## Getting started

```bash
git clone …
cd LessMouse
swift build
swift test        # everything must stay green
scripts/make-app.sh   # full .app bundle for manual testing
```

No package manager, no codegen, no dependencies — macOS 14+, Swift 5.9+,
that's the whole toolchain.

## The one rule that outranks everything

**Never record what the user types.** The privacy contract lives in
`Sources/LessMouseCore/Models/KeySignature.swift` (~20 lines) and is guarded
by an exhaustive keycode × modifier sweep in
`Tests/LessMouseTests/CGEventNormalizerTests.swift`. If your change touches
the event path, that suite is the reviewer that never gets tired. New data
fields must be aggregate counts, readable in `stats.json`, and argued for in
the PR.

## Architecture in one screen

```
CGEventTap (KeyboardMonitor, listen-only, own thread)   ← thin shell, ~100 lines
   → CGEventNormalizer → KeyEvent (value type)
      → KeySignatureFilter (THE privacy choke point)
         ├→ StatsStore (stats.json, serial queue, atomic writes)
         ├→ PatternDetector (sliding-window bursts)
         └→ SuggestionEngine (card state machine + adoption)
              → AppState (@MainActor) → SwiftUI popover / menu bar dot
```

Everything below the tap is pure Swift with injected clocks — that's why the
whole brain of the app is unit-tested without touching a real keyboard. Keep
it that way: new logic goes in the pure layer, with tests, and the tap stays
a shell.

## Design language

The UI follows a strict token system ("ink, signal green, and clean paper")
defined in `Sources/LessMouseCore/Theme.swift`:

- One green, `#2CDB5C`, spent only on "on" states, dots and fills — never as
  a text color, never on chrome. Primary buttons are ink black.
- Control Center module grammar: rounded blocks, two-line rows, 28pt circular
  glyphs, monospaced digits for anything countable, no shadows inside the
  panel.
- Light/dark follows the system; every color is a token, not a literal.

If your change introduces a new visual concept, it belongs in `Theme.swift`
first. Screenshots for review: `LM_SNAPSHOT_DIR=/tmp/shots swift test` writes
PNGs of every page.

## Adding a coaching card

Cards are data. In `RuleLibrary.swift`: id, trigger (one of three shapes),
adoption signatures, keycaps, cooldown — then title/body/summary strings in
**both** `en.lproj` and `zh-Hans.lproj`. A trigger threshold should encode
"unmistakably a habit", not "technically possible". Tests go in
`SuggestionEngineTests`.

## Windows port — wanted, and designed for

We'd love a Windows maintainer. The split that matters:

| Layer | Portable? | Windows counterpart |
|---|---|---|
| `Models/`, `Detection/`, `Suggestions/`, `Storage/` | **As-is** — pure Foundation | none needed |
| `Monitoring/` | rewrite | `SetWindowsHookEx(WH_KEYBOARD_LL)`, VK codes → SafeKey |
| `State/AppState.swift` | mostly | swap `KeyEventSource`, permission flow |
| `Views/` | rewrite | WinUI 3 / tray flyout, same information architecture |

Recommended shape: a `windows/` directory in this repo, sharing the rule book
and thresholds via a small JSON export of `RuleLibrary` (or a shared
`rules/` folder both platforms read). Open an issue titled "Windows port"
before the first big PR so we can pin the plan together.

## PR checklist

- [ ] `swift test` green (all of it — the privacy sweep is not optional)
- [ ] No new dependencies without an issue discussing why
- [ ] No network code, period
- [ ] Strings in both languages
- [ ] If UI changed: a snapshot PNG in the PR description
- [ ] Commit messages that say *why*

## Conduct

Be kind, be specific, assume competence. Coaching software shouldn't nag;
neither should we.
