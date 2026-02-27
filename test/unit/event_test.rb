# frozen_string_literal: true

require_relative "../test_helper"

module CheckTimeline
  class EventTest < Minitest::Test

    # -------------------------------------------------------------------------
    # Construction — valid attributes
    # -------------------------------------------------------------------------

    def test_creates_event_with_required_attributes
      event = build_event
      assert_instance_of CheckTimeline::Event, event
    end

    def test_stores_id
      event = build_event(id: "evt-001")
      assert_equal "evt-001", event.id
    end

    def test_stores_timestamp_as_datetime
      ts = DateTime.parse("2024-03-15T12:00:00.123Z")
      event = build_event(timestamp: ts)
      assert_equal ts, event.timestamp
    end

    def test_stores_source_as_symbol
      event = build_event(source: :checks_api)
      assert_equal :checks_api, event.source
    end

    def test_coerces_source_string_to_symbol
      event = build_event(source: "raygun")
      assert_equal :raygun, event.source
    end

    def test_stores_category_as_symbol
      event = build_event(category: :payment)
      assert_equal :payment, event.category
    end

    def test_coerces_category_string_to_symbol
      event = build_event(category: "exception")
      assert_equal :exception, event.category
    end

    def test_defaults_category_to_unknown
      event = CheckTimeline::Event.new(
        id:         "evt-default-cat",
        timestamp:  DateTime.parse("2024-03-15T12:00:00.000Z"),
        source:     :checks_api,
        event_type: "check.created",
        title:      "Test"
      )
      assert_equal :unknown, event.category
    end

    def test_stores_event_type
      event = build_event(event_type: "check.created")
      assert_equal "check.created", event.event_type
    end

    def test_stores_title
      event = build_event(title: "Check Created")
      assert_equal "Check Created", event.title
    end

    def test_stores_description
      event = build_event(description: "Some detail")
      assert_equal "Some detail", event.description
    end

    def test_description_defaults_to_nil
      event = build_event
      assert_nil event.description
    end

    def test_stores_severity_as_symbol
      event = build_event(severity: :warning)
      assert_equal :warning, event.severity
    end

    def test_coerces_severity_string_to_symbol
      event = build_event(severity: "error")
      assert_equal :error, event.severity
    end

    def test_defaults_severity_to_info
      event = CheckTimeline::Event.new(
        id:         "evt-default-sev",
        timestamp:  DateTime.parse("2024-03-15T12:00:00.000Z"),
        source:     :checks_api,
        event_type: "check.created",
        title:      "Test"
      )
      assert_equal :info, event.severity
    end

    def test_stores_amount
      event = build_event(amount: 1200)
      assert_equal 1200, event.amount
    end

    def test_amount_defaults_to_nil
      event = build_event
      assert_nil event.amount
    end

    def test_stores_currency
      event = build_event(currency: "USD")
      assert_equal "USD", event.currency
    end

    def test_currency_defaults_to_gbp
      event = build_event
      assert_equal "GBP", event.currency
    end

    def test_stores_metadata
      meta = { "table_id" => "42", "covers" => "2" }
      event = build_event(metadata: meta)
      assert_equal meta, event.metadata
    end

    def test_metadata_defaults_to_empty_hash
      event = build_event
      assert_equal({}, event.metadata)
    end

    # -------------------------------------------------------------------------
    # SEVERITIES and CATEGORIES constants
    # -------------------------------------------------------------------------

    def test_severities_constant_contains_expected_values
      assert_equal %i[info warning error critical], CheckTimeline::Event::SEVERITIES
    end

    def test_categories_constant_contains_expected_values
      assert_includes CheckTimeline::Event::CATEGORIES, :check
      assert_includes CheckTimeline::Event::CATEGORIES, :payment
      assert_includes CheckTimeline::Event::CATEGORIES, :exception
      assert_includes CheckTimeline::Event::CATEGORIES, :version
      assert_includes CheckTimeline::Event::CATEGORIES, :unknown
    end

    # -------------------------------------------------------------------------
    # formatted_amount
    # -------------------------------------------------------------------------

    def test_formatted_amount_returns_nil_when_no_amount
      event = build_event(amount: nil)
      assert_nil event.formatted_amount
    end

    def test_formatted_amount_formats_gbp_correctly
      event = build_event(amount: 1200, currency: "GBP")
      assert_equal "£12.00", event.formatted_amount
    end

    def test_formatted_amount_formats_usd_correctly
      event = build_event(amount: 999, currency: "USD")
      assert_equal "$9.99", event.formatted_amount
    end

    def test_formatted_amount_handles_negative_amounts
      event = build_event(amount: -500, currency: "GBP")
      assert_equal "-£5.00", event.formatted_amount
    end

    def test_formatted_amount_handles_zero
      event = build_event(amount: 0, currency: "GBP")
      assert_equal "£0.00", event.formatted_amount
    end

    # -------------------------------------------------------------------------
    # source_icon
    # -------------------------------------------------------------------------

    def test_source_icon_checks_api
      event = build_event(source: :checks_api)
      assert_equal "💳", event.source_icon
    end

    def test_source_icon_raygun
      event = build_event(source: :raygun)
      assert_equal "🐛", event.source_icon
    end

    def test_source_icon_paper_trail
      event = build_event(source: :paper_trail)
      assert_equal "📋", event.source_icon
    end

    def test_source_icon_unknown_source_returns_question_mark
      event = build_event(source: :some_unknown_source)
      assert_equal "❓", event.source_icon
    end

    # -------------------------------------------------------------------------
    # error?
    # -------------------------------------------------------------------------

    def test_error_returns_false_for_info
      assert_equal false, build_event(severity: :info).error?
    end

    def test_error_returns_false_for_warning
      assert_equal false, build_event(severity: :warning).error?
    end

    def test_error_returns_true_for_error
      assert_equal true, build_event(severity: :error).error?
    end

    def test_error_returns_true_for_critical
      assert_equal true, build_event(severity: :critical).error?
    end

    # -------------------------------------------------------------------------
    # Comparable / <=>
    # -------------------------------------------------------------------------

    def test_events_sort_chronologically
      a = build_event_at("2024-03-15T12:00:00.000Z")
      b = build_event_at("2024-03-15T12:01:00.000Z")
      c = build_event_at("2024-03-15T11:59:00.000Z")
      assert_equal [c, a, b], [a, b, c].sort
    end

    def test_events_sort_using_millisecond_precision
      a = build_event_at("2024-03-15T12:00:00.100Z")
      b = build_event_at("2024-03-15T12:00:00.900Z")
      c = build_event_at("2024-03-15T12:00:00.500Z")
      assert_equal [a, c, b], [a, b, c].sort
    end

    def test_spaceship_operator_returns_negative_for_earlier_event
      a = build_event_at("2024-03-15T12:00:00.000Z")
      b = build_event_at("2024-03-15T12:00:01.000Z")
      assert_equal(-1, a <=> b)
    end

    def test_spaceship_operator_returns_zero_for_equal_timestamps
      ts = "2024-03-15T12:00:00.000Z"
      a  = build_event_at(ts)
      b  = build_event_at(ts)
      assert_equal 0, a <=> b
    end

    def test_spaceship_operator_returns_positive_for_later_event
      a = build_event_at("2024-03-15T12:00:01.000Z")
      b = build_event_at("2024-03-15T12:00:00.000Z")
      assert_equal 1, a <=> b
    end
  end
end
