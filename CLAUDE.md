# Inkwell — conventions for Claude

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
