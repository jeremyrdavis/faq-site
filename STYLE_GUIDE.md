# Docker style guide for web UI

Version 1.0.0. Source of values: the Docker Demo Design System (`docker-ds.css` v1.1.0). Tokens live in `tokens.css`; this guide says how a page must use them.

Rules 1–7 are **checkable** and any violation is Blocking. Rule 8 is judgment and is only ever a Suggestion.

| # | Rule | Kind |
|---|---|---|
| 1 | All colors come from `tokens.css` custom properties. No raw hex, `rgb()`, `hsl()` or named colors in `styles.css` (`transparent`, `currentColor`, `inherit` are fine). | checkable |
| 2 | One font stack: `font-family` is `var(--font-sans)` only. Every `font-size` is a `var(--fs-*)` token. No web fonts, no `@import` or `<link>` to font hosts. | checkable |
| 3 | Spacing uses the 4px-grid scale through `--space-1` … `--space-8` (0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4 rem). `margin`, `padding`, `gap` and `inset` take `var(--space-*)`, `0` or `auto`, never a literal length. Border and outline widths are exempt. | checkable |
| 4 | Content is one centered column no wider than `var(--measure)`. No horizontal scrolling and no clipped text at 360 px or at 1280 px. | checkable (screenshots, `computed.json`) |
| 5 | Every interactive element (`a`, `summary`, `button`) shows a visible focus state of at least 2 px, with a color that differs from its background. `summary` stays keyboard-operable: keep `<details>`/`<summary>`, no `tabindex="-1"`, no `outline: none` without a replacement. | checkable |
| 6 | Body text contrast is at least 4.5:1 against its effective background, in the default (light) scheme. | checkable (`computed.json`) |
| 7 | No inline `style=` attributes and no `!important`. | checkable |
| 8 | Tone: calm, generous whitespace, one accent color (`--accent`) used sparingly. | judgment (Suggestions only) |

## Using the tokens

- Link `tokens.css` before `styles.css`. `styles.css` sets `color-scheme: light dark` itself.
- Page background `--bg`, body text `--fg-body`, headings `--fg`, links and focus `--accent` and `--focus`, dividers `--rule`.
- Dark mode comes from the tokens (`prefers-color-scheme: dark`); do not hand-write dark colors.
