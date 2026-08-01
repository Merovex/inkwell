require "net/http"
require "json"

# Thin Cloudflare API client for the custom-domain onboarding flow: create /
# read / delete a custom hostname on the kindredquill.com zone, and PUT / DELETE
# the HOSTNAMES KV mapping the edge Worker reads. Only the calls the flow needs
# — not a general SDK.
#
# The API token is read from credentials (cloudflare.api_token) and needs, per
# the runbook: Zone → SSL and Certificates → Edit on kindredquill.com, plus
# Account → Workers KV Storage → Edit. Non-secret ids come from config.x.
# cloudflare. Injectable everywhere it's used so tests pass a fake instead.
module Cloudflare
  class Client
    class Error < StandardError; end

    BASE = "https://api.cloudflare.com/client/v4".freeze

    # DV certificate over a TXT record — "pre-validation": the cert can issue
    # BEFORE DNS cuts over, avoiding the TLS-error window "http" would open.
    def create_custom_hostname(hostname)
      body = { hostname: hostname, ssl: { method: "txt", type: "dv" } }
      result = post("/zones/#{zone_id}/custom_hostnames", body)
      CustomHostname.new(result)
    end

    def get_custom_hostname(id)
      CustomHostname.new(get("/zones/#{zone_id}/custom_hostnames/#{id}"))
    end

    def delete_custom_hostname(id)
      request(Net::HTTP::Delete, "/zones/#{zone_id}/custom_hostnames/#{id}")
      true
    end

    # KV contract: the key is the bare lowercase hostname, the value is the plain
    # account slug — no JSON wrapper (edge/src/index.js reads a bare string).
    def kv_put(hostname, slug)
      request(Net::HTTP::Put, kv_path(hostname), raw_body: slug)
      true
    end

    def kv_delete(hostname)
      request(Net::HTTP::Delete, kv_path(hostname))
      true
    end

    private
      def kv_path(hostname)
        "/accounts/#{account_id}/storage/kv/namespaces/#{kv_namespace_id}/values/#{ERB::Util.url_encode(hostname)}"
      end

      def cf = Rails.configuration.x.cloudflare
      def zone_id = cf.zone_id
      def account_id = cf.account_id
      def kv_namespace_id = cf.kv_namespace_id

      def token
        Rails.application.credentials.dig(:cloudflare, :api_token) ||
          raise(Error, "Cloudflare API token missing (credentials: cloudflare.api_token)")
      end

      def get(path) = request(Net::HTTP::Get, path).fetch("result")
      def post(path, body) = request(Net::HTTP::Post, path, json_body: body).fetch("result")

      # One request/parse/error path for every verb. KV endpoints answer with a
      # bare "success" envelope and no result; the API endpoints wrap `result`.
      def request(verb, path, json_body: nil, raw_body: nil)
        uri = URI("#{BASE}#{path}")
        req = verb.new(uri)
        req["Authorization"] = "Bearer #{token}"
        if json_body
          req["Content-Type"] = "application/json"
          req.body = json_body.to_json
        elsif raw_body
          req["Content-Type"] = "text/plain"
          req.body = raw_body
        end

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        parse(response, path)
      end

      def parse(response, path)
        parsed = response.body.present? ? JSON.parse(response.body) : {}
        unless response.is_a?(Net::HTTPSuccess) && parsed.fetch("success", true)
          messages = Array(parsed["errors"]).map { |e| e["message"] }.join("; ")
          raise Error, "Cloudflare #{path} failed (#{response.code}): #{messages.presence || response.body}"
        end
        parsed
      rescue JSON::ParserError
        raise Error, "Cloudflare #{path} returned non-JSON (#{response.code})"
      end
  end
end
