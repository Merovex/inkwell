# One DV TXT record Cloudflare is waiting on: the name to create and the exact
# value it must carry. Cloudflare hands back a list of these, and the shape
# round-trips through the custom_domains.validation_records JSON column, so
# this is the one type the API client, the model, the diagnosis, and the DNS
# instructions all speak.
class CustomDomain::ValidationRecord < Data.define(:txt_name, :txt_value)
  # Both directions of the JSON column, with the string keys Cloudflare itself
  # uses — so a stored record and a freshly-fetched one are indistinguishable.
  def self.wrap(records)
    Array(records).filter_map do |record|
      record = record.to_h.stringify_keys
      new(txt_name: record["txt_name"], txt_value: record["txt_value"]) if record["txt_name"].present?
    end
  end

  def as_json(...) = { "txt_name" => txt_name, "txt_value" => txt_value }
end
