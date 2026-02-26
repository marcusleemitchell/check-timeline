# frozen_string_literal: true

require "date"
require_relative "../currency"

module CheckTimeline
  module Sources
    # Shared JSON:API parsing logic for check and payment documents.
    #
    # Both ChecksApiSource (live HTTP) and CheckFileSource (local JSON file)
    # include this module to avoid duplicating the event-building logic.
    #
    # The module expects the including class to provide:
    #   - #check_id   → String
    #   - #build_event(**attrs) → CheckTimeline::Event   (from BaseSource)
    #   - #event_id(*components) → String                (from BaseSource)
    #   - #parse_timestamp(value) → DateTime             (from BaseSource)
    #   - #warn_log(message)                             (from BaseSource)
    module ChecksParser
      include CheckTimeline::Currency

      # Field classification constants used by build_changes_description.
      # Defined at module level to avoid dynamic constant assignment errors.
      MONETARY_FIELDS  = %w[amount_due subtotal gratuities_cents line_items_tax_cents extra_tax_cents].freeze
      ARRAY_FIELDS     = %w[line_items discounts service_charges other_payments vat_items].freeze
      TIMESTAMP_FIELDS = %w[created_at updated_at paid_at].freeze
      SKIP_ALWAYS      = %w[id item_id simphony_id auto_service_charge_percentage micros_workstation_name].freeze

      # -----------------------------------------------------------------------
      # Top-level document parsers
      # -----------------------------------------------------------------------

      # Parse a full JSON:API check document and return an array of Events.
      #
      #   doc  - the parsed Hash from GET /public/checks/:id (or a local file)
      #
      def parse_check_document(doc)
        data       = doc["data"]        || {}
        attributes = data["attributes"] || {}
        included   = doc["included"]    || []

        venue    = find_included(included, "venues",    attributes["location_code"])
        location = find_included(included, "locations", extract_location_id(data))

        build_check_events(data, attributes, venue, location)
      end

      # Extract the authoritative total_cents from a check JSON:API document.
      # Returns an Integer when present, or nil if the field is absent.
      def parse_check_total_cents(doc)
        raw = doc.dig("data", "attributes", "total_cents")
        raw.nil? ? nil : raw.to_i
      end

      # Parse a JSON:API payments document and return an array of Events.
      #
      #   doc  - the parsed Hash/Array from GET /public/checks/:id/payments
      #          (or a local payments JSON file)
      #
      def parse_payments_document(doc)
        payments = case doc
                   when Array then doc
                   when Hash  then doc["data"] || doc["payments"] || []
                   else []
                   end

        payments.flat_map { |payment| build_payment_events(payment) }
      end

      # Parse a PaperTrail versions document and return an array of Events.
      #
      # Accepts two shapes:
      #   1. A full check JSON:API document that has version records sideloaded
      #      in its "included" array (check_versions.json format).
      #   2. A standalone array of version objects.
      #
      # Version records are identified by type == "versions" in the included
      # array, or by the presence of an "event" attribute (create/update).
      #
      # The check's currency is passed through so monetary change values are
      # formatted correctly. If not supplied, the currency is inferred from
      # any currency change recorded in the versions themselves.
      #
      def parse_versions_document(doc, currency: "GBP")
        versions = extract_version_records(doc)

        # Attempt to infer currency from any version that records a currency change
        inferred_currency = infer_currency_from_versions(versions) || currency

        versions.map { |v| build_version_event(v, inferred_currency) }.compact
      end

      # -----------------------------------------------------------------------
      # Check event builders
      # -----------------------------------------------------------------------

      def build_check_events(data, attrs, venue, location)
        events   = []
        currency = attrs.fetch("currency", "GBP")

        # ── Check created ────────────────────────────────────────────────────
        if (created_at = attrs["created_at"])
          events << build_event(
            id:          event_id("check", "created", data["id"]),
            timestamp:   parse_timestamp(created_at),
            source:      :checks_api,
            category:    :check,
            event_type:  "check.created",
            title:       "Check ##{attrs["check_number"]} Created",
            description: check_description(attrs, venue, location),
            severity:    :info,
            amount:      attrs["total_cents"].to_i,
            currency:    currency,
            metadata:    check_metadata(data, attrs, venue, location)
          )
        end

        # ── Check updated (only when meaningfully later than created_at) ─────
        if (updated_at = attrs["updated_at"]) && updated_at != attrs["created_at"]
          events << build_event(
            id:          event_id("check", "updated", data["id"], updated_at),
            timestamp:   parse_timestamp(updated_at),
            source:      :checks_api,
            category:    :check,
            event_type:  "check.updated",
            title:       "Check ##{attrs["check_number"]} Updated",
            description: "Check updated. Status: #{attrs["status"]}. " \
                         "Total: #{format_cents(attrs["total_cents"], currency)}.",
            severity:    :info,
            amount:      attrs["total_cents"].to_i,
            currency:    currency,
            metadata:    check_metadata(data, attrs, venue, location)
          )
        end

        # ── Paid ─────────────────────────────────────────────────────────────
        if (paid_at = attrs["paid_at"])
          events << build_event(
            id:          event_id("check", "paid", data["id"]),
            timestamp:   parse_timestamp(paid_at),
            source:      :checks_api,
            category:    :check,
            event_type:  "check.paid",
            title:       "Check ##{attrs["check_number"]} Paid",
            description: "Check fully settled. " \
                         "Total: #{format_cents(attrs["total_cents"], currency)}.",
            severity:    :info,
            amount:      attrs["total_cents"].to_i,
            currency:    currency,
            metadata:    check_metadata(data, attrs, venue, location)
          )
        end

        # ── Line items ───────────────────────────────────────────────────────
        # Line items have no individual timestamps; offset each by 1 second
        # from created_at so they sort after the "check created" event.
        base_ts = attrs["created_at"]
        Array(attrs["line_items"]).each_with_index do |item, idx|
          next unless base_ts

          item_ts = (DateTime.parse(base_ts) + Rational(idx + 1, 86_400)).iso8601(3)

          events << build_event(
            id:          event_id("line_item", data["id"], item["name"], idx.to_s),
            timestamp:   parse_timestamp(item_ts),
            source:      :checks_api,
            category:    :check,
            event_type:  "check.line_item_added",
            title:       "Line Item: #{item["name"]}",
            description: line_item_description(item, currency),
            severity:    :info,
            amount:      item["cents"].to_i,
            currency:    currency,
            metadata:    item.transform_keys(&:to_s)
          )
        end

        # ── Discounts ────────────────────────────────────────────────────────
        Array(attrs["discounts"]).each_with_index do |discount, idx|
          ref_ts = discount["created_at"] || attrs["updated_at"] || attrs["created_at"]
          next unless ref_ts

          events << build_event(
            id:          event_id("discount", data["id"], discount["id"] || discount["name"] || idx.to_s),
            timestamp:   parse_timestamp(ref_ts),
            source:      :checks_api,
            category:    :check,
            event_type:  "check.discount_applied",
            title:       "Discount: #{discount["name"] || discount["code"] || "Discount"}",
            description: discount_description(discount, currency),
            severity:    :info,
            amount:      -extract_discount_cents(discount).abs,
            currency:    currency,
            metadata:    discount.transform_keys(&:to_s)
          )
        end

        # ── Service charges ──────────────────────────────────────────────────
        Array(attrs["service_charges"]).each_with_index do |charge, idx|
          ref_ts = charge["created_at"] || attrs["updated_at"] || attrs["created_at"]
          next unless ref_ts

          events << build_event(
            id:          event_id("service_charge", data["id"], charge["id"] || idx.to_s),
            timestamp:   parse_timestamp(ref_ts),
            source:      :checks_api,
            category:    :check,
            event_type:  "check.service_charge_added",
            title:       "Service Charge: #{charge["name"] || "Service Charge"}",
            description: service_charge_description(charge, currency),
            severity:    :info,
            amount:      charge["cents"].to_i,
            currency:    currency,
            metadata:    charge.transform_keys(&:to_s)
          )
        end

        events.compact
      end

      # -----------------------------------------------------------------------
      # Version event builders
      # -----------------------------------------------------------------------

      def extract_version_records(doc)
        case doc
        when Array
          # Raw array of version objects
          doc
        when Hash
          if doc["included"]
            # Full check JSON:API document — pull type=="versions" from included
            Array(doc["included"]).select { |r| r["type"] == "versions" }
          elsif doc["data"].is_a?(Array)
            doc["data"].select { |r| r["type"] == "versions" }
          else
            []
          end
        else
          []
        end
      end

      def infer_currency_from_versions(versions)
        versions.each do |v|
          changes = (v.dig("attributes", "object_changes") || v["object_changes"] || {})
          if (currency_change = changes["currency"])
            # currency_change is [before, after] — take whichever is non-blank
            val = Array(currency_change).compact.reject { |c| c.to_s.strip.empty? }.last
            return val if val
          end
        end
        nil
      end

      def build_version_event(version, currency)
        attrs   = version["attributes"] || version
        changes = attrs["object_changes"] || {}
        event   = attrs["event"] || "update"
        ver_id  = version["id"] || attrs["id"]

        timestamp = attrs["created_at"]
        return nil if timestamp.nil?

        title, description, severity = describe_version(event, changes, currency, ver_id)

        build_event(
          id:          event_id("version", ver_id.to_s),
          timestamp:   parse_timestamp(timestamp),
          source:      :paper_trail,
          category:    :version,
          event_type:  "version.#{event}",
          title:       title,
          description: description,
          severity:    severity,
          metadata:    build_version_metadata(attrs, ver_id)
        )
      end

      # Produces [title, description, severity] for a version record.
      # Prioritises the most meaningful changes in the diff when multiple
      # fields changed in a single version.
      def describe_version(event, changes, currency, ver_id)
        if event == "create"
          return describe_create_version(changes, currency)
        end

        # Ordered by significance — first match wins for the title
        describe_update_version(changes, currency)
      end

      def describe_create_version(changes, currency)
        check_number = extract_after(changes, "check_number")
        status       = extract_after(changes, "status")
        title = "Check ##{check_number} Created" if check_number
        title ||= "Check Created"

        parts = []
        parts << "Status: #{status.capitalize}" if status
        parts << "Table: #{extract_after(changes, "table_id")}" if extract_after(changes, "table_id") && extract_after(changes, "table_id") != "0"
        parts << "Covers: #{extract_after(changes, "covers")}"  if extract_after(changes, "covers")

        [title, parts.join(" · "), :info]
      end

      def describe_update_version(changes, currency)
        # Status transition — most important
        if (status_change = changes["status"])
          before, after = status_change
          title    = "Status: #{fmt_val(before)} → #{fmt_val(after)}"
          severity = after.to_s == "closed" ? :warning : :info
          desc     = build_changes_description(changes, currency, skip: ["status"])
          return [title, desc, severity]
        end

        # Payment / settlement — amount_due dropping to 0 with a paid_at
        if changes["paid_at"] && extract_after(changes, "paid_at")
          amount_before = extract_before(changes, "amount_due")
          amount_after  = extract_after(changes, "amount_due")
          title = "Check Settled"
          title += " (#{format_currency(amount_before, currency)} → #{format_currency(amount_after, currency)})" if amount_before && amount_after
          return [title, build_changes_description(changes, currency, skip: ["paid_at", "amount_due"]), :info]
        end

        # Amount change without settlement
        if changes["amount_due"]
          before_cents = extract_before(changes, "amount_due")
          after_cents  = extract_after(changes, "amount_due")
          title = "Amount Due: #{format_currency(before_cents, currency)} → #{format_currency(after_cents, currency)}"
          return [title, build_changes_description(changes, currency, skip: ["amount_due"]), :info]
        end

        # Discounts applied / removed
        if changes["discounts"]
          before_arr = Array(extract_before(changes, "discounts"))
          after_arr  = Array(extract_after(changes, "discounts"))
          if after_arr.size > before_arr.size
            names = (after_arr - before_arr).map { |d| d.is_a?(Hash) ? (d["type"] || "Discount") : d.to_s }
            title = "Discount Applied: #{names.join(", ")}"
          elsif after_arr.size < before_arr.size
            names = (before_arr - after_arr).map { |d| d.is_a?(Hash) ? (d["type"] || "Discount") : d.to_s }
            title = "Discount Removed: #{names.join(", ")}"
          else
            title = "Discounts Updated"
          end
          return [title, build_changes_description(changes, currency, skip: ["discounts"]), :info]
        end

        # Service charges applied / removed
        if changes["service_charges"]
          before_arr = Array(extract_before(changes, "service_charges"))
          after_arr  = Array(extract_after(changes, "service_charges"))
          if after_arr.size > before_arr.size
            title = "Service Charge Added"
          elsif after_arr.size < before_arr.size
            title = "Service Charge Removed"
          else
            title = "Service Charges Updated"
          end
          return [title, build_changes_description(changes, currency, skip: ["service_charges"]), :info]
        end

        # Other payments recorded
        if changes["other_payments"]
          after_arr = Array(extract_after(changes, "other_payments"))
          types     = after_arr.map { |p| p.is_a?(Hash) ? (p["type"] || "Payment") : p.to_s }.uniq
          title = types.any? ? "Other Payment: #{types.join(", ")}" : "Other Payments Updated"
          return [title, build_changes_description(changes, currency, skip: ["other_payments"]), :info]
        end

        # Currency set
        if changes["currency"]
          before, after = changes["currency"]
          title = "Currency Set: #{fmt_val(before)} → #{fmt_val(after)}"
          return [title, build_changes_description(changes, currency, skip: ["currency"]), :info]
        end

        # Reason / routing change
        if changes["reason"]
          before, after = changes["reason"]
          title = "Reason: #{fmt_val(before)} → #{fmt_val(after)}"
          return [title, build_changes_description(changes, currency, skip: ["reason"]), :info]
        end

        # Fallback — list all changed field names
        changed_fields = changes.keys.reject { |k| k == "id" }
        title = changed_fields.any? ? "Updated: #{changed_fields.join(", ")}" : "Check Updated"
        [title, build_changes_description(changes, currency), :info]
      end

      # Builds a multi-line human-readable summary of all changed fields.
      # Monetary fields are formatted using format_currency.
      # Array fields (line_items, discounts, service_charges) summarise counts.
      #
      #   skip - array of field names to exclude from the output (already in title)
      def build_changes_description(changes, currency, skip: [])
        skip_set = (skip + SKIP_ALWAYS).to_set

        lines = changes.filter_map do |field, change|
          next if skip_set.include?(field)

          before, after = Array(change)
          label         = field.gsub("_", " ").split.map(&:capitalize).join(" ")

          if MONETARY_FIELDS.include?(field)
            "#{label}: #{format_currency(before, currency)} → #{format_currency(after, currency)}"
          elsif ARRAY_FIELDS.include?(field)
            b_count = Array(before).size
            a_count = Array(after).size
            next if b_count == a_count && before == after
            "#{label}: #{b_count} item(s) → #{a_count} item(s)"
          elsif TIMESTAMP_FIELDS.include?(field)
            next if before == after
            after_fmt = after ? after.to_s : "—"
            "#{label}: #{after_fmt}"
          elsif before.nil? && !after.nil?
            "#{label}: set to #{fmt_val(after)}"
          elsif !before.nil? && after.nil?
            "#{label}: cleared"
          else
            next if before.to_s == after.to_s
            "#{label}: #{fmt_val(before)} → #{fmt_val(after)}"
          end
        end

        lines.join("\n")
      end

      def build_version_metadata(attrs, ver_id)
        {
          "version_id"   => ver_id.to_s,
          "item_type"    => attrs["item_type"],
          "item_id"      => attrs["item_id"],
          "event"        => attrs["event"],
          "whodunnit"    => attrs["whodunnit"],
          "changed_fields" => (attrs["object_changes"] || {}).keys.join(", ")
        }.compact
      end

      # -----------------------------------------------------------------------
      # Version value helpers
      # -----------------------------------------------------------------------

      def extract_before(changes, field)
        Array(changes[field]).first
      end

      def extract_after(changes, field)
        val = changes[field]
        val.is_a?(Array) ? val.last : val
      end

      # Format a raw change value for display — truncates long strings and
      # renders nil/empty as a dash.
      def fmt_val(value)
        return "—" if value.nil? || value.to_s.strip.empty?
        return value.to_s if value.is_a?(Numeric)

        str = value.to_s
        str.length > 60 ? "#{str[0, 57]}…" : str
      end

      # -----------------------------------------------------------------------
      # Payment event builders
      # -----------------------------------------------------------------------

      def build_payment_events(payment)
        # Support both raw hash and JSON:API { "id": ..., "attributes": { ... } } shape
        attrs    = payment["attributes"] || payment
        pay_id   = payment["id"] || attrs["id"]
        currency = attrs.fetch("currency", "GBP")
        events   = []

        # ── Initiated ────────────────────────────────────────────────────────
        if (created_at = attrs["created_at"] || attrs["initiated_at"])
          events << build_event(
            id:          event_id("payment", "created", pay_id),
            timestamp:   parse_timestamp(created_at),
            source:      :checks_api,
            category:    :payment,
            event_type:  "payment.initiated",
            title:       "Payment Initiated",
            description: payment_description(attrs, currency),
            severity:    :info,
            amount:      attrs["amount_cents"]&.to_i || extract_payment_cents(attrs),
            currency:    currency,
            metadata:    attrs.transform_keys(&:to_s)
          )
        end

        # ── Captured / succeeded ─────────────────────────────────────────────
        if (captured_at = attrs["captured_at"] || attrs["succeeded_at"])
          events << build_event(
            id:          event_id("payment", "captured", pay_id),
            timestamp:   parse_timestamp(captured_at),
            source:      :checks_api,
            category:    :payment,
            event_type:  "payment.captured",
            title:       "Payment Captured",
            description: "Payment of #{format_cents(attrs["amount_cents"], currency)} successfully captured.",
            severity:    :info,
            amount:      attrs["amount_cents"]&.to_i || extract_payment_cents(attrs),
            currency:    currency,
            metadata:    attrs.transform_keys(&:to_s)
          )
        end

        # ── Failed ───────────────────────────────────────────────────────────
        if (failed_at = attrs["failed_at"])
          events << build_event(
            id:          event_id("payment", "failed", pay_id),
            timestamp:   parse_timestamp(failed_at),
            source:      :checks_api,
            category:    :payment,
            event_type:  "payment.failed",
            title:       "Payment Failed",
            description: payment_failure_description(attrs, currency),
            severity:    :error,
            amount:      attrs["amount_cents"]&.to_i || extract_payment_cents(attrs),
            currency:    currency,
            metadata:    attrs.transform_keys(&:to_s)
          )
        end

        # ── Refunded ─────────────────────────────────────────────────────────
        if (refunded_at = attrs["refunded_at"])
          refund_cents = attrs["refund_amount_cents"]&.to_i ||
                         attrs["amount_cents"]&.to_i        ||
                         extract_payment_cents(attrs)
          events << build_event(
            id:          event_id("payment", "refunded", pay_id),
            timestamp:   parse_timestamp(refunded_at),
            source:      :checks_api,
            category:    :payment,
            event_type:  "payment.refunded",
            title:       "Payment Refunded",
            description: "Refund of #{format_cents(refund_cents, currency)} processed.",
            severity:    :warning,
            amount:      -refund_cents.abs,
            currency:    currency,
            metadata:    attrs.transform_keys(&:to_s)
          )
        end

        events.compact
      end

      # -----------------------------------------------------------------------
      # JSON:API structural helpers
      # -----------------------------------------------------------------------

      def find_included(included, type, id)
        return nil if id.nil?

        included.find { |r| r["type"] == type && r["id"].to_s == id.to_s }
      end

      def extract_location_id(data)
        data.dig("relationships", "location", "data", "id")
      end

      # -----------------------------------------------------------------------
      # Description builders
      # -----------------------------------------------------------------------

      def check_description(attrs, venue, location)
        venue_attrs    = venue&.dig("attributes")    || {}
        location_attrs = location&.dig("attributes") || {}

        parts = []
        parts << "#{venue_attrs["name"] || attrs["location_name"]} (#{attrs["location_code"]})" \
          if attrs["location_name"] || venue_attrs["name"]
        parts << "Status: #{attrs["status"].capitalize}"    if attrs["status"]
        parts << "Table: #{attrs["table_id"]}"              if attrs["table_id"] && attrs["table_id"] != "0"
        parts << "Covers: #{attrs["covers"]}"               if attrs["covers"]
        parts << "Revenue centre: #{attrs["reason"]}"       if attrs["reason"]
        parts << "Subtotal: #{format_cents(attrs["subtotal"] || attrs["total_cents"], attrs["currency"])}"
        parts << "Tax: #{format_cents(attrs["line_items_tax_cents"], attrs["currency"])}" if attrs["line_items_tax_cents"]
        parts << "Total: #{format_cents(attrs["total_cents"], attrs["currency"])}"        if attrs["total_cents"]
        parts << "Service charge: #{location_attrs["service_charge_percentage"]}%"       if location_attrs["service_charge_percentage"]
        parts.join(" · ")
      end

      def line_item_description(item, currency)
        parts = []
        parts << "#{item["quantity"]}× #{item["name"]}"
        parts << format_cents(item["cents"], currency)
        parts << "Category: #{item["category"]}"                if item["category"]
        parts << "Revenue centre: #{item["revenue_center"]}"    if item["revenue_center"]
        parts.join(" · ")
      end

      def discount_description(discount, currency)
        name = discount["name"] || discount["code"] || "Discount"
        amount_str = if discount["cents"]
                       format_cents(discount["cents"], currency)
                     elsif discount["percentage"]
                       "#{discount["percentage"]}%"
                     else
                       "amount unknown"
                     end
        "#{name}: -#{amount_str}"
      end

      def service_charge_description(charge, currency)
        name = charge["name"] || "Service Charge"
        "#{name}: #{format_cents(charge["cents"], currency)}"
      end

      def payment_description(attrs, currency)
        amount = attrs["amount_cents"]&.to_i || extract_payment_cents(attrs)
        parts  = []
        parts << "Method: #{attrs["method"] || attrs["payment_method"] || attrs["type"] || "unknown"}"
        parts << "Amount: #{format_cents(amount, currency)}"
        parts << "Status: #{attrs["status"]}" if attrs["status"]
        ref = attrs["reference"] || attrs["external_id"] || attrs["stripe_payment_intent_id"]
        parts << "Ref: #{ref}" if ref
        parts.join(" · ")
      end

      def payment_failure_description(attrs, currency)
        amount = attrs["amount_cents"]&.to_i || extract_payment_cents(attrs)
        reason = attrs["failure_reason"] || attrs["error_message"] ||
                 attrs["decline_code"]   || attrs["failure_code"]  || "unknown reason"
        "Payment of #{format_cents(amount, currency)} failed. Reason: #{reason}"
      end

      # -----------------------------------------------------------------------
      # Monetary helpers
      # -----------------------------------------------------------------------

      # Delegates to the shared Currency module.
      # All monetary values in this API are already in cents.
      def format_cents(cents, currency)
        format_currency(cents, currency)
      end

      def extract_payment_cents(attrs)
        %w[amount_cents total_cents cents amount].each do |key|
          return attrs[key].to_i if attrs[key]
        end
        0
      end

      def extract_discount_cents(discount)
        discount["cents"] || discount["amount_cents"] || 0
      end

      # -----------------------------------------------------------------------
      # Metadata builders
      # -----------------------------------------------------------------------

      def check_metadata(data, attrs, venue, location)
        venue_attrs    = venue&.dig("attributes")    || {}
        location_attrs = location&.dig("attributes") || {}

        {
          "check_id"              => data["id"],
          "check_number"          => attrs["check_number"],
          "sequence_number"       => attrs["sequence_number"],
          "waiter_id"             => attrs["waiter_id"],
          "status"                => attrs["status"],
          "location_name"         => attrs["location_name"],
          "location_code"         => attrs["location_code"],
          "business_unit"         => attrs["business_unit"],
          "covers"                => attrs["covers"],
          "table_id"              => attrs["table_id"],
          "revenue_center_id"     => attrs["revenue_center_id"],
          "variable_tips_enabled" => attrs["variable_tips_enabled"],
          "service_charge_pct"    => location_attrs["service_charge_percentage"],
          "venue_timezone"        => venue_attrs["time_zone"],
          "total_cents"           => attrs["total_cents"],
          "remaining_cents"       => attrs["remaining_cents"],
          "net_cents"             => attrs["net_cents"],
          "line_items_tax_cents"  => attrs["line_items_tax_cents"],
          "gratuities_cents"      => attrs["gratuities_cents"]
        }.compact
      end
    end
  end
end
