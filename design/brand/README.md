# Brand – the app icon

*The mark is a gas pistol and a charging plug facing each other inside a thin frame: fuel in
`taillight`, electric in `headlight`, ink frame on `midnight` (`docs/DESIGN.md` → app icon,
product owner, 2026-08-30).*

The two objects were **generated** (`imagegen`, Gemini image model; the exact prompt is
`icon-prompt.txt`), then extracted into `icon-objects.png` – an alpha layer with the colours
snapped to the palette tokens. Everything else is composed from that layer, never redrawn:

| File | What | Used by |
|---|---|---|
| `icon-objects.png` | the two objects, alpha, token colours – **the master** | everything below |
| `AppIcon-dark-1024.png` | objects at 700 px inside the ink frame on `#101318` | app icon (Dark), site favicon / touch icon / `icon.svg` |
| `AppIcon-light-1024.png` | objects recoloured to the light tokens, frame `ink.light`, on `#F5F6F8` | app icon (Any / light) |
| `AppIcon-tinted-1024.png` | objects and frame in white on transparent | app icon (Tinted) |
| `AppIcon-dark-unframed-1024.png` | the unframed alternate, kept for the record | canvas Brand page |

Re-render after changing the master (all ImageMagick, see the shell history in the P6.6 row of
`docs/TASKS.md`); copy the three `AppIcon-*` files into
`ios/App/Resources/Assets.xcassets/AppIcon.appiconset/`. Full-bleed squares, no alpha on the
opaque pair – iOS applies the mask; never pre-round the corners.
