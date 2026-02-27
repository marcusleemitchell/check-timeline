# frozen_string_literal: true

require_relative "../test_helper"

module CheckTimeline
  class AggregatorTest < Minitest::Test

    # -------------------------------------------------------------------------
    # Stub source — lets us inject events without touching the filesystem or network
    # -------------------------------------------------------------------------

    class StubSource
      attr_reader :source_name, :events_to_return, :check_total_cents, :fetch_called

      def initialize(name:, events: [], available: true, check_total_cents: nil)
        @source_name       = name
        @events_to_return  = events
        @is_available      = available
        @check_total_cents = check_total_cents
        @fetch_called      = false
      end

      def available?
        @is_available
      end

      def fetch
        @fetch_called = true
        @events_to_return
      end

      def safe_fetch
        return [] unless available?

        fetch
      rescue StandardError
        []
      end
    end

    # -------------------------------------------------------------------------
    # Construction
    # -------------------------------------------------------------------------

    def test_stores_check_id
      agg = Aggregator.new(check_id: "abc-123", sources: [])
      assert_equal "abc-123", agg.check_id
    end

    def test_stores_sources
      source = StubSource.new(name: :stub)
      agg    = Aggregator.new(check_id: "abc-123", sources: [source])
      assert_equal [source], agg.sources
    end

    # -------------------------------------------------------------------------
    # run — sequential (default)
    # -------------------------------------------------------------------------

    def test_run_returns_a_timeline
      agg = Aggregator.new(check_id: "abc-123", sources: [])
      tl  = agg.run(quiet: true)
      assert_instance_of CheckTimeline::Timeline, tl
    end

    def test_run_timeline_has_correct_check_id
      agg = Aggregator.new(check_id: "abc-123", sources: [])
      tl  = agg.run(quiet: true)
      assert_equal "abc-123", tl.check_id
    end

    def test_run_collects_events_from_all_sources
      events_a = [build_event(title: "A"), build_event(title: "B")]
      events_b = [build_event(title: "C")]
      source_a = StubSource.new(name: :source_a, events: events_a)
      source_b = StubSource.new(name: :source_b, events: events_b)

      agg = Aggregator.new(check_id: "abc-123", sources: [source_a, source_b])
      tl  = agg.run(quiet: true)

      assert_equal 3, tl.count
    end

    def test_run_merges_events_from_multiple_sources_and_sorts_them
      early = build_event_at("2024-03-15T12:00:00.000Z", title: "Early")
      late  = build_event_at("2024-03-15T12:05:00.000Z", title: "Late")
      mid   = build_event_at("2024-03-15T12:02:30.000Z", title: "Mid")

      source_a = StubSource.new(name: :a, events: [late])
      source_b = StubSource.new(name: :b, events: [early, mid])

      agg = Aggregator.new(check_id: "abc-123", sources: [source_a, source_b])
      tl  = agg.run(quiet: true)

      assert_equal %w[Early Mid Late], tl.events.map(&:title)
    end

    def test_run_returns_empty_timeline_when_no_sources
      agg = Aggregator.new(check_id: "abc-123", sources: [])
      tl  = agg.run(quiet: true)
      assert tl.empty?
    end

    def test_run_skips_unavailable_sources
      available   = StubSource.new(name: :available,   events: [build_event(title: "OK")], available: true)
      unavailable = StubSource.new(name: :unavailable, events: [build_event(title: "NO")], available: false)

      agg = Aggregator.new(check_id: "abc-123", sources: [available, unavailable])
      tl  = agg.run(quiet: true)

      assert_equal 1, tl.count
      assert_equal "OK", tl.events.first.title
    end

    def test_run_passes_check_total_cents_from_source_to_timeline
      source = StubSource.new(name: :stub, events: [build_event(amount: 100)], check_total_cents: 1200)
      agg    = Aggregator.new(check_id: "abc-123", sources: [source])
      tl     = agg.run(quiet: true)
      assert_equal 1200, tl.check_total_cents
    end

    def test_run_uses_first_non_nil_check_total_cents_across_sources
      source_a = StubSource.new(name: :a, events: [build_event], check_total_cents: nil)
      source_b = StubSource.new(name: :b, events: [build_event], check_total_cents: 800)
      source_c = StubSource.new(name: :c, events: [build_event], check_total_cents: 999)

      agg = Aggregator.new(check_id: "abc-123", sources: [source_a, source_b, source_c])
      tl  = agg.run(quiet: true)

      assert_equal 800, tl.check_total_cents
    end

    def test_run_leaves_check_total_cents_nil_when_no_source_provides_it
      source = StubSource.new(name: :stub, events: [build_event], check_total_cents: nil)
      agg    = Aggregator.new(check_id: "abc-123", sources: [source])
      tl     = agg.run(quiet: true)
      assert_nil tl.check_total_cents
    end

    def test_run_tolerates_source_that_does_not_respond_to_check_total_cents
      # A plain stub without check_total_cents — must not raise
      source = StubSource.new(name: :stub, events: [build_event])
      source.instance_eval { undef check_total_cents rescue nil }

      agg = Aggregator.new(check_id: "abc-123", sources: [source])
      tl  = nil
      assert_silent { tl = agg.run(quiet: true) }
      assert_instance_of CheckTimeline::Timeline, tl
    end

    def test_run_suppresses_source_errors_and_continues
      # Source whose safe_fetch swallows its own error and returns [] —
      # events from the good source still appear in the final timeline
      bad_source = StubSource.new(name: :bad, events: [], available: true)
      bad_source.define_singleton_method(:safe_fetch) { [] }

      good_source = StubSource.new(name: :good, events: [build_event(title: "Good")])

      agg = Aggregator.new(check_id: "abc-123", sources: [bad_source, good_source])
      tl  = agg.run(quiet: true)

      assert_equal 1, tl.count
      assert_equal "Good", tl.events.first.title
    end

    def test_run_quiet_suppresses_stdout
      source = StubSource.new(name: :stub, events: [build_event])
      agg    = Aggregator.new(check_id: "abc-123", sources: [source])

      output = capture_io { agg.run(quiet: true) }.first
      assert_empty output
    end

    def test_run_prints_progress_when_not_quiet
      source = StubSource.new(name: :stub, events: [build_event])
      agg    = Aggregator.new(check_id: "abc-123", sources: [source])

      output = capture_io { agg.run(quiet: false) }.first
      refute_empty output
    end

    # -------------------------------------------------------------------------
    # run — parallel
    # -------------------------------------------------------------------------

    def test_run_parallel_collects_all_events
      events_a = [build_event(title: "A"), build_event(title: "B")]
      events_b = [build_event(title: "C")]
      source_a = StubSource.new(name: :a, events: events_a)
      source_b = StubSource.new(name: :b, events: events_b)

      agg = Aggregator.new(check_id: "abc-123", sources: [source_a, source_b], parallel: true)
      tl  = agg.run(quiet: true)

      assert_equal 3, tl.count
    end

    def test_run_parallel_returns_timeline
      agg = Aggregator.new(check_id: "abc-123", sources: [], parallel: true)
      tl  = agg.run(quiet: true)
      assert_instance_of CheckTimeline::Timeline, tl
    end

    def test_run_parallel_passes_check_total_cents
      source = StubSource.new(name: :stub, events: [build_event], check_total_cents: 1500)
      agg    = Aggregator.new(check_id: "abc-123", sources: [source], parallel: true)
      tl     = agg.run(quiet: true)
      assert_equal 1500, tl.check_total_cents
    end

    def test_run_parallel_and_sequential_produce_same_event_count
      events_a = [build_event_at("2024-03-15T12:00:00.000Z"), build_event_at("2024-03-15T12:01:00.000Z")]
      events_b = [build_event_at("2024-03-15T12:00:30.000Z")]

      make_sources = lambda do
        [
          StubSource.new(name: :a, events: events_a),
          StubSource.new(name: :b, events: events_b)
        ]
      end

      seq_tl  = Aggregator.new(check_id: "abc-123", sources: make_sources.call, parallel: false).run(quiet: true)
      para_tl = Aggregator.new(check_id: "abc-123", sources: make_sources.call, parallel: true).run(quiet: true)

      assert_equal seq_tl.count, para_tl.count
    end
  end
end
