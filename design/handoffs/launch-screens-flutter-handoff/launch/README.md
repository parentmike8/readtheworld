# Launch Screen assets — Read the World

Replaces the placeholder 1x1 `LaunchImage` PNGs. Flat paper, centered loading lockup (wordmark + hairline + the clay dot resting on its line). Calm, on-brand, no text that would feel awkward on a flash frame.

## Recommended: storyboard + centered logo (best across all devices)
This is the cleanest fix for `LaunchScreen.storyboard`.

1. In `LaunchScreen.storyboard`, set the root view **background color to Paper `#F3F0E9`** (RGB 243, 240, 233).
2. Drop the transparent logo into the `LaunchImage` image set (Assets):
   - `LaunchImage.png`      · 348 × 104  (@1x)
   - `LaunchImage@2x.png`   · 696 × 208  (@2x)
   - `LaunchImage@3x.png`   · 1044 × 312 (@3x)
3. Keep the centered `imageView` with `contentMode = Aspect Fit`. The lockup stays centered and crisp on every device; the paper background fills edge-to-edge.

The logo PNGs are transparent, so they sit correctly on the paper background.

## Alternative: full-bleed launch image (single-image / scaleAspectFill)
If the storyboard uses one full-screen image with `Aspect Fill` instead of a background color + centered logo, use these pre-composed paper frames:

- `launch-universal-1290x2796.png` — safe universal choice; the flat background + centered mark crop cleanly on any iPhone aspect ratio.
- `launch-iphone-6.9-1290x2796.png` — iPhone 6.9″ (Pro Max)
- `launch-iphone-6.1-1179x2556.png` — iPhone 6.1″ (Pro)
- `launch-ipad-12.9-2048x2732.png`  — iPad 12.9″

All are RGB, no transparency.

## Colors used
- Paper background `#F3F0E9`
- Ink wordmark `#211F1A`
- Clay dot + period `#B06A47`
- Hairline `#E0DACE`

Regenerate or tweak from `Read the World - Launch Screen.dc.html` in the project root.
