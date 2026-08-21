# Klass Hero — Design

The visual vocabulary for Klass Hero — what the product looks like, what each part of the
palette is *for*, and what we refuse to do. This file defines intent; it is not a token
table.

**Values live in code, and only in code.** Nothing here restates a colour value, a pixel
size, or a class string — those drift the moment they are copied.

| What | Where it is defined |
|---|---|
| Colour scales, fonts, semantic CSS variables, gradients | `assets/css/app.css` (`@theme` and `:root`) |
| Every design token as a Tailwind class string | `lib/klass_hero_web/components/theme.ex` |
| Form inputs, flash, buttons, headers | `lib/klass_hero_web/components/core_components.ex` |
| Code-level rules (component organisation, typography enforcement) | `.claude/rules/frontend.md` |
| Enforcement | `mix lint_typography`, `/review-design` |

When a value and this file disagree, **the code is right and this file is stale** — fix it.

---

## Brand

**Klass Hero**:
Berlin's marketplace for youth education, sport, and recreation. It serves three audiences
with genuinely different needs: **parents** discovering and booking activities for their
children, **providers** listing programs and running sessions, and **admins** vetting and
moderating from the Backpex backoffice.

**The vibe**:
Friendly, trustworthy, superhero-themed. Parents are handing over their children — every
design decision either earns that trust or spends it. Warmth does the earning: a warm peach
page background, white cards, generous rounding, soft shadows. Nothing cold, nothing
clinical, nothing that looks like a form to be endured.
_Avoid_: cold grey dashboards, dense enterprise tables, hard-edged cards, dramatic shadows

**Superhero, lightly**:
The metaphor lives in the wordmark and in headings ("Heroes for Our Youth"). It never
reaches body copy, never becomes a mascot, and never turns into comic-book styling beyond
the logo.
_Avoid_: speech bubbles, halftone dots, action lines, capes

---

## Voice & content

**Person**:
Second person to parents ("Find verified tutors", "Book camps instantly"). First-person
plural for the brand ("We verify every provider"). Genuine first person is reserved for
founder and about copy, where it does trust work.

**Casing**:
Sentence case for body copy and most UI. Title Case for section labels and navigation
("Featured Programs", "For Families"). ALL CAPS **only** for the wordmark.
_Avoid_: Title Case sentences, ALL CAPS buttons, ALL CAPS section headers

