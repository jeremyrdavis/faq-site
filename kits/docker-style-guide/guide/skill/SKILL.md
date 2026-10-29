---
name: docker-style-guide
description: Apply or evaluate the Docker style guide for web UI
version: 1.0.0
---

# docker-style-guide v1.0.0

The guide is `/usr/share/docker-style-guide/STYLE_GUIDE.md`; the tokens are `/usr/share/docker-style-guide/tokens.css`. Read both before you write or review anything. Rules 1–7 are **Blocking**. Rule 8 is a **Suggestion** and never counts toward `blocking`.

## Applying (developer)

Write `styles.css` so every check below passes. Link order in `index.html` is `tokens.css` then `styles.css`. Add class names to `index.html` if you need them; change nothing else in it.

## Evaluating (reviewer)

Run each check literally from the repo root. Every hit is one Blocking item, tagged with its rule number. Do not invent additional blocking criteria. Do not run checks against `tokens.css`; it is the source of values.

1. **Colors.** Hits for either command:
   - `grep -nEi '#[0-9a-f]{3,8}\b|\b(rgb|rgba|hsl|hsla|hwb|lab|lch|oklch|oklab|color)\(' styles.css`
   - `grep -nEi '(color|background|border|outline|fill|stroke|shadow)[a-z-]*\s*:[^;]*\b(black|white|red|green|blue|gray|grey|yellow|orange|purple|pink|brown|navy|teal|silver|gold)\b' styles.css`
2. **Fonts and type scale.**
   - `grep -nE 'font-family' styles.css` — every hit must be exactly `var(--font-sans)`. Anything else is a hit.
   - `grep -nE 'font-size\s*:' styles.css` — every hit must be `var(--fs-…)`. A literal length or keyword is a hit.
   - `grep -nEi '@import|@font-face|fonts\.(googleapis|gstatic)' styles.css index.html` — any hit.
3. **Spacing.** `grep -nE '(^|[^a-z-])(margin|padding|gap|row-gap|column-gap|inset|top|right|bottom|left)[a-z-]*\s*:' styles.css`, then inspect each declaration (not each line: `border` and `outline` widths on the same line are exempt). A hit is any literal length (`px`, `rem`, `em`, `%`, `vw`) that is not inside `var(--space-…)`. `0`, `auto` and `var(--space-…)` pass. `calc()` passes only if every length in it is a `var(--space-…)`.
4. **Layout.** From `computed.json`: `layout.mobile.scrollWidth` must be ≤ `layout.mobile.clientWidth` (same for desktop); `layout.desktop.mainContentWidth` must be ≤ 740 (the value of `--measure`); and `layout.desktop.mainLeft` and `mainRight` must differ by at most 2 (centered). In `styles.css`, `var(--measure)` must appear as a `max-width`. Also look at `mobile.png` and `desktop.png`: clipped or overlapping text is a hit.
5. **Focus.** From `computed.json`, `focus.a` and `focus.summary` must each have `outlineStyle` not `none`, `outlineWidth` ≥ 2px, and `outlineColor` different from `backgroundColor`. Also: `grep -nE 'outline\s*:\s*(none|0)' styles.css` — a hit counts only if no `:focus-visible` rule in `styles.css` sets a visible outline. `grep -nE 'tabindex="-1"' index.html` — any hit. `index.html` must still use `<details>` and `<summary>`.
6. **Contrast.** `computed.json` `contrast.body` is the ratio of `body` text color to its effective background, and `contrast.summary` the same for `summary`. Either below 4.5 is a hit. To recompute by hand: linearize each sRGB channel (`c/255`, then `c/12.92` if ≤ 0.03928 else `((c+0.055)/1.055)^2.4`), `L = 0.2126R + 0.7152G + 0.0722B`, ratio = `(Lmax+0.05)/(Lmin+0.05)`.
7. **Inline styles.** `grep -nE 'style\s*=' index.html` and `grep -n '!important' styles.css` — any hit.
8. **Tone (Suggestion only).** Judgment on whitespace, calm and a single accent. Put findings under Suggestions, never under Blocking, and never in `blocking`.

`blocking` is the number of numbered Blocking items. If two items come from the same line for the same rule, count one.
