module SeoHelper
  # A <script type="application/ld+json"> block. json_escape neutralises any
  # "</script>" in the data so content can't break out of the tag.
  def json_ld_tag(data)
    content_tag :script, raw(json_escape(data.compact.to_json)), type: "application/ld+json"
  end
end
