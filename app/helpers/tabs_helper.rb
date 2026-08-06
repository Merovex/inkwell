# A segmented control + its ARIA tab panels, driven by the shared `tabs`
# Stimulus controller (data-tabs-target). Pass an array of tabs, each a hash of
# { id:, label:, panel: } where panel is already-rendered HTML (from `render`
# for a partial, or `capture do … end` for inline markup). The first panel tab
# shows (or the one whose id matches `selected:` — pass params[:tab] to let
# links deep-link a tab); the rest start hidden.
#
# A tab may carry { href: } instead of { panel: }: it renders as a link
# segment that navigates — for a sibling page wearing the same control (e.g.
# System settings ⇄ Domain). Links stay out of the Stimulus roving-tabindex
# wiring, so they're Tab-key reachable but arrow keys skip them.
#
#   <%= segmented_tabs [
#         { id: "series", label: "Series",
#           panel: render("admin/books/series_membership", record: @record, book: @book) },
#       ] %>
module TabsHelper
  def segmented_tabs(tabs, aria_label: "Sections", selected: nil)
    selected_id = tabs.find { |t| t[:panel] && t[:id].to_s == selected.to_s }&.dig(:id) ||
      tabs.find { |t| t[:panel] }&.dig(:id)

    segments = safe_join(tabs.map do |tab|
      if tab[:href]
        link_to tab[:label], tab[:href], class: "segmented__seg", role: "tab",
          aria: { selected: false }, tabindex: "0"
      else
        on = tab[:id] == selected_id
        tag.button tab[:label], type: "button", class: "segmented__seg", role: "tab",
          id: "seg-#{tab[:id]}",
          aria: { controls: "panel-#{tab[:id]}", selected: on },
          tabindex: (on ? "0" : "-1"),
          data: { tabs_target: "tab", action: "click->tabs#show" }
      end
    end)

    panels = safe_join(tabs.select { |t| t[:panel] }.map do |tab|
      # `narrow: true` constrains a short-content panel to a centered ~60% on
      # desktop (full width on mobile) — good for lists, not for wide URLs.
      tag.div tab[:panel],
        class: class_names("tabs__panel", "tabs__panel--narrow" => tab[:narrow]),
        role: "tabpanel", id: "panel-#{tab[:id]}", aria: { labelledby: "seg-#{tab[:id]}" },
        tabindex: "0", hidden: tab[:id] != selected_id,
        data: { tabs_target: "panel" }
    end)

    control = tag.div segments, class: "segmented", role: "tablist",
      aria: { label: aria_label }, data: { action: "keydown->tabs#key" }

    tag.div safe_join([ control, panels ]), data: { controller: "tabs" }
  end
end
