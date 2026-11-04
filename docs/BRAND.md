# RestBar brand

RestBar follows the visual language of [Dokki](https://dokki.one): monochrome structure, one scarce red, and dots that mean something. It is its own product, with its own mark. Do not use Dokki's logo or wordmark on it.

## The idea

The moon has two phases, and they are the product's two states.

| State | Mark | Colour |
| --- | --- | --- |
| At rest: RestBar is not keeping the Mac awake | A crescent with one red dot | Ink, red for the dot only |
| Awake: RestBar is keeping the Mac awake | The full disc | Red |

**Red means RestBar is holding your Mac awake right now.** That is what makes it worth noticing, so do not spend it on decoration. The only red a resting screen shows is the mark's dot; checked controls use it because macOS draws them in the accent colour.

## Name and line

- **RestBar**: one word, capital R and B. There is no separate Chinese name.
- **Line:** Let your Mac rest on your schedule. / 让 Mac 按你的节奏休息

## Colour

| Token | Value | Use |
| --- | --- | --- |
| Paper | `#191919` | App icon tile, dark brand surfaces |
| White | `#FFFFFF` | Ink on Paper |
| Mark red | `#F50233` | The mark's dot, the awake menu bar glyph |
| Signal, light | `#ED0031` | Red text and glyphs on light surfaces |
| Signal, dark | `#FF1748` | Red text and glyphs on dark surfaces |
| Signal fill, dark | `#ED002F` | Red behind a white label on dark |

Everything else in the app is the macOS system colour for that role, so it follows light and dark. Orange stays reserved for warnings (low battery, sleep disabled system-wide).

No gradients, glows or drop shadows on brand images.

## The mark

`Sources/Brand.swift` is the only definition. The app, the icon and every brand image draw from it, so they cannot drift.

- Dots sit on a square grid at 80% of their cell. The red dot is one and a half times its neighbours and sits on the grid.
- 15 columns from 128 pixels up, 11 from 48, and 9 in the menu bar.
- At 32 pixels and below a dot is too small to survive, so the icon draws the same moon as a solid shape.
- At rest the menu bar glyph is a template in one colour, so macOS can colour it for the bar. Its dot is drawn in that same colour.
- Keep clear space of at least a quarter of the mark's width. Use `-on-light` files on light backgrounds and `-on-dark` on dark.
- Do not redraw it, tilt it, recolour its dots or add dots.

## Type

- **Wordmark:** [Bitcount Grid Single](https://fonts.google.com/specimen/Bitcount+Grid+Single), weight 300, SIL Open Font License. It is used only for the wordmark in brand images. It is not bundled in the app.
- **Everything else:** the system font. Timers use its monospaced design.
- Do not set sentences or headlines in the dot font.

## Voice

Calm and exact, like a good instrument. Say what happens to the Mac in plain words and state the limits openly: "Closing the lid still follows macOS rules" is on-brand. Avoid hype, exclamation marks and promises about battery life.

## Files

| Path | Regenerate with |
| --- | --- |
| `AppIcon.icns`, `assets/brand/*` | `scripts/Icon.swift` (instructions at the top of the file) |
| `assets/screenshots/*` | `scripts/PanelShot.swift` (instructions at the top of the file) |

GitHub's social card is `assets/brand/social-preview.png`. It has to be uploaded by hand under Settings → General → Social preview.
