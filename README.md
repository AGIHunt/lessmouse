# LessMouse

> Your keyboard coach on the menu bar — it watches how you type, spots the
> slow habits, and shows you the shortcut that fixes them.

**Work in progress.** Full documentation lands with the first release.

## Privacy (the whole policy)

LessMouse **never records what you type**. It counts:

- shortcuts you already use (⌘C, ⌥⌫, …),
- navigation keys (backspace, arrows, Home/End, …),
- detected slow patterns (e.g. "five backspaces in two seconds").

Aggregate counts only, stored locally in
`~/Library/Application Support/LessMouse/stats.json`, readable by you at any
time. The codebase has **zero network access and zero third-party
dependencies** — audit it, it's the point.

## Build

```bash
swift build
swift test
swift run LessMouse
```

macOS 14+, Swift 5.9+. See also [简体中文文档](README.zh-CN.md).

## License

MIT — see [LICENSE](LICENSE).
