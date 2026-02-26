# frozen_string_literal: true

require "json"
require_relative "checks_parser"

module CheckTimeline
  module Sources
    # Reads a local check JSON file in the same JSON:API format returned by
    # GET /public/checks/:id and optionally a companion payments file.
    # PaperTrail version records are parsed automatically from the check file's
    # own "included" array when present — no separate file is required.
    #
    # This is useful for:
    #   - Offline / local development without API access
    #   - Investigating a specific check using a saved API response
    #   - Running the tool in environments where the API is unreachable
    #   - Combining a saved check snapshot with live Raygun exception files
    #
    # Usage (check file only):
    #   CheckFileSource.new(
    #     check_id: "8ac70c0e-8760-47b6-92f1-a8bf26e86a77",
    #     check_file: "path/to/check.json"
    #   )
    #
    # Usage (check file + payments file):
    #   CheckFileSource.new(
    #     check_id: "8ac70c0e-8760-47b6-92f1-a8bf26e86a77",
    #     check_file:    "path/to/check.json",
    #     payments_file: "path/to/payments.json"
    #   )
    #
    # The check_id option is used for event ID generation. If omitted, the id
    # is read directly from the check file's data.id field.
    #
    # File format — check.json must match the JSON:API envelope:
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
    # File format — payments.json must be one of:
    #   - A root JSON array:              [ { ... }, { ... } ]
    #   - A JSON:API collection:          { "data": [ { ... } ] }
    #   - A plain wrapper object:         { "payments": [ { ... } ] }
    #
    # If the check file's "included" array contains records with type == "versions"
    # (i.e. PaperTrail records sideloaded by the API), they are parsed automatically
    # into version events — no extra flag or file is needed.
    class CheckFileSource < BaseSource
      include ChecksParser

      def initialize(check_id:, **options)
        super
        @check_file_path    = options[:check_file]
        @payments_file_path = options[:payments_file]
      end

      def available?
        return false if @check_file_path.nil? || @check_file_path.to_s.strip.empty?

        unless File.file?(@check_file_path)
          warn_log "Check file not found: #{@check_file_path}"
          return false
        end

        true
      end

      def fetch
        check_events   = load_check_events
        payment_events = @payments_file_path ? load_payment_events : []
        check_events + payment_events
      end

      private

      # ------------------------------------------------------------------
      # Check file
      # ------------------------------------------------------------------

      def load_check_events
        doc = read_json_file!(@check_file_path)

        # Validate that this looks like a check document before proceeding
        unless doc.is_a?(Hash) && doc["data"]
          raise SourceError,
                "#{@check_file_path} does not look like a check JSON:API document " \
                "(expected a root \"data\" key)"
        end

        # If check_id was not passed explicitly on the CLI, derive it from
        # the file itself so event IDs are still deterministic.
        derive_check_id_from_doc!(doc) if @check_id.nil? || @check_id.to_s.strip.empty?

        check_events   = parse_check_document(doc)
        version_events = parse_versions_from_doc(doc)
        check_events + version_events
      end

      # ------------------------------------------------------------------
      # Payments file (optional)
      # ------------------------------------------------------------------

      def load_payment_events
        return [] if @payments_file_path.nil?

        unless File.file?(@payments_file_path)
          warn_log "Payments file not found: #{@payments_file_path} — skipping payment events."
          return []
        end

        doc = read_json_file!(@payments_file_path)
        parse_payments_document(doc)
      end

      # ------------------------------------------------------------------
      # Helpers
      # ------------------------------------------------------------------

      # Read and parse a JSON file, raising a descriptive SourceError on failure.
      def read_json_file!(path)
        raw = File.read(path)
        JSON.parse(raw)
      rescue Errno::ENOENT
        raise SourceError, "File not found: #{path}"
      rescue Errno::EACCES
        raise SourceError, "Permission denied reading file: #{path}"
      rescue JSON::ParserError => e
        raise SourceError, "Could not parse JSON in #{path}: #{e.message}"
      end

      # When check_id is not supplied via the CLI (e.g. the user only passed
      # --check-file without a UUID argument), pull the id from the document
      # so that deterministic event IDs still work correctly.
      def derive_check_id_from_doc!(doc)
        file_id = doc.dig("data", "id")
        if file_id.nil? || file_id.to_s.strip.empty?
          raise SourceError,
                "Could not determine check id: no UUID argument was given and " \
                "\"data.id\" is missing from #{@check_file_path}"
        end
        @check_id = file_id
      end

      # Parse PaperTrail version records that are sideloaded in the check
      # document's "included" array. Returns an empty array silently when no
      # version records are present, so callers need not check in advance.
      def parse_versions_from_doc(doc)
        included = doc["included"] || []
        return [] unless included.any? { |r| r["type"] == "versions" }

        currency = doc.dig("data", "attributes", "currency") || "GBP"
        parse_versions_document(doc, currency: currency)
      end
    end

    # Raised for file-level errors in CheckFileSource
    class SourceError < StandardError; end
  end
end
