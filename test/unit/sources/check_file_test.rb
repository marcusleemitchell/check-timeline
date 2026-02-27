# frozen_string_literal: true

require_relative "../../test_helper"

module CheckTimeline
  module Sources
    class CheckFileTest < Minitest::Test

      FIXTURES = File.expand_path("../../fixtures", __dir__)

      def fixture(name)
        File.join(FIXTURES, name)
      end

      # -----------------------------------------------------------------------
      # available?
      # -----------------------------------------------------------------------

      def test_available_returns_false_when_no_check_file_given
        source = CheckFileSource.new(check_id: "abc-123")
        refute source.available?
      end

      def test_available_returns_false_when_check_file_path_is_nil
        source = CheckFileSource.new(check_id: "abc-123", check_file: nil)
        refute source.available?
      end

      def test_available_returns_false_when_check_file_does_not_exist
        source = CheckFileSource.new(check_id: "abc-123", check_file: "/no/such/file.json")
        refute source.available?
      end

      def test_available_returns_true_when_check_file_exists
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        assert source.available?
      end

      # -----------------------------------------------------------------------
      # fetch — check events
      # -----------------------------------------------------------------------

      def test_fetch_returns_array_of_events
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events = source.fetch
        assert_kind_of Array, events
        assert events.all? { |e| e.is_a?(CheckTimeline::Event) }
      end

      def test_fetch_returns_at_least_one_event
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        refute_empty source.fetch
      end

      def test_fetch_emits_check_created_event
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        types  = source.fetch.map(&:event_type)
        assert_includes types, "check.created"
      end

      def test_fetch_emits_check_paid_event_when_paid_at_present
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        types  = source.fetch.map(&:event_type)
        assert_includes types, "check.paid"
      end

      def test_fetch_emits_line_item_events
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        types  = source.fetch.map(&:event_type)
        line_item_events = types.select { |t| t == "check.line_item_added" }
        # fixture has two line items
        assert_equal 2, line_item_events.size
      end

      def test_fetch_events_all_have_checks_api_source
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events = source.fetch.reject { |e| e.source == :paper_trail }
        assert events.all? { |e| e.source == :checks_api }
      end

      def test_fetch_events_are_not_already_sorted_requirement_timeline_sorts_them
        # We just assert fetch returns all the expected events; Timeline handles sort
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events = source.fetch
        refute_empty events
      end

      # -----------------------------------------------------------------------
      # check_total_cents — populated from the check file
      # -----------------------------------------------------------------------

      def test_check_total_cents_is_nil_before_fetch
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        assert_nil source.check_total_cents
      end

      def test_check_total_cents_is_set_after_fetch
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        source.fetch
        assert_equal 1200, source.check_total_cents
      end

      def test_check_total_cents_is_an_integer
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        source.fetch
        assert_kind_of Integer, source.check_total_cents
      end

      # -----------------------------------------------------------------------
      # check_id derivation from file when not supplied
      # -----------------------------------------------------------------------

      def test_fetch_derives_check_id_from_file_when_not_supplied
        source = CheckFileSource.new(check_id: "", check_file: fixture("check.json"))
        source.fetch
        assert_equal "abc-123", source.check_id
      end

      def test_fetch_uses_explicit_check_id_when_supplied
        source = CheckFileSource.new(check_id: "explicit-id", check_file: fixture("check.json"))
        source.fetch
        assert_equal "explicit-id", source.check_id
      end

      # -----------------------------------------------------------------------
      # fetch — with payments file
      # -----------------------------------------------------------------------

      def test_fetch_with_payments_file_includes_payment_events
        source = CheckFileSource.new(
          check_id:      "abc-123",
          check_file:    fixture("check.json"),
          payments_file: fixture("payments.json")
        )
        types = source.fetch.map(&:event_type)
        assert(types.any? { |t| t.start_with?("payment.") },
               "Expected at least one payment event, got: #{types.inspect}")
      end

      def test_fetch_with_payments_file_emits_payment_initiated_event
        source = CheckFileSource.new(
          check_id:      "abc-123",
          check_file:    fixture("check.json"),
          payments_file: fixture("payments.json")
        )
        types = source.fetch.map(&:event_type)
        assert_includes types, "payment.initiated"
      end

      def test_fetch_with_payments_file_emits_payment_captured_event
        source = CheckFileSource.new(
          check_id:      "abc-123",
          check_file:    fixture("check.json"),
          payments_file: fixture("payments.json")
        )
        types = source.fetch.map(&:event_type)
        assert_includes types, "payment.captured"
      end

      def test_fetch_without_payments_file_returns_no_payment_events
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        types  = source.fetch.map(&:event_type)
        refute(types.any? { |t| t.start_with?("payment.") },
               "Expected no payment events without a payments file")
      end

      def test_fetch_skips_missing_payments_file_gracefully
        source = CheckFileSource.new(
          check_id:      "abc-123",
          check_file:    fixture("check.json"),
          payments_file: "/no/such/payments.json"
        )
        # Must not raise — returns only check events
        events = source.fetch
        refute_empty events
        types = events.map(&:event_type)
        refute(types.any? { |t| t.start_with?("payment.") })
      end

      # -----------------------------------------------------------------------
      # Timestamp millisecond preservation
      # -----------------------------------------------------------------------

      def test_created_at_timestamp_preserves_milliseconds
        source  = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events  = source.fetch
        created = events.find { |e| e.event_type == "check.created" }
        ms = (created.timestamp.sec_fraction * 1000).to_i
        assert_equal 123, ms
      end

      def test_updated_at_timestamp_preserves_milliseconds
        source  = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events  = source.fetch
        updated = events.find { |e| e.event_type == "check.updated" }
        ms = (updated.timestamp.sec_fraction * 1000).to_i
        assert_equal 456, ms
      end

      def test_payment_captured_at_timestamp_preserves_milliseconds
        source   = CheckFileSource.new(
          check_id:      "abc-123",
          check_file:    fixture("check.json"),
          payments_file: fixture("payments.json")
        )
        events   = source.fetch
        captured = events.find { |e| e.event_type == "payment.captured" }
        ms = (captured.timestamp.sec_fraction * 1000).to_i
        assert_equal 234, ms
      end

      # -----------------------------------------------------------------------
      # _at fields in check event metadata
      # -----------------------------------------------------------------------

      def test_check_created_metadata_contains_created_at_raw_string
        source  = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events  = source.fetch
        created = events.find { |e| e.event_type == "check.created" }
        assert_equal "2024-03-15T12:00:00.123Z", created.metadata["created_at"]
      end

      def test_check_created_metadata_contains_updated_at_raw_string
        source  = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events  = source.fetch
        created = events.find { |e| e.event_type == "check.created" }
        assert_equal "2024-03-15T12:05:30.456Z", created.metadata["updated_at"]
      end

      def test_check_created_metadata_contains_paid_at_raw_string
        source  = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        events  = source.fetch
        created = events.find { |e| e.event_type == "check.created" }
        assert_equal "2024-03-15T12:05:30.456Z", created.metadata["paid_at"]
      end

      # -----------------------------------------------------------------------
      # safe_fetch
      # -----------------------------------------------------------------------

      def test_safe_fetch_returns_empty_array_when_not_available
        source = CheckFileSource.new(check_id: "abc-123", check_file: nil)
        assert_empty source.safe_fetch
      end

      def test_safe_fetch_returns_events_when_available
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        refute_empty source.safe_fetch
      end

      # -----------------------------------------------------------------------
      # Error handling — invalid JSON
      # -----------------------------------------------------------------------

      def test_fetch_raises_source_error_for_invalid_json
        Dir.mktmpdir do |dir|
          bad_path = File.join(dir, "bad.json")
          File.write(bad_path, "{ this is not valid json }")
          source = CheckFileSource.new(check_id: "abc-123", check_file: bad_path)
          assert_raises(SourceError) { source.fetch }
        end
      end

      def test_fetch_raises_source_error_when_data_key_missing
        Dir.mktmpdir do |dir|
          bad_path = File.join(dir, "no_data.json")
          File.write(bad_path, JSON.generate({ "something" => "else" }))
          source = CheckFileSource.new(check_id: "abc-123", check_file: bad_path)
          assert_raises(SourceError) { source.fetch }
        end
      end

      # -----------------------------------------------------------------------
      # Integration with Aggregator — check_total_cents flows through
      # -----------------------------------------------------------------------

      def test_aggregator_receives_check_total_cents_from_check_file_source
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        agg    = Aggregator.new(check_id: "abc-123", sources: [source])
        tl     = agg.run(quiet: true)
        assert_equal 1200, tl.check_total_cents
      end

      def test_aggregator_timeline_formatted_final_value_uses_check_total_cents
        source = CheckFileSource.new(check_id: "abc-123", check_file: fixture("check.json"))
        agg    = Aggregator.new(check_id: "abc-123", sources: [source])
        tl     = agg.run(quiet: true)
        assert_equal "£12.00", tl.formatted_final_value
      end
    end
  end
end
