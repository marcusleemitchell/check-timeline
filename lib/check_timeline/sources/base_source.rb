# frozen_string_literal: true

module CheckTimeline
  module Sources
    # Abstract base class for all data sources.
    #
    # Subclasses must implement:
    #   #fetch → Array<CheckTimeline::Event>
    #
    # Subclasses may override:
    #   #source_name → Symbol   (defaults to class name underscored)
    #   #available?  → Boolean  (used to skip sources that are not configured)
    #
    # Example:
    #   class MySource < BaseSource
    #     def fetch
    #       # ... retrieve raw data ...
    #       [build_event(timestamp: Time.now, ...)]
    #     end
    #   end
    class BaseSource
      attr_reader :check_id, :options

      def initialize(check_id:, **options)
        @check_id = check_id
        @options  = options
      end

      # Subclasses MUST implement this method.
      # It must return an Array of CheckTimeline::Event instances.
      def fetch
        raise NotImplementedError, "#{self.class}#fetch is not implemented"
      end

      # Returns true if this source has everything it needs to run.
      # Override in subclasses to gate on ENV vars, file existence, etc.
      def available?
        true
      end

      # Human-readable name for this source, used in log output.
      # Defaults to the underscored, demodulized class name.
      def source_name
        self.class.name
            .split("::")
            .last
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
            .to_sym
      end

      # Safe wrapper around fetch: returns an empty array and prints a warning
      # if the source is unavailable or raises an unexpected error.
      def safe_fetch
        unless available?
          warn_log "Source '#{source_name}' is not available (skipping). " \
                   "Check configuration and environment variables."
          return []
        end

        fetch
      rescue StandardError => e
        warn_log "Source '#{source_name}' raised an error during fetch: " \
                 "#{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        []
      end

      protected

      # Convenience factory so subclasses don't need to spell out the full class.
      def build_event(**attributes)
        CheckTimeline::Event.new(**attributes)
      end

      # Generates a deterministic ID for an event given a set of components.
      # Useful for deduplication — same inputs always produce the same ID.
      def event_id(*components)
        require "digest"
        Digest::SHA1.hexdigest([check_id, source_name, *components].join(":"))
      end

      # Parses a timestamp from a variety of input types:
      #   - Already a Time/DateTime → returned as-is
      #   - String → parsed via DateTime.parse
      #   - nil    → raises ArgumentError
      def parse_timestamp(value)
        return value if value.is_a?(DateTime)
        return value.to_datetime if value.is_a?(Time)

        raise ArgumentError, "Cannot parse nil timestamp in #{source_name}" if value.nil?

        DateTime.parse(value.to_s)
      rescue Date::Error => e
        raise ArgumentError, "Invalid timestamp '#{value}' in #{source_name}: #{e.message}"
      end

      private

      def warn_log(message)
        $stderr.puts "[WARN] [#{self.class.name}] #{message}"
      end
    end
  end
end
