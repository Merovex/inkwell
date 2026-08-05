# Inkwell — conventions for Claude

## Rails standards: rails-best-practices-core is ALWAYS in force

Before writing, refactoring, or reviewing any Ruby/Rails code in this repo,
load the `rails-best-practices-core` skill (via the Skill tool) and apply it.
This is not optional or judgment-based — treat that skill's contents as part
of these instructions for every Rails task, not just when a review is asked
for. (The `/dhh` skill layers a review voice on top; the standards themselves
live in rails-best-practices-core.)

The most-violated rule, restated here so it is ambient even before the skill
loads — **everything is CRUD**: no custom member/collection actions in
`config/routes.rb`. Model the verb as a noun resource (subscribe →
`resource :subscription`, archive → `resource :archive`, accept →
`resource :acceptance`; POST creates the state, DELETE undoes it). Toggle
actions are doubly banned — split them into create/destroy so each request
names its direction instead of flipping whatever it finds.

## View components: reuse, don't re-roll

Before writing markup for a UI pattern, check `app/views/shared/` and the living
style guide (`app/views/admin/static/theme.html.erb`, `/admin/theme` when the app
is running) for an existing component. If a partial exists for the shape you
need, use it — extend it with a new local rather than copying its markup into a
view. Duplicated component markup drifts (it already happened once with list
rows) and breaks styling/accessibility fixes made in one place.

### List rows (`.list` / `.list__item`)

Every `.list` renders its rows through **`shared/list_item`** — never hand-roll
`.list__item` markup, and never use `<ul>`/`<li>` for these lists:

```erb
<div class="list">
  <%= render "shared/list_item", href: path, title: record.title, ... %>
</div>
```

The partial covers: avatars (`avatar_user:` / `avatar_src:` / initials /
`avatar_spacer:` / `avatar: false`), title badges (`badge:`, `badge_variant:`,
`client_visible:`), byline chips, excerpt, scheduled/pinned flags, comment
count, a delete button (`discard_path:` + `discard_title:`/`discard_aria:`/
`discard_confirm:`), and arbitrary trailing buttons via `actions:` (build with
`capture`). Rows without a link omit `href:`; compact stat rows (analytics)
pass `title_tag: "span"`. See the locals comment at the top of
`app/views/shared/_list_item.html.erb` for the full contract.

Accessibility contract: the row is an `<article>`, the title is a real `<h3>`
(via `title_tag:`), and the whole middle column is the link (`a.list__body`).
If the partial can't express a new row variant, add a local to the partial —
don't fork the markup.

The one sanctioned exception: comment-thread rows (`.list__item.comment` in
`admin/comments/`, `circles/pulses/`) — their rich-text/menu content and
turbo-frame swap targets don't fit the summary-row shape.

## CSS cascade hazards (learned the hard way)

- **`lexxy.css` is unlayered** and loads before the app styles — its rules
  beat EVERY `@layer` rule regardless of specificity (it styles
  `vnd.actiontext.*` attachments, e.g. squeezing imgs to 1em). A counter-rule
  must also be unlayered, in a sheet that loads later (they load
  alphabetically via `stylesheet_link_tag :app`).
- **Never size `.avatar` with `em` on the avatar element itself** — `.avatar`
  derives its own font-size from `--avatar-size`, so the em chases its tail
  and collapses. Declare a `rem` value on the element (an element's own
  `--avatar-size` also beats any value inherited from a parent).
- Inline chips that must sit on the text baseline (e.g. `.mention`) should be
  plain **inline** boxes — an inline-flex chip exports its first item's
  synthesized box baseline and rides high.
