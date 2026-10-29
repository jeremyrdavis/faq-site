# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Conventions

- Static site: `index.html`, `styles.css`, `tokens.css`. No build step, no dependencies, no web fonts.
- `tokens.css` and `STYLE_GUIDE.md` come from the `docker-style-guide` mixin. Do not edit them here.
- Branch names: `style/<topic>` for styling, `content/<issue>-<slug>` for content changes.
- Conventional commits (`style: …`, `content: …`).
- A PR body must reference the issue when one exists (`Fixes #<n>`).
