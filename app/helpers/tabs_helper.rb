# A segmented control + its ARIA tab panels, driven by the shared `tabs`
# Stimulus controller (data-tabs-target). Pass an array of tabs, each a hash of
# { id:, label:, panel: } where panel is already-rendered HTML (from `render`
# for a partial, or `capture do … end` for inline markup). The first tab shows;
# the rest start hidden.
#
#   <%= segmented_tabs [
#         { id: "series", label: "Series",
#           panel: render("admin/books/series_membership", record: @record, book: @book) },
#       ] %>
module TabsHelper
  def segmented_tabs(tabs, aria_label: "Sections")
    segments = safe_join(tabs.each_with_index.map do |tab, i|
      tag.button tab[:label], type: "button", class: "segmented__seg", role: "tab",
        id: "seg-#{tab[:id]}",
        aria: { controls: "panel-#{tab[:id]}", selected: i.zero? },
        tabindex: (i.zero? ? "0" : "-1"),
        data: { tabs_target: "tab", action: "click->tabs#show" }
    end)

    panels = safe_join(tabs.each_with_index.map do |tab, i|
      # `narrow: true` constrains a short-content panel to a centered ~60% on
      # desktop (full width on mobile) — good for lists, not for wide URLs.
      tag.div tab[:panel],
        class: class_names("tabs__panel", "tabs__panel--narrow" => tab[:narrow]),
        role: "tabpanel", id: "panel-#{tab[:id]}", aria: { labelledby: "seg-#{tab[:id]}" },
        tabindex: "0", hidden: !i.zero?,
        data: { tabs_target: "panel" }
    end)

    control = tag.div segments, class: "segmented", role: "tablist",
      aria: { label: aria_label }, data: { action: "keydown->tabs#key" }

    tag.div safe_join([ control, panels ]), data: { controller: "tabs" }
  end
end
