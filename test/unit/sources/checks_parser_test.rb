# frozen_string_literal: true

require_relative "../../test_helper"

module CheckTimeline
  module Sources
    class ChecksParserTest < Minitest::Test

      # -----------------------------------------------------------------------
      # Test host — a minimal class that includes ChecksParser exactly as the
      # real sources do, so every method under test runs in the right context.
      # -----------------------------------------------------------------------

      class ParserHost
        include CheckTimeline::Sources::ChecksParser

        attr_accessor :check_id

        def initialize(check_id: "abc-123")
          @check_id = check_id
        end

        # Satisfy the BaseSource contract that ChecksParser depends on
        def source_name = :test_parser

        def build_event(**attrs)
          CheckTimeline::Event.new(**attrs)
        end

        def event_id(*components)
          require "digest"
          Digest::SHA1.hexdigest([check_id, source_name, *components].join(":"))
        end

        def parse_timestamp(value)
          return value if value.is_a?(DateTime)
          DateTime.parse(value.to_s)
        end

        def warn_log(msg)
          # suppress in tests
        end
      end

      def setup
        @parser = ParserHost.new(check_id: "abc-123")
      end

      # -----------------------------------------------------------------------
      # Helpers — minimal document builders
      # -----------------------------------------------------------------------

      def check_doc(attribute_overrides = {}, included: nil)
        included ||= []
        defaults = {
          "check_number"        => "1001",
          "sequence_number"     => "555001",
          "currency"            => "GBP",
          "status"              => "paid",
          "covers"              => "2",
          "location_name"       => "Test Venue",
          "location_code"       => "TEST",
          "total_cents"         => 1200,
          "net_cents"           => 1000,
          "remaining_cents"     => 0,
          "line_items_tax_cents"=> 200,
          "gratuities_cents"    => 0,
          "extra_tax_cents"     => 0,
          "subtotal"            => 1000,
          "variable_tips_enabled" => false,
          "created_at"          => "2024-03-15T12:00:00.123Z",
          "updated_at"          => "2024-03-15T12:05:30.456Z",
          "paid_at"             => "2024-03-15T12:05:30.456Z",
          "line_items"          => [],
          "discounts"           => [],
          "service_charges"     => [],
          "other_payments"      => [],
          "vat_items"           => []
        }

        {
          "data"     => {
            "id"            => "abc-123",
            "type"          => "checks",
            "attributes"    => defaults.merge(attribute_overrides),
            "relationships" => {
              "location" => { "data" => { "id" => "loc-1", "type" => "locations" } }
            }
          },
          "included" => included
        }
      end

      def payment_attrs(overrides = {})
        {
          "id" => "pay-001",
          "attributes" => {
            "currency"     => "GBP",
            "amount_cents" => 1200,
            "status"       => "captured",
            "created_at"   => "2024-03-15T12:04:10.789Z",
            "captured_at"  => "2024-03-15T12:04:11.234Z"
          }.merge(overrides)
        }
      end

      # -----------------------------------------------------------------------
      # parse_check_total_cents
      # -----------------------------------------------------------------------

      def test_parse_check_total_cents_returns_integer_when_present
        doc = check_doc({ "total_cents" => 1200 })
        assert_equal 1200, @parser.parse_check_total_cents(doc)
      end

      def test_parse_check_total_cents_returns_nil_when_absent
        doc = check_doc({})
        doc["data"]["attributes"].delete("total_cents")
        assert_nil @parser.parse_check_total_cents(doc)
      end

      def test_parse_check_total_cents_coerces_string_to_integer
        doc = check_doc({ "total_cents" => "800" })
        assert_equal 800, @parser.parse_check_total_cents(doc)
      end

      # -----------------------------------------------------------------------
      # parse_check_document — top-level event generation
      # -----------------------------------------------------------------------

      def test_parse_check_document_returns_array_of_events
        events = @parser.parse_check_document(check_doc)
        assert_kind_of Array, events
        assert events.all? { |e| e.is_a?(CheckTimeline::Event) }
      end

      def test_parse_check_document_emits_created_event
        events = @parser.parse_check_document(check_doc)
        types  = events.map(&:event_type)
        assert_includes types, "check.created"
      end

      def test_parse_check_document_emits_updated_event_when_timestamps_differ
        doc    = check_doc({ "created_at" => "2024-03-15T12:00:00.000Z",
                             "updated_at" => "2024-03-15T12:05:00.000Z" })
        events = @parser.parse_check_document(doc)
        types  = events.map(&:event_type)
        assert_includes types, "check.updated"
      end

      def test_parse_check_document_does_not_emit_updated_event_when_timestamps_same
        doc    = check_doc({ "created_at" => "2024-03-15T12:00:00.000Z",
                             "updated_at" => "2024-03-15T12:00:00.000Z" })
        events = @parser.parse_check_document(doc)
        types  = events.map(&:event_type)
        refute_includes types, "check.updated"
      end

      def test_parse_check_document_emits_paid_event_when_paid_at_present
        events = @parser.parse_check_document(check_doc({ "paid_at" => "2024-03-15T12:05:30.456Z" }))
        types  = events.map(&:event_type)
        assert_includes types, "check.paid"
      end

      def test_parse_check_document_does_not_emit_paid_event_when_paid_at_absent
        doc    = check_doc({})
        doc["data"]["attributes"].delete("paid_at")
        events = @parser.parse_check_document(doc)
        types  = events.map(&:event_type)
        refute_includes types, "check.paid"
      end

      def test_parse_check_document_all_events_have_checks_api_source
        events = @parser.parse_check_document(check_doc)
        assert events.all? { |e| e.source == :checks_api }
      end

      def test_parse_check_document_all_events_have_check_category
        events = @parser.parse_check_document(check_doc)
        assert events.all? { |e| e.category == :check }
      end

      def test_parse_check_document_created_event_carries_total_cents_as_amount
        doc    = check_doc({ "total_cents" => 1200 })
        events = @parser.parse_check_document(doc)
        created = events.find { |e| e.event_type == "check.created" }
        assert_equal 1200, created.amount
      end

      def test_parse_check_document_created_event_timestamp_preserves_milliseconds
        doc     = check_doc({ "created_at" => "2024-03-15T12:00:00.123Z" })
        events  = @parser.parse_check_document(doc)
        created = events.find { |e| e.event_type == "check.created" }
        ms = (created.timestamp.sec_fraction * 1000).to_i
        assert_equal 123, ms
      end

      def test_parse_check_document_updated_event_timestamp_preserves_milliseconds
        doc    = check_doc({ "created_at" => "2024-03-15T12:00:00.000Z",
                             "updated_at" => "2024-03-15T12:05:30.456Z" })
        events  = @parser.parse_check_document(doc)
        updated = events.find { |e| e.event_type == "check.updated" }
        ms = (updated.timestamp.sec_fraction * 1000).to_i
        assert_equal 456, ms
      end

      def test_parse_check_document_uses_gbp_currency_by_default
        doc    = check_doc({})
        doc["data"]["attributes"].delete("currency")
        events = @parser.parse_check_document(doc)
        assert events.all? { |e| e.currency == "GBP" }
      end

      def test_parse_check_document_uses_currency_from_attributes
        doc    = check_doc({ "currency" => "USD" })
        events = @parser.parse_check_document(doc)
        assert events.all? { |e| e.currency == "USD" }
      end

      # -----------------------------------------------------------------------
      # parse_check_document — line items
      # -----------------------------------------------------------------------

      def test_parse_check_document_emits_line_item_events
        line_items = [
          { "name" => "Burger", "cents" => 800, "quantity" => 1, "category" => "Food", "revenue_center" => "Floor" },
          { "name" => "Beer",   "cents" => 400, "quantity" => 1, "category" => "Drink", "revenue_center" => "Floor" }
        ]
        doc    = check_doc({ "line_items" => line_items })
        events = @parser.parse_check_document(doc)
        types  = events.map(&:event_type)
        assert_equal 2, types.count("check.line_item_added")
      end

      def test_parse_check_document_line_item_events_have_correct_amounts
        line_items = [
          { "name" => "Burger", "cents" => 800, "quantity" => 1, "category" => "Food", "revenue_center" => "Floor" }
        ]
        doc     = check_doc({ "line_items" => line_items })
        events  = @parser.parse_check_document(doc)
        li_event = events.find { |e| e.event_type == "check.line_item_added" }
        assert_equal 800, li_event.amount
      end

      def test_parse_check_document_line_items_sort_after_created_event
        line_items = [
          { "name" => "Item A", "cents" => 100, "quantity" => 1, "category" => "Food", "revenue_center" => "Floor" }
        ]
        doc    = check_doc({ "line_items" => line_items,
                             "created_at" => "2024-03-15T12:00:00.000Z",
                             "updated_at" => "2024-03-15T12:05:00.000Z" })
        events = @parser.parse_check_document(doc)
        created  = events.find  { |e| e.event_type == "check.created" }
        li_event = events.find  { |e| e.event_type == "check.line_item_added" }
        assert li_event.timestamp > created.timestamp
      end

      # -----------------------------------------------------------------------
      # parse_check_document — discounts
      # -----------------------------------------------------------------------

      def test_parse_check_document_emits_discount_event
        discounts = [
          { "name" => "Staff Discount", "percentage" => "20", "cents" => 200, "created_at" => "2024-03-15T12:01:00.000Z" }
        ]
        doc    = check_doc({ "discounts" => discounts })
        events = @parser.parse_check_document(doc)
        types  = events.map(&:event_type)
        assert_includes types, "check.discount_applied"
      end

      def test_parse_check_document_discount_amount_is_negative
        discounts = [
          { "name" => "10% Off", "cents" => 120, "created_at" => "2024-03-15T12:01:00.000Z" }
        ]
        doc      = check_doc({ "discounts" => discounts })
        events   = @parser.parse_check_document(doc)
        discount = events.find { |e| e.event_type == "check.discount_applied" }
        assert discount.amount < 0
      end

      # -----------------------------------------------------------------------
      # parse_check_document — service charges
      # -----------------------------------------------------------------------

      def test_parse_check_document_emits_service_charge_event
        charges = [
          { "name" => "Service Charge", "cents" => 150, "created_at" => "2024-03-15T12:01:00.000Z" }
        ]
        doc    = check_doc({ "service_charges" => charges })
        events = @parser.parse_check_document(doc)
        types  = events.map(&:event_type)
        assert_includes types, "check.service_charge_added"
      end

      def test_parse_check_document_service_charge_amount_is_positive
        charges = [
          { "name" => "Service Charge", "cents" => 150, "created_at" => "2024-03-15T12:01:00.000Z" }
        ]
        doc    = check_doc({ "service_charges" => charges })
        events = @parser.parse_check_document(doc)
        charge = events.find { |e| e.event_type == "check.service_charge_added" }
        assert charge.amount > 0
      end

      # -----------------------------------------------------------------------
      # check_metadata — _at fields included with milliseconds
      # -----------------------------------------------------------------------

      def test_check_metadata_includes_created_at_with_milliseconds
        doc    = check_doc({ "created_at" => "2024-03-15T12:00:00.123Z" })
        events = @parser.parse_check_document(doc)
        created = events.find { |e| e.event_type == "check.created" }
        assert_equal "2024-03-15T12:00:00.123Z", created.metadata["created_at"]
      end

      def test_check_metadata_includes_updated_at
        doc    = check_doc({ "created_at" => "2024-03-15T12:00:00.000Z",
                             "updated_at" => "2024-03-15T12:05:30.456Z" })
        events = @parser.parse_check_document(doc)
        updated = events.find { |e| e.event_type == "check.updated" }
        assert_equal "2024-03-15T12:05:30.456Z", updated.metadata["updated_at"]
      end

      def test_check_metadata_includes_paid_at
        doc    = check_doc({ "paid_at" => "2024-03-15T12:05:30.789Z" })
        events = @parser.parse_check_document(doc)
        paid   = events.find { |e| e.event_type == "check.paid" }
        assert_equal "2024-03-15T12:05:30.789Z", paid.metadata["paid_at"]
      end

      def test_check_metadata_includes_standard_fields
        doc    = check_doc({})
        events = @parser.parse_check_document(doc)
        created = events.find { |e| e.event_type == "check.created" }
        assert_equal "abc-123", created.metadata["check_id"]
        assert_equal "1001",    created.metadata["check_number"].to_s
        assert_equal 1200,      created.metadata["total_cents"]
      end

      def test_check_metadata_omits_nil_values
        doc    = check_doc({ "waiter_id" => nil, "table_id" => nil })
        events = @parser.parse_check_document(doc)
        created = events.find { |e| e.event_type == "check.created" }
        refute created.metadata.key?("waiter_id")
        refute created.metadata.key?("table_id")
      end

      # -----------------------------------------------------------------------
      # parse_payments_document
      # -----------------------------------------------------------------------

      def test_parse_payments_document_accepts_array
        doc    = [payment_attrs]
        events = @parser.parse_payments_document(doc)
        refute_empty events
        assert events.all? { |e| e.is_a?(CheckTimeline::Event) }
      end

      def test_parse_payments_document_accepts_jsonapi_hash_with_data_key
        doc    = { "data" => [payment_attrs] }
        events = @parser.parse_payments_document(doc)
        refute_empty events
      end

      def test_parse_payments_document_accepts_payments_wrapper_hash
        doc    = { "payments" => [payment_attrs] }
        events = @parser.parse_payments_document(doc)
        refute_empty events
      end

      def test_parse_payments_document_returns_empty_for_empty_array
        assert_empty @parser.parse_payments_document([])
      end

      def test_parse_payments_document_emits_initiated_event_for_created_at
        events = @parser.parse_payments_document([payment_attrs])
        types  = events.map(&:event_type)
        assert_includes types, "payment.initiated"
      end

      def test_parse_payments_document_emits_captured_event_for_captured_at
        events = @parser.parse_payments_document([payment_attrs])
        types  = events.map(&:event_type)
        assert_includes types, "payment.captured"
      end

      def test_parse_payments_document_emits_failed_event_for_failed_at
        attrs  = payment_attrs("failed_at" => "2024-03-15T12:04:15.000Z")
        events = @parser.parse_payments_document([attrs])
        types  = events.map(&:event_type)
        assert_includes types, "payment.failed"
      end

      def test_parse_payments_document_emits_refunded_event_for_refunded_at
        attrs  = payment_attrs("refunded_at" => "2024-03-15T12:10:00.000Z")
        events = @parser.parse_payments_document([attrs])
        types  = events.map(&:event_type)
        assert_includes types, "payment.refunded"
      end

      def test_parse_payments_document_all_events_have_checks_api_source
        events = @parser.parse_payments_document([payment_attrs])
        assert events.all? { |e| e.source == :checks_api }
      end

      def test_parse_payments_document_all_events_have_payment_category
        events = @parser.parse_payments_document([payment_attrs])
        assert events.all? { |e| e.category == :payment }
      end

      def test_parse_payments_document_initiated_event_has_correct_amount
        events    = @parser.parse_payments_document([payment_attrs("amount_cents" => 1200)])
        initiated = events.find { |e| e.event_type == "payment.initiated" }
        assert_equal 1200, initiated.amount
      end

      def test_parse_payments_document_captured_timestamp_preserves_milliseconds
        events   = @parser.parse_payments_document([payment_attrs("captured_at" => "2024-03-15T12:04:11.234Z")])
        captured = events.find { |e| e.event_type == "payment.captured" }
        ms = (captured.timestamp.sec_fraction * 1000).to_i
        assert_equal 234, ms
      end

      def test_parse_payments_document_refunded_event_has_negative_amount
        attrs    = payment_attrs("refunded_at" => "2024-03-15T12:10:00.000Z", "amount_cents" => 1200)
        events   = @parser.parse_payments_document([attrs])
        refunded = events.find { |e| e.event_type == "payment.refunded" }
        assert refunded.amount < 0
      end

      def test_parse_payments_document_failed_event_has_error_severity
        attrs  = payment_attrs("failed_at" => "2024-03-15T12:04:15.000Z")
        events = @parser.parse_payments_document([attrs])
        failed = events.find { |e| e.event_type == "payment.failed" }
        assert_equal :error, failed.severity
      end

      def test_parse_payments_document_handles_multiple_payments
        events = @parser.parse_payments_document([payment_attrs, payment_attrs("id" => "pay-002")])
        assert events.size >= 2
      end

      # -----------------------------------------------------------------------
      # parse_check_total_cents — edge cases
      # -----------------------------------------------------------------------

      def test_parse_check_total_cents_returns_nil_for_missing_data_key
        assert_nil @parser.parse_check_total_cents({})
      end

      def test_parse_check_total_cents_returns_nil_for_missing_attributes_key
        assert_nil @parser.parse_check_total_cents({ "data" => {} })
      end

      def test_parse_check_total_cents_handles_zero
        doc = check_doc({ "total_cents" => 0 })
        assert_equal 0, @parser.parse_check_total_cents(doc)
      end

      # -----------------------------------------------------------------------
      # Millisecond ordering — events on the same check are sorted by ms
      # -----------------------------------------------------------------------

      def test_events_within_one_second_are_ordered_by_milliseconds
        # created_at and updated_at share the same second but differ by ms
        doc = check_doc({
          "created_at" => "2024-03-15T12:00:00.100Z",
          "updated_at" => "2024-03-15T12:00:00.900Z"
        })
        events = @parser.parse_check_document(doc).sort
        created = events.find { |e| e.event_type == "check.created" }
        updated = events.find { |e| e.event_type == "check.updated" }
        assert created.timestamp < updated.timestamp
      end
    end
  end
end
