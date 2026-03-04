# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require_relative "checks_parser"

module CheckTimeline
  module Sources
    # Fetches all check data from a single REST endpoint:
    #
    #   GET /checks/checks/:id?include=payments,paper_trail_versions
    #
    # The endpoint returns a JSON:API document with payments and PaperTrail
    # version records sideloaded in the "included" array:
    #   {
    #     "data": {
    #       "id": "...",
    #       "type": "checks",
    #       "attributes": { ... },
    #       "relationships": { ... }
    #     },
    #     "included": [
    #       { "type": "payments", ... },
    #       { "type": "versions", ... }
    #     ]
    #   }
    #
    # All monetary values in the API are already in cents (e.g. total_cents: 400).
    #
    # Required environment variables:
    #   CHECKS_API_KEY  - sent as the X-API-KEY request header
    #
    # Required runtime options:
    #   gid:  - user identifier sent as the X-On-Behalf-Of request header
    #           (only required when fetching from the live API)
    class ChecksApiSource < BaseSource
      include ChecksParser

      BASE_URL    = "https://api.production.sohohousedigital.com"
      ENV_API_KEY = "CHECKS_API_KEY"

      def available?
        !ENV[ENV_API_KEY].to_s.strip.empty? &&
          !options[:gid].to_s.strip.empty?
      end

      def fetch
        fetch_all_events
      end

      def check_total_cents
        @check_total_cents
      end

      private

      # -----------------------------------------------------------------------
      # Single endpoint  GET /checks/checks/:id?include=payments,paper_trail_versions
      # -----------------------------------------------------------------------

      def fetch_all_events
        endpoint = "/checks/checks/#{check_id}"
        response = connection.get(endpoint, include: "payments,paper_trail_versions")
        handle_response!(response, endpoint: endpoint)

        doc = parse_json!(response.body, endpoint: endpoint)

        # Capture the authoritative total_cents from the check record so the
        # Timeline can display it directly rather than summing event amounts.
        @check_total_cents = parse_check_total_cents(doc)

        check_events   = parse_check_document(doc)
        payment_events = parse_payments_from_doc(doc)
        version_events = parse_versions_from_doc(doc)

        check_events + payment_events + version_events
      end

      # Parse payment records sideloaded in the "included" array.
      def parse_payments_from_doc(doc)
        included = doc["included"] || []
        payments = included.select { |r| r["type"] == "payments" }
        return [] if payments.empty?

        parse_payments_document(payments)
      end

      # Parse PaperTrail version records sideloaded in the "included" array.
      def parse_versions_from_doc(doc)
        included = doc["included"] || []
        return [] unless included.any? { |r| r["type"] == "versions" }

        currency = doc.dig("data", "attributes", "currency") || "GBP"
        parse_versions_document(doc, currency: currency)
      end

      # -----------------------------------------------------------------------
      # HTTP connection
      # -----------------------------------------------------------------------

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request  :retry, max: 3, interval: 0.5, backoff_factor: 2,
                             exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
          f.request  :json
          f.response :json, content_type: /\bjson$/
          f.adapter  Faraday.default_adapter

          f.headers["X-API-KEY"]      = api_key
          f.headers["X-On-Behalf-Of"] = gid
          f.headers["Accept"]          = "application/json"
          f.headers["User-Agent"] = "check-timeline/1.0"
        end
      end

      def api_key
        @api_key ||= ENV.fetch(ENV_API_KEY)
      end

      def gid
        @gid ||= options.fetch(:gid)
      end

      # -----------------------------------------------------------------------
      # Response / JSON helpers
      # -----------------------------------------------------------------------

      def handle_response!(response, endpoint:)
        return if response.success?

        raise ApiError,
              "#{source_name} received HTTP #{response.status} from #{endpoint}. " \
              "Body: #{response.body.to_s.slice(0, 300)}"
      end

      def parse_json!(body, endpoint:)
        return body if body.is_a?(Hash) || body.is_a?(Array)

        JSON.parse(body.to_s)
      rescue JSON::ParserError => e
        raise ApiError, "#{source_name} could not parse JSON from #{endpoint}: #{e.message}"
      end
    end

    # Raised when the API returns a non-success status or unparseable body
    class ApiError < StandardError; end
  end
end
