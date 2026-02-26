# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require_relative "checks_parser"

module CheckTimeline
  module Sources
    # Fetches check and payment data from two REST endpoints:
    #
    #   GET /public/checks/:id
    #   GET /public/checks/:id/payments
    #
    # The check endpoint returns a JSON:API document:
    #   {
    #     "data": {
    #       "id": "...",
    #       "type": "checks",
    #       "attributes": { ... },
    #       "relationships": { ... }
    #     },
    #     "included": [ ... ]
    #   }
    #
    # All monetary values in the API are already in cents (e.g. total_cents: 400).
    #
    # Required environment variables:
    #   CHECKS_API_BASE_URL  - e.g. https://api.example.com
    #   CHECKS_API_KEY       - sent as the X-API-Key header
    #   CHECKS_APP_NAME      - sent as the X-App-Name header
    class ChecksApiSource < BaseSource
      include ChecksParser

      ENV_BASE_URL = "CHECKS_API_BASE_URL"
      ENV_API_KEY  = "CHECKS_API_KEY"
      ENV_APP_NAME = "CHECKS_APP_NAME"

      def available?
        [ENV_BASE_URL, ENV_API_KEY, ENV_APP_NAME].all? { |var| !ENV[var].to_s.strip.empty? }
      end

      def fetch
        fetch_check_events + fetch_payment_events
      end

      def check_total_cents
        @check_total_cents
      end

      private

      # -----------------------------------------------------------------------
      # Check endpoint  GET /public/checks/:id
      # -----------------------------------------------------------------------

      def fetch_check_events
        endpoint = "/public/checks/#{check_id}"
        response = connection.get(endpoint)
        handle_response!(response, endpoint: endpoint)

        doc = parse_json!(response.body, endpoint: endpoint)

        # Capture the authoritative total_cents from the check record so the
        # Timeline can display it directly rather than summing event amounts.
        @check_total_cents = parse_check_total_cents(doc)

        parse_check_document(doc)
      end

      # -----------------------------------------------------------------------
      # Payments endpoint  GET /public/checks/:id/payments
      # -----------------------------------------------------------------------

      def fetch_payment_events
        endpoint = "/public/checks/#{check_id}/payments"
        response = connection.get(endpoint)
        handle_response!(response, endpoint: endpoint)

        doc = parse_json!(response.body, endpoint: endpoint)
        parse_payments_document(doc)
      end

      # -----------------------------------------------------------------------
      # HTTP connection
      # -----------------------------------------------------------------------

      def connection
        @connection ||= Faraday.new(url: base_url) do |f|
          f.request  :retry, max: 3, interval: 0.5, backoff_factor: 2,
                             exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
          f.request  :json
          f.response :json, content_type: /\bjson$/
          f.adapter  Faraday.default_adapter

          f.headers["X-API-Key"]  = api_key
          f.headers["X-App-Name"] = app_name
          f.headers["Accept"]     = "application/json"
          f.headers["User-Agent"] = "check-timeline/1.0"
        end
      end

      def base_url
        @base_url ||= ENV.fetch(ENV_BASE_URL).chomp("/")
      end

      def api_key
        @api_key ||= ENV.fetch(ENV_API_KEY)
      end

      def app_name
        @app_name ||= ENV.fetch(ENV_APP_NAME)
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