**Sentence shape**:
Short, confident, benefit-first. Lists of three are a recurring rhythm ("Safety First /
Easy Scheduling / Community Focused"). CTAs end in `→`.
_Avoid_: hedging, feature-first phrasing, paragraphs where a list of three would land

**Provider voice**:
Direct and business-minded — providers are running a business, not shopping. "Get paid and
grow", "insights into your business". Same warmth, less whimsy.

**Emoji**:
Language-switcher flags and the occasional avatar or info-box accent. Nowhere else.
_Avoid_: emoji in headings, marketing copy, navigation, or buttons

**German**:
Full Gettext parity, English is the source. German runs roughly 30% longer — any string in
a fixed-width element must survive that expansion. Every new `gettext` call ships with its
German translation in the same PR (`mix lint_translations` enforces it).

---

## Colour roles

The scales are `hero-blue`, `hero-yellow`, `hero-pink`, `hero-cream`, `hero-grey`, and
`hero-black`, defined in `app.css`'s `@theme`. What matters is which one you are allowed to
reach for, and when.

**Hero Blue** — the primary:
The only colour a primary call-to-action may be. Also links, focus, and informational
status. `Theme.brand_color(:primary)`, `Theme.button_variant(:primary)`,
`var(--brand-primary)`.
_Avoid_: a second competing CTA colour on one screen; blue for anything decorative

**Hero Yellow** — the accent:
Highlight, emphasis, section labels, the provider sidebar's active state, and the
`:secondary` button. Accent means *sparing* — it stops working the moment it is everywhere.
_Avoid_: yellow primary CTAs; yellow as a page or section background; yellow body text
(it fails contrast on every surface we have)

**Hero Pink** — the page base:
The warm default page background (`--bg-base`). This is the single strongest brand signal
the product has, and it is the thing most easily lost by defaulting to a grey app shell.
_Avoid_: `bg-white` or a grey shade as a full-page background; treating pink as decorative

**Hero Cream** — the alt stripe:
Muted alternate sections (`--bg-muted`), used to structure long marketing pages into bands
against the white card surfaces.
_Avoid_: a third background tone; stripes on dense app screens, where they read as noise

**Hero Grey** — structure only:
Borders, dividers, muted and subtle text, skeleton states. Never a brand colour.

**Hero Black** — text:
Headings (`--fg-primary`) and body (`--fg-body`). Also the provider sidebar background —
see *Surfaces*.

**Status colours**:
Green / yellow / red carry meaning and only meaning. `Theme.status/1` for the bordered,
tinted pill; `Theme.status_badge/1` for the solid one. `status_badge` pairs a `-100` tint
with `-800` text specifically because the lighter `-700`/`-600` pairings fall below WCAG AA.
_Avoid_: green as a decorative accent; inventing a new status tint instead of using the helper

**Contrast on warm surfaces**:
`--fg-muted` is only safe on white. Over Hero Pink and the `base_fade` gradient it measures
about 3.1:1, which fails AA. `--fg-muted-on-light` exists for exactly this and clears 4.5:1
across the whole gradient.
_Avoid_: muted text over pink or a gradient without switching to `--fg-muted-on-light`

**Arbitrary values**:
`text-[var(--token)]` and friends are sanctioned bridges to the semantic layer. Literal
arbitrary values are not.
_Avoid_: `bg-[#abc]`, `text-[13px]`, raw hex inside `style=` strings

---

## Typography

**Two families, two jobs**:
**Plus Jakarta Sans** (`font-display`) is the voice — heroes, page and section titles, CTAs.
**Outfit** (`font-sans`) is everything else — body, forms, card titles, captions.

**Always through `Theme.typography/1`**:
Eight variants cover every case: `:hero`, `:page_title`, `:section_title`, `:cta`,
`:card_title`, `:body`, `:body_small`, `:caption`. They encode family, responsive size,
weight, and tracking together, which is why picking one is a single decision rather than
four.
_Avoid_: raw `font-display` in a template (`mix lint_typography` fails the build);
hand-assembling `text-3xl font-bold tracking-tight` when a variant already says it

**Display text is always tracking-tight**:
Every display variant carries it. Loosely-tracked bold headings do not look like this brand.

Justified exceptions take `<%!-- typography-lint-ignore: reason --%>` — with a real reason.

---

## Layout & rhythm

**Mobile-first is not a preference**:
Design the small screen first, then let it grow. Review viewports are **375 / 768 / 1280**.
_Avoid_: designing at desktop width and squeezing down; horizontal scroll at 375px;
tap targets under 44px

**Container**:
`max-w-7xl mx-auto` with responsive horizontal padding. Marketing sections breathe
(`py-16 lg:py-24`); app screens are tighter.

**Collapse**:
Feature and provider grids run three-up on desktop and collapse to a single column on
mobile. Two-up intermediate states are for content that genuinely pairs.

**Spacing**:
`Theme.spacing/1` returns the Tailwind scale step, so `p-{Theme.spacing(:md)}` composes.
Six steps exist and they are enough.
_Avoid_: arbitrary margin and padding brackets

---

## Elevation, radii, borders

**Rounding is a brand signal**:
Cards are `Theme.rounded(:lg)` or `(:xl)`; buttons and inputs `(:md)`; pills, avatars,
search bars, and FABs `(:full)`. Sharp corners belong to dividers only.
_Avoid_: `rounded-none` on a surface; mixing three radii inside one component

**Borders**:
1.5px is the house weight (daisyUI `--border`). Light borders on cards, medium on inputs.

**Shadows stay soft**:
`shadow-sm` at rest, `shadow-md` on hover, `shadow-lg` for genuinely elevated surfaces.
Elevation is a hint, not a statement.
_Avoid_: heavy or coloured drop shadows; shadow *and* a strong border doing the same job

**Glass**:
`Theme.card_variant(:glass)` and the blurred overlay treatment exist for the hero search bar
and floating icon buttons. Small surfaces only.
_Avoid_: blurring a whole section

---

## Motion

**Subtle and reassuring, never flashy.** Motion here signals "this is working", not "look at
this".

`Theme.transition/1` gives the three speeds (fast / normal / slow). Scroll reveal runs
through the `ScrollReveal` hook — opacity plus a short rise, staggered for children.
Interactive lift is a light shade change plus a shadow step; CTAs and cards may scale
slightly on hover. Pending form submits fade via `phx-submit-loading`.

**Reduced motion is already handled** in `app.css`, and the reveal CSS is scoped under `.js`
so content stays visible if JavaScript never loads.
_Avoid_: animation that blocks reading; parallax; motion without a reduced-motion path;
anything bouncing that is not the hero logo

---

## Iconography & imagery

**Heroicons**, via the `hero-<name>` class pattern. Outline by default, solid for filled
states, mini for inline-with-text. Sizes come from `Theme.icon_size/1`.
_Avoid_: a second icon set; icons at arbitrary sizes

**Gradient icon chips** are the signature motif — a rounded chip with a gradient background
and a white icon, used for features, provider steps, and empty states. `kh_icon_chip`.

**Gradients** are for chips and primary CTAs. `Theme.gradient/1` names them.
_Avoid_: full-bleed gradient section backgrounds; inventing a gradient inline

**Photography** is warm, natural, and shows children in context. Program covers are rounded
with status pills overlaid in the corner. Skeletons pulse in grey.
_Avoid_: heavy filters, black and white, stock-photo staging, empty rooms

---

## Component vocabulary

**Reach for what exists; do not rebuild it.** A hand-rolled button is not just duplication —
it is a surface that will not receive the next design change.

**`kh_*` primitives** (`ui_components.ex`) are the shared vocabulary: `kh_button`, `kh_card`,
`kh_pill`, `kh_icon`, `kh_icon_chip`, `kh_list_row`, `kh_logo`, `kh_trust_mark`,
`kh_user_menu`, `kh_menu_item`.

**Surface families** compose those primitives per audience:

| Prefix | Module | Surface |
|---|---|---|
| `Mk*` | `marketing_components.ex` | public marketing site |
| `Pa*` | `parent_components.ex` | authenticated parent app |
| `Pv*` | `provider_layout_components.ex` | authenticated provider chrome |

Domain UI lives in its domain module (`program_`, `booking_`, `messaging_`,
`participation_`, `review_`, `provider_`). Shared primitives live in `ui_`, `core_`, or
`composite_`.

**Extraction threshold is three.** A one-off stays a one-off; the third occurrence becomes a
component.

One legacy primitive, `faq_item`, still lives in `ui_components.ex` and is still consumed
by `HomeLive` and `ForProvidersLive`, pending migration to the `Mk*` family. Its former
companions — `hero_section`, `feature_card`, `provider_step_card` — outlived their callers
and were deleted. Prefer `Mk*` in new work.

---

## Surfaces

The four surfaces are deliberately not uniform. Chrome tells you where you are.

**Marketing** — warm pink base, cream and white alternating bands, full-width hero, the
most expressive typography in the product.

**Parent app** — white-with-blue sidebar, softer density, children and schedule foremost.
Sidebar, topbar, and mobile bottom-tab navigation share one active-nav atom, so a new
destination is added once.

**Provider app** — **black sidebar with a yellow active accent**, an intentional inversion
of the parent surface's white-with-blue. Business-minded density.

**Admin** — Backpex. Functional, not branded; do not spend design effort here.

---

## Don'ts

The failure modes worth naming, each with the move that replaces it.

1. **Grey app shell.** → Hero Pink is the page base. Losing it loses the brand.
2. **Hand-rolled button, card, or pill.** → `kh_button`, `kh_card`, `kh_pill`.
3. **Raw `font-display` in a template.** → `Theme.typography(:variant)`. The linter fails the build.
4. **Hand-assembled type classes.** → one of the eight variants.
5. **Yellow as a call-to-action.** → Hero Blue. Yellow is accent only.
6. **Muted text on pink or a gradient.** → `--fg-muted-on-light`; `--fg-muted` fails AA there.
7. **Arbitrary literal values** (`mt-[7px]`, `bg-[#abc]`, hex in `style=`). → a `Theme` helper, or a `var(--token)` bridge.
8. **A new status colour.** → `Theme.status/1` or `Theme.status_badge/1`.
9. **Desktop-first layout.** → 375 first, then grow. Check 375 / 768 / 1280.
10. **Heavy shadows or sharp corners.** → `shadow-sm` at rest, generous radii.
11. **Emoji in headings, CTAs, or navigation.** → flags and light accents only.
12. **A new `gettext` string with no German.** → translate in the same PR, or allowlist it with a reason.
13. **Motion that blocks reading.** → subtle, and always with a reduced-motion path.
14. **Design effort spent on Backpex admin.** → it is functional, not branded.

---

## Where the design system lives

**In this repo** — `theme.ex` is the token authority, `app.css` holds the scales and
semantic variables, and the component modules hold the vocabulary. There is no docs site and
no governance board; the code is the specification and this file is its intent.

**On claude.ai** — a design-system project, *Klass Hero Design System*, carries the portable
half: a token stylesheet, logo assets, rendered swatch and component preview cards, and
three UI kits (marketing, parent, provider). It exists so on-brand mockups, decks, and
prototypes can be produced without repo access.

That project is a **build artifact**. This repo is the source of truth; the remote is
regenerated from it and never hand-edited. A hand-edit there becomes a second truth, and the
two diverge silently.

**`design_handoff/`** — several component moduledocs and the `:root` block in `app.css`
reference `design_handoff/<surface>/Sections.jsx` as the origin of the `Mk*` / `Pa*` / `Pv*`
naming. That directory has never existed in this repo or its history; it lives in the
claude.ai project. The semantic CSS variable layer in `app.css` is the compatibility bridge
to it. Read those moduledoc references as pointers to the design project, not to a path you
can open.
