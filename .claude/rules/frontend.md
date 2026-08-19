# Frontend Architecture

## Component Organization

- Core UI components in `lib/klass_hero_web/components/core_components.ex`
- Shared primitives:
  - `ui_components.ex` - Basic UI elements, including the `kh_*` primitive vocabulary (`kh_button`, `kh_card`, `kh_pill`, `kh_icon`, `kh_icon_chip`, `kh_list_row`, …)
  - `composite_components.ex` - Complex composite components (search bars, filter pills, navigation)
  - `theme.ex` - Design token authority (see `DESIGN.md`)
- Per-surface layout families:
  - `marketing_components.ex` - Public marketing site (`Mk*`)
  - `parent_components.ex` - Authenticated parent app (`Pa*`)
  - `provider_layout_components.ex` - Authenticated provider chrome (`Pv*`)
  - `layouts.ex` - Root/app/admin layout shells
- Domain components:
  - `program_components.ex` - Program cards, hero sections, program lists
  - `booking_components.ex` - Booking forms, time slot selection, capacity indicators
  - `review_components.ex` - Star ratings, review lists, review forms
  - `messaging_components.ex` - Conversations and message UI
  - `participation_components.ex` - Check-in/out and session management
  - `provider_components.ex` - Provider dashboard UI

Domain UI belongs in its domain file; shared primitives in `ui_`/`core_`/`composite_`. Extraction threshold is three occurrences.

## Design Principles

- **Visual vocabulary lives in `DESIGN.md`** (repo root) — brand intent, colour roles, voice, and the don'ts list. This file covers the *code* rules; DESIGN.md covers *what things should look like and why*
- **Mobile-first responsive design** - all UI elements designed for mobile before desktop
- Reusable component patterns with clear prop interfaces
- Consistent spacing and typography using Tailwind design tokens
- Tailwind CSS utility classes for styling

## Typography

- **Always use `Theme.typography(:variant)`** for headings and display text in component/page templates — never raw `font-display` or `font-sans` on those elements
- Root/layout-level base font (e.g. `class="font-sans"` on `<body>` in `root.html.heex`) is allowed as a defense-in-depth default
- Available variants: `:hero`, `:page_title`, `:section_title`, `:cta`, `:card_title`, `:body`, `:body_small`, `:caption`
- Font configuration lives in `assets/css/app.css` (`@theme` block: `--font-sans`, `--font-display`) and `lib/klass_hero_web/components/theme.ex`
- Enforced by `mix lint_typography` in the precommit pipeline
- For justified exceptions, add `<%!-- typography-lint-ignore: reason --%>` on the line

## Important Notes

- **Mobile-first design mandatory** - every design element must be designed mobile-first before desktop
- For "app wide" template imports, you can import/alias into the `klass_hero_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponents, and all modules that do `use KlassHeroWeb, :html`
