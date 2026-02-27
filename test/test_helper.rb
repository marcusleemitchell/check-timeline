# frozen_string_literal: true

require "minitest/autorun"
require "date"
require "json"
require "tmpdir"

# Load the application without bundler (gems are available system-wide in this project)
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "check_timeline"

module CheckTimeline
  module TestHelpers
    FIXTURES_DIR = File.expand_path("fixtures", __dir__)

    # -------------------------------------------------------------------------
    # Fixture helpers
    # -------------------------------------------------------------------------

    def fixture_path(name)
      File.join(FIXTURES_DIR, name)
    end

    def load_fixture_json(name)
      JSON.parse(File.read(fixture_path(name)))
    end

    # -------------------------------------------------------------------------
    # Factory helpers — build minimal valid objects without touching the FS
    # -------------------------------------------------------------------------

    def build_event(overrides = {})
      defaults = {
        id:         "evt-#{SecureRandom.hex(4)}",
        timestamp:  DateTime.parse("2024-03-15T12:00:00.000Z"),
        source:     :checks_api,
        category:   :check,
        event_type: "check.created",
        title:      "Test Event",
        severity:   :info
      }
      CheckTimeline::Event.new(**defaults.merge(overrides))
    end

    def build_event_at(iso8601, overrides = {})
      build_event(overrides.merge(timestamp: DateTime.parse(iso8601)))
    end

    def build_timeline(events: [], check_id: "abc-123", check_total_cents: nil)
      CheckTimeline::Timeline.new(
        check_id:          check_id,
        events:            events,
        check_total_cents: check_total_cents
      )
    end

    # -------------------------------------------------------------------------
    # SecureRandom shim — available in stdlib, just make sure it's loaded
    # -------------------------------------------------------------------------
  end
end

require "securerandom"

# Make helpers available in all test cases automatically
class Minitest::Test
  include CheckTimeline::TestHelpers
end
