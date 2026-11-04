# RestBar brand

RestBar follows the visual language of [Dokki](https://dokki.one): monochrome, flat, and dots that mean something. It is its own product, with its own mark. Do not use Dokki's logo or wordmark on it.

## Two rules

1. **Red belongs to the moon and to keeping the Mac awake.** At rest there is one red dot, in the moon's mouth. While awake the moon itself turns red, in the menu bar and the panel, and so does the switch that holds it there. Nothing else is red: not checkboxes, not text, not warnings.
2. **Nothing is said twice.** If the timer shows the Mac is awake, no icon, subtitle or status word says so again. Before adding an element, ask what it says that nothing else on screen already does.

## The moon

The moon has two phases, and they are the product's two states.

| State | Mark |
| --- | --- |
| At rest | A crescent with one red dot |
| Awake | The full disc, in red |

## The switch

The keep-awake switch is drawn by RestBar rather than macOS, because on and off have to be told apart at a glance. On is solid red with a white knob on the right. Off is a hollow outline with a grey knob on the left.

## Name and line

- **RestBar**: one word, capital R and B. There is no separate Chinese name.
- **Line:** Keep your Mac awake while your agents work. / Agent 跑着时，别让 Mac 睡

## Colour

| Token | Value | Use |
| --- | --- | --- |
| Paper | `#191919` | App icon tile, dark brand surfaces |
| White | `#FFFFFF` | Ink on Paper |
| Logo red | `#F50233` | The moon's dot on the icon and brand images |
| Signal | `#ED0031` on light, `#FF1748` on dark | The moon and the keep-awake switch in the app |
| Control tint | `#191919` on light, `#8A8A8A` on dark | Checked boxes |

Everything else in the app is the macOS system colour for that role, so it follows light and dark. Orange is for warnings and errors only, because red is taken.

No gradients, glows, shadows, cards or decorative icons.

## The mark

`Sources/Brand.swift` is the only definition. The app, the icon and every brand image draw from it, so they cannot drift.

- Dots sit on a square grid at 80% of their cell. The crescent is symmetrical about its diagonal.
- 11 columns from 128 pixels up, 9 below that and in the app. Fewer than 9 stops reading as a moon.
- The red dot is half again the size of its neighbours and sits on the grid, in the crescent's mouth.
- The resting menu bar glyph has no dot: macOS colours it as a template, and a template has one colour.
- At 32 pixels and below a dot is too small to survive, so the icon draws the same moon as a solid shape.
- Keep clear space of at least a quarter of the mark's width. Use `-on-light` files on light backgrounds and `-on-dark` on dark.
- Do not redraw it, tilt it, recolour its dots or add dots.

## Type

- **Wordmark:** [Bitcount Grid Single](https://fonts.google.com/specimen/Bitcount+Grid+Single), weight 300, SIL Open Font License. It is used only for the wordmark in brand images. It is not bundled in the app.
- **Everything else:** the system font. The timer uses its monospaced design.
- Do not set sentences or headlines in the dot font.

## Voice

Calm and exact, like a good instrument. Say what happens to the Mac in plain words and state the limits openly: "Closing the lid still follows macOS rules" is on-brand. Avoid hype, exclamation marks and promises about battery life.

## Files

| Path | Regenerate with |
| --- | --- |
| `AppIcon.icns`, `assets/brand/*` | `scripts/Icon.swift` (instructions at the top of the file) |
| `assets/screenshots/*` | `bash scripts/screenshots.sh` |

GitHub's social card is `assets/brand/social-preview.png`. It has to be uploaded by hand under Settings → General → Social preview.
