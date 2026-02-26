# frozen_string_literal: true

require "json"
require "date"

module CheckTimeline
  module Sources
    # Reads one or more local Raygun exception JSON files and converts each
    # exception into a CheckTimeline::Event.
    #
    # Raygun's standard error payload looks like:
    #
    #   {
    #     "OccurredOn": "2024-01-15T10:23:45.000Z",
    #     "Details": {
    #       "Error": {
    #         "ClassName": "RuntimeError",
    #         "Message": "Something went wrong",
    #         "StackTrace": [ { "FileName": "...", "LineNumber": 42, ... } ]
    #       },
    #       "Request": {
    #         "Url": "https://...",
    #         "HttpMethod": "POST",
    #         "Headers": { ... },
    #         "Form": { ... },
    #         "QueryString": { ... }
    #       },
    #       "Response": { "StatusCode": 500 },
    #       "User": { "Identifier": "user@example.com" },
    #       "Tags": ["tag1", "tag2"],
    #       "UserCustomData": { ... },
    #       "MachineName": "web-01",
    #       "Version": "1.2.3"
    #     }
    #   }
    #
    # Usage:
    #   RaygunFileSource.new(
    #     check_id: uuid,
    #     files: ["path/to/error1.json", "path/to/error2.json"]
    #   )
    #
    # The :files option can be a String glob pattern or an Array of file paths.
    class RaygunFileSource < BaseSource
      # Maximum number of stack frames to include in the description
      MAX_STACK_FRAMES = 5

      def initialize(check_id:, **options)
        super
        @files = resolve_files(options[:files])
      end

      def available?
        @files.any?
      end

      def fetch
        @files.flat_map { |path| parse_file(path) }.compact
      end

      private

      # ------------------------------------------------------------------
      # File resolution
      # ------------------------------------------------------------------

      def resolve_files(input)
        case input
        when nil
          []
        when String
          # Treat as a glob if it contains wildcard characters, otherwise a literal path
          if input.include?("*") || input.include?("?")
            Dir.glob(input).select { |f| File.file?(f) }
          else
            [input].select { |f| File.file?(f) }
          end
        when Array
          input.flat_map do |item|
            if item.include?("*") || item.include?("?")
              Dir.glob(item).select { |f| File.file?(f) }
            else
              [item].select { |f| File.file?(f) }
            end
          end
        else
          []
        end
      end

      # ------------------------------------------------------------------
      # File parsing
      # ------------------------------------------------------------------

      def parse_file(path)
        raw = File.read(path)
        payload = JSON.parse(raw)
        build_exception_event(payload, path)
      rescue Errno::ENOENT
        warn_log "Raygun file not found: #{path}"
        nil
      rescue Errno::EACCES
        warn_log "Permission denied reading Raygun file: #{path}"
        nil
      rescue JSON::ParserError => e
        warn_log "Could not parse JSON in #{path}: #{e.message}"
        nil
      rescue StandardError => e
        warn_log "Unexpected error reading #{path}: #{e.class}: #{e.message}"
        nil
      end

      # ------------------------------------------------------------------
      # Event building
      # ------------------------------------------------------------------

      def build_exception_event(payload, file_path)
        occurred_on = extract_occurred_on(payload)
        details     = extract_details(payload)
        error       = extract_error(details)
        request     = extract_request(details)
        response    = extract_response(details)

        class_name  = error.fetch("ClassName", "UnknownError")
        message     = error.fetch("Message", "No message provided")
        status_code = response&.fetch("StatusCode", nil)

        build_event(
          id:          event_id("raygun", file_path, occurred_on.to_s),
          timestamp:   occurred_on,
          source:      :raygun,
          category:    :exception,
          event_type:  "exception.raised",
          title:       "#{class_name}: #{truncate(message, 80)}",
          description: build_description(error, request, response, details),
          severity:    derive_severity(class_name, status_code),
          metadata:    build_metadata(payload, details, file_path)
        )
      end

      # ------------------------------------------------------------------
      # Payload extraction helpers
      # ------------------------------------------------------------------

      def extract_occurred_on(payload)
        ts = payload["OccurredOn"] || payload["occurredOn"] || payload["occurred_on"]
        parse_timestamp(ts)
      rescue ArgumentError
        # Fall back to file modification time is not available so use epoch
        warn_log "Could not parse OccurredOn timestamp; using current time as fallback."
        DateTime.now
      end

      def extract_details(payload)
        payload["Details"] || payload["details"] || {}
      end

      def extract_error(details)
        details["Error"] || details["error"] || {}
      end

      def extract_request(details)
        details["Request"] || details["request"]
      end

      def extract_response(details)
        details["Response"] || details["response"]
      end

      # ------------------------------------------------------------------
      # Description builder
      # ------------------------------------------------------------------

      def build_description(error, request, response, details)
        parts = []

        # Error message
        message = error["Message"] || error["message"]
        parts << message if message

        # Request line
        if request
          method = request["HttpMethod"] || request["method"] || "?"
          url    = request["Url"]        || request["url"]    || "?"
          parts << "Request: #{method} #{url}"
        end

        # Response status
        if response
          status = response["StatusCode"] || response["statusCode"]
          parts << "Response: HTTP #{status}" if status
        end

        # Inner exception
        if (inner = error["InnerError"] || error["innerError"])
          inner_class   = inner["ClassName"] || "UnknownError"
          inner_message = inner["Message"]   || ""
          parts << "Caused by: #{inner_class}: #{truncate(inner_message, 120)}"
        end

        # Stack trace (top N frames)
        stack_frames = error["StackTrace"] || error["stackTrace"] || []
        if stack_frames.any?
          parts << "Stack trace:"
          stack_frames.first(MAX_STACK_FRAMES).each do |frame|
            parts << format_stack_frame(frame)
          end
          remaining = stack_frames.size - MAX_STACK_FRAMES
          parts << "  ... #{remaining} more frames" if remaining > 0
        end

        # Tags
        tags = details["Tags"] || details["tags"] || []
        parts << "Tags: #{tags.join(", ")}" if tags.any?

        # Machine / version context
        machine = details["MachineName"] || details["machineName"]
        version = details["Version"]     || details["version"]
        parts << "Machine: #{machine}"  if machine
        parts << "App version: #{version}" if version

        parts.join("\n")
      end

      def format_stack_frame(frame)
        file        = frame["FileName"]   || frame["fileName"]   || "?"
        line        = frame["LineNumber"] || frame["lineNumber"]  || "?"
        method_name = frame["MethodName"] || frame["methodName"] || frame["Method"] || "?"
        class_name  = frame["ClassName"]  || frame["className"]
        location    = class_name ? "#{class_name}##{method_name}" : method_name
        "  #{location} (#{file}:#{line})"
      end

      # ------------------------------------------------------------------
      # Severity derivation
      # ------------------------------------------------------------------

      # Maps exception class names and HTTP status codes to severity levels.
      CRITICAL_PATTERNS = %w[
        OutOfMemoryError SystemStackError NoMemoryError
        FatalError Segfault SignalException
      ].freeze

      ERROR_STATUS_CODES = (500..599).freeze
      WARNING_STATUS_CODES = (400..499).freeze

      def derive_severity(class_name, status_code)
        return :critical if CRITICAL_PATTERNS.any? { |p| class_name.to_s.include?(p) }
        return :error    if status_code && ERROR_STATUS_CODES.cover?(status_code.to_i)
        return :warning  if status_code && WARNING_STATUS_CODES.cover?(status_code.to_i)

        :error # Unhandled exceptions are always at least :error
      end

      # ------------------------------------------------------------------
      # Metadata builder
      # ------------------------------------------------------------------

      def build_metadata(payload, details, file_path)
        meta = {}

        meta["file"] = file_path

        # User identity
        if (user = details["User"] || details["user"])
          meta["user"] = user["Identifier"] || user["identifier"] || user["email"] || user.to_s
        end

        # Request details
        if (request = details["Request"] || details["request"])
          meta["http_method"] = request["HttpMethod"] || request["method"]
          meta["url"]         = request["Url"]        || request["url"]
          meta["ip_address"]  = request["IpAddress"]  || request["ipAddress"]
        end

        # Response details
        if (response = details["Response"] || details["response"])
          meta["status_code"] = response["StatusCode"] || response["statusCode"]
        end

        # User custom data — flatten top-level keys
        if (custom = details["UserCustomData"] || details["userCustomData"])
          custom.each do |k, v|
            meta["custom_#{k}"] = v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
          end
        end

        # Tags
        tags = details["Tags"] || details["tags"] || []
        meta["tags"] = tags.join(", ") if tags.any?

        meta["machine_name"] = details["MachineName"] || details["machineName"] if details["MachineName"] || details["machineName"]
        meta["app_version"]  = details["Version"]     || details["version"]      if details["Version"]     || details["version"]

        meta.compact
      end

      # ------------------------------------------------------------------
      # String helpers
      # ------------------------------------------------------------------

      def truncate(string, max_length)
        return string if string.nil? || string.length <= max_length

        "#{string[0, max_length - 1]}…"
      end
    end
  end
end
