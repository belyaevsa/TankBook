# Brand – the app icon

*The mark is the fuel pump: body with its window, base line, hose to a spout, and a checkmark,
in `taillight` on `midnight` (`docs/DESIGN.md` → app icon; product owner, 2026-08-30: "the pump
icon was absolutely fine"). It is the mark Welcome and the site header have carried since P1.*

| File | What | Used by |
|---|---|---|
| `icon.svg` | **the master**, vector, 52-unit grid, full-bleed on the token ground | everything below; copied verbatim to `site/static/icon.svg` |
| `AppIcon-dark-1024.png` | `taillight` on `#101318` | app icon (Dark); site touch icon and favicon; press page |
| `AppIcon-light-1024.png` | `taillight.light` on `#F5F6F8` | app icon (Any / light); press page |
| `AppIcon-tinted-1024.png` | white strokes on transparent | app icon (Tinted) |
| `alt-pistol-plug/` | the generated gas-pistol-and-charging-plug alternative (objects layer, prompt, three appearances, unframed) | the canvas Brand page only |

Re-render after editing the master:

```
rsvg-convert -w 1024 -h 1024 icon.svg | magick - -alpha off AppIcon-dark-1024.png
sed -e 's/#101318/#F5F6F8/g' -e 's/#F4503A/#CE3422/g' icon.svg | rsvg-convert -w 1024 -h 1024 | magick - -alpha off AppIcon-light-1024.png
sed -e 's/<rect[^>]*\/>//' -e 's/#F4503A/#FFFFFF/g' icon.svg | rsvg-convert -w 1024 -h 1024 > AppIcon-tinted-1024.png
```

Then copy the three into `ios/App/Resources/Assets.xcassets/AppIcon.appiconset/`, re-render
`BrandMark.imageset` (276 px from the dark and light PNGs), `site/static/apple-touch-icon.png`
(180 px) and `favicon.ico` (64/32/16). Full-bleed squares, no alpha on the opaque pair – iOS
applies the mask; never pre-round the corners.
