# Icon derivation

Two sources of truth, both SVG (readable by humans, diffable by git):

- `MenuBarIcon.svg` — the menu bar mark: a keycap with a filled dot at its
  lower right ("keyboard + notification"). Alpha-only template art; macOS
  recolors it per menu bar appearance.
- `AppIcon.svg` — the app icon: clean paper `#F7F8F7`, one ink keycap
  `#0B0F0C` carrying a white ⌘, one green dot `#2CDB5C` top-right. The green
  is spent exactly once, same as everywhere else in the product.

Deriving the binaries (`scripts/make-icons.swift`, plain CoreGraphics/CoreText
so no external SVG tooling is needed):

| Output | Source of geometry | Used by |
|---|---|---|
| `Sources/LessMouseCore/Resources/MenuBarIcon.png` (36px = 18pt @2x, template) | `MenuBarIcon.svg` | `ProductMark.menuBar` |
| `assets/AppIcon-1024.png` | `AppIcon.svg` | `scripts/make-app.sh` → `AppIcon.icns` |

```bash
swift scripts/make-icons.swift           # regenerate
swift scripts/make-icons.swift --check   # CI: committed art matches geometry
```

The geometry is duplicated between SVG and script — deliberate, so the build
needs no SVG renderer. If you change one, change both and re-run.
