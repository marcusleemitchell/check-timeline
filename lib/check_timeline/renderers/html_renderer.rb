# frozen_string_literal: true

require "erubi"
require "date"
require "json"
require "fileutils"
require_relative "../currency"

module CheckTimeline
  module Renderers
    # Renders a Timeline to a self-contained HTML file using an ERB template.
    #
    # Usage:
    #   renderer = HtmlRenderer.new(timeline)
    #   path     = renderer.render          # writes to ./timeline_<check_id>.html
    #   path     = renderer.render(output_path: "/tmp/my_timeline.html")
    #
    # The rendered file is entirely self-contained — all CSS and JS is inlined,
    # so it can be opened directly in any browser without a server.
    class HtmlRenderer
      TEMPLATE_PATH = File.expand_path("../../../templates/timeline.html.erb", __dir__)

      # Severity → Tailwind-compatible colour tokens (resolved to hex in template)
      SEVERITY_COLORS = {
        info:     { bg: "#e8f4fd", border: "#3b82f6", text: "#1e40af", dot: "#3b82f6", label: "Info" },
        warning:  { bg: "#fefce8", border: "#f59e0b", text: "#92400e", dot: "#f59e0b", label: "Warning" },
        error:    { bg: "#fef2f2", border: "#ef4444", text: "#991b1b", dot: "#ef4444", label: "Error" },
        critical: { bg: "#fdf4ff", border: "#a855f7", text: "#6b21a8", dot: "#a855f7", label: "Critical" }
      }.freeze

      # Category → icon (emoji) and label
      CATEGORY_META = {
        check:     { icon: "🧾", label: "Check",       color: "#0ea5e9" },
        payment:   { icon: "💳", label: "Payment",     color: "#10b981" },
        exception: { icon: "🐛", label: "Exception",   color: "#f43f5e" },
        version:   { icon: "📋", label: "Version",     color: "#8b5cf6" },
        unknown:   { icon: "❓", label: "Unknown",     color: "#94a3b8" }
      }.freeze

      SOURCE_META = {
        checks_api:  { icon: "🔌", label: "Checks API"   },
        raygun:      { icon: "🐛", label: "Raygun"        },
        paper_trail: { icon: "📋", label: "PaperTrail"   },
        unknown:     { icon: "❓", label: "Unknown"       }
      }.freeze

      attr_reader :timeline

      def initialize(timeline)
        @timeline = timeline
      end

      # Renders the timeline to an HTML file and returns the output path.
      # Optionally auto-opens the file in the default browser.
      def render(output_path: nil, open_browser: true)
        path = output_path || default_output_path
        FileUtils.mkdir_p(File.dirname(path))

        html = render_html
        File.write(path, html)

        puts "  ✓ Timeline written to: #{path}"
        open_in_browser(path) if open_browser

        path
      end

      # Returns the rendered HTML string without writing to disk.
      def render_html
        template_src = File.read(TEMPLATE_PATH)
        engine       = Erubi::Engine.new(template_src, escape: false)
        ctx          = TemplateContext.new(
          timeline:        timeline,
          severity_colors: SEVERITY_COLORS,
          category_meta:   CATEGORY_META,
          source_meta:     SOURCE_META,
          generated_at:    DateTime.now
        )
        ctx.instance_eval(engine.src)
      end

      private

      def default_output_path
        safe_id = timeline.check_id.gsub(/[^a-zA-Z0-9\-_]/, "_")
        File.join(Dir.pwd, "timeline_#{safe_id}.html")
      end

      def open_in_browser(path)
        case RUBY_PLATFORM
        when /darwin/ then system("open", path)
        when /linux/  then system("xdg-open", path)
        when /mingw|mswin|cygwin/ then system("start", path)
        end
      rescue StandardError
        # Not critical — just skip silently
      end

      # ---------------------------------------------------------------------------
      # Template context — all helpers available inside the ERB template live here.
      # ---------------------------------------------------------------------------
      class TemplateContext
        include CheckTimeline::Currency

        attr_reader :timeline, :severity_colors, :category_meta, :source_meta, :generated_at

        def initialize(timeline:, severity_colors:, category_meta:, source_meta:, generated_at:)
          @timeline        = timeline
          @severity_colors = severity_colors
          @category_meta   = category_meta
          @source_meta     = source_meta
          @generated_at    = generated_at
        end

        # Returns the pre-compiled ERB result string. Called by render_html via instance_eval.
        def _buf
          @_buf ||= String.new
        end

        # ── Formatting helpers ──────────────────────────────────────────────

        def format_timestamp(dt)
          return "—" if dt.nil?

          ms = (dt.sec_fraction * 1000).to_i
          fmt = ms > 0 ? dt.strftime("%d %b %Y %H:%M:%S.") + format("%03d", ms) : dt.strftime("%d %b %Y %H:%M:%S")
          "#{fmt} UTC"
        end

        def format_timestamp_iso(dt)
          return "" if dt.nil?

          dt.iso8601
        end

        def format_time_only(dt)
          return "—" if dt.nil?

          dt.strftime("%H:%M:%S")
        end

        # Like format_time_only but appends .ms when the timestamp has non-zero
        # sub-second precision — e.g. "20:36:54.769" vs "20:36:54".
        def format_time_precise(dt)
          return "—" if dt.nil?

          ms = (dt.sec_fraction * 1000).to_i
          ms > 0 ? dt.strftime("%H:%M:%S.") + format("%03d", ms) : dt.strftime("%H:%M:%S")
        end

        def format_date(dt)
          return "—" if dt.nil?

          dt.strftime("%A, %-d %B %Y")
        end

        def relative_offset(event_ts, base_ts)
          return "0s" if base_ts.nil?

          seconds = ((event_ts - base_ts) * 86_400).to_i
          return "0s" if seconds == 0

          parts = []
          parts << "#{seconds / 3600}h"        if seconds.abs >= 3600
          parts << "#{(seconds % 3600) / 60}m" if seconds.abs >= 60
          parts << "#{seconds % 60}s"
          (seconds.negative? ? "-" : "+") + parts.join(" ")
        end

        def severity_style(severity)
          colors = severity_colors.fetch(severity.to_sym, severity_colors[:info])
          "background:#{colors[:bg]};border-color:#{colors[:border]};color:#{colors[:text]}"
        end

        def severity_dot_color(severity)
          severity_colors.fetch(severity.to_sym, severity_colors[:info])[:dot]
        end

        def severity_label(severity)
          severity_colors.fetch(severity.to_sym, severity_colors[:info])[:label]
        end

        def severity_badge_style(severity)
          colors = severity_colors.fetch(severity.to_sym, severity_colors[:info])
          "background:#{colors[:border]};color:#fff"
        end

        def category_icon(category)
          category_meta.fetch(category.to_sym, category_meta[:unknown])[:icon]
        end

        def category_label(category)
          category_meta.fetch(category.to_sym, category_meta[:unknown])[:label]
        end

        def category_color(category)
          category_meta.fetch(category.to_sym, category_meta[:unknown])[:color]
        end

        def source_icon(source)
          source_meta.fetch(source.to_sym, source_meta[:unknown])[:icon]
        end

        def source_label(source)
          source_meta.fetch(source.to_sym, source_meta[:unknown])[:label]
        end

        def h(text)
          text.to_s
              .gsub("&", "&amp;")
              .gsub("<", "&lt;")
              .gsub(">", "&gt;")
              .gsub('"', "&quot;")
              .gsub("'", "&#39;")
        end

        def nl2br(text)
          h(text.to_s).gsub("\n", "<br>")
        end

        # ── Timeline position helpers ───────────────────────────────────────

        # Returns a 0–100 float representing where on the timeline this event sits.
        def timeline_position(event)
          return 0.0 if timeline.started_at.nil? || timeline.ended_at.nil?
          return 0.0 if timeline.started_at == timeline.ended_at

          total_span = (timeline.ended_at - timeline.started_at).to_f
          event_span = (event.timestamp - timeline.started_at).to_f
          ((event_span / total_span) * 100).clamp(0.0, 100.0).round(2)
        end

        # ── Stats ───────────────────────────────────────────────────────────

        def stats
          @stats ||= {
            total:    timeline.count,
            errors:   timeline.error_count,
            sources:  timeline.sources.size,
            duration: timeline.duration,
            by_source:   timeline.by_source.transform_values(&:count),
            by_category: timeline.by_category.transform_values(&:count),
            by_severity: timeline.severity_counts,
            final_value: timeline.formatted_final_value
          }
        end

        # ── JSON data for the mini-map JS ───────────────────────────────────

        def events_json
          data = timeline.map do |event|
            {
              id:        event.id,
              timestamp: format_timestamp_iso(event.timestamp),
              position:  timeline_position(event),
              severity:  event.severity.to_s,
              category:  event.category.to_s,
              source:    event.source.to_s,
              title:     event.title,
              dot_color: severity_dot_color(event.severity)
            }
          end
          data.to_json
        end

        # ── Value ledger for chart ───────────────────────────────────────────

        def ledger_json
          ledger = timeline.value_ledger
          return "[]" if ledger.empty?

          data = ledger.map do |event, running_total|
            {
              timestamp:         format_timestamp_iso(event.timestamp),
              label:             event.title,
              amount:            event.amount,
              amount_formatted:  format_currency(event.amount, event.currency),
              running:           running_total,
              running_formatted: format_currency(running_total, event.currency),
              currency_code:     event.currency,
              currency_symbol:   CheckTimeline::Currency.symbol(event.currency)
            }
          end
          data.to_json
        end

        # ── Chart data JSON ──────────────────────────────────────────────────
        # Produces a single JSON object consumed by the value chart:
        #
        #   points      - chronological delta events (line items, discounts,
        #                 payments), each with a normalised x position (0–1
        #                 across total time span), running total, formatted
        #                 label, category, source, and the DOM event-card id
        #                 so the scrubber can scroll to the matching card.
        #
        #                 Check-level summary events (check.created,
        #                 check.updated, check.paid) carry total_cents rather
        #                 than a delta and are intentionally excluded so the
        #                 running total isn't triple-counted.
        #
        #   exceptions  - all events with source == :raygun, expressed as
        #                 normalised x positions so they can be drawn as
        #                 vertical markers on the chart.
        #
        #   currency    - symbol string for axis labels (e.g. "£")
        #
        #   min_value / max_value - cent range used to size the Y axis.
        #
        # Event types that represent additive line-item deltas (build the check value up):
        LINE_ITEM_EVENT_TYPES = %w[
          check.line_item_added
          check.discount_applied
          check.service_charge_added
        ].freeze

        # Payment event types that settle the check (drive the balance toward zero):
        PAYMENT_EVENT_TYPES = %w[
          payment.initiated
          payment.captured
          payment.refunded
          payment.failed
        ].freeze

        def chart_data_json
          return {points: [], exceptions: [], versions: [], currency: "£",
                  min_value: 0, max_value: 0}.to_json if timeline.empty?

          t_start = timeline.started_at
          t_end   = timeline.ended_at
          span    = (t_end - t_start).to_f
          span    = 1.0 if span.zero?

          # ── Value points ─────────────────────────────────────────────────
          # The check value is built up by line items, discounts, and service
          # charges — these are true deltas we can sum directly.
          #
          # Payments are NOT deltas against that running sum. The payment
          # amount settles total_cents (net + tax + gratuity) whereas line
          # items only contribute net_cents. Treating them as simple deltas
          # produces a wrong result (e.g. £14.50 - £16.60 = -£2.10).
          #
          # Instead, when we see a payment event we drop the running balance
          # by exactly the amount still outstanding at that moment — so the
          # line always lands at zero (or remaining_cents) when fully paid.
          # For refunds we add back the refunded amount.
          # The authoritative peak value from the check record. Line items only
          # sum to net_cents; total_cents also includes tax and gratuity. We use
          # final_value_cents to bridge that gap before the payment lands so the
          # graph peak and the payment drop are both correct.
          authoritative_total = timeline.final_value_cents
          currency_code       = timeline.currency

          running        = 0
          points         = []
          peak_corrected = false   # only apply the correction once

          timeline.events.each do |event|
            next if event.amount.nil?

            if LINE_ITEM_EVENT_TYPES.include?(event.event_type)
              # Discounts are already stored as negative amounts by the parser.
              running += event.amount
              delta    = event.amount

            elsif PAYMENT_EVENT_TYPES.include?(event.event_type)
              # Before the first payment, snap the running total up to the
              # authoritative total_cents if line items alone fell short
              # (because tax / gratuity have no individual timestamped events).
              # Emit the gap as an explicit synthetic point anchored 1 second
              # before the payment so the step line visibly reaches the correct
              # peak before dropping.
              unless peak_corrected
                if authoritative_total && running < authoritative_total
                  gap   = authoritative_total - running
                  x_gap = ((event.timestamp - t_start).to_f / span).clamp(0.0, 1.0)
                  running = authoritative_total
                  points << {
                    event_id:          nil,
                    x:                 x_gap.round(6),
                    value:             running,
                    value_formatted:   format_currency(running, currency_code),
                    delta:             gap,
                    delta_formatted:   format_currency(gap, currency_code),
                    label:             "Tax & Gratuity",
                    category:          "check",
                    source:            "checks_api",
                    currency_symbol:   CheckTimeline::Currency.symbol(currency_code),
                    timestamp_label:   format_timestamp(event.timestamp)
                  }
                end
                peak_corrected = true
              end

              if event.event_type == "payment.refunded"
                # Refund: balance rises by the refunded amount
                delta    = event.amount.abs
                running += delta
              else
                # Payment (initiated/captured/failed): drop balance toward zero.
                # Cap the drop at the current running balance so we never go
                # below zero (handles partial payments correctly too).
                drop     = [event.amount.abs, running].min
                delta    = -drop
                running += delta   # running = running - drop
              end

            else
              next
            end

            x = ((event.timestamp - t_start).to_f / span).clamp(0.0, 1.0)

            points << {
              event_id:          event.id,
              x:                 x.round(6),
              value:             running,
              value_formatted:   format_currency(running, event.currency),
              delta:             delta,
              delta_formatted:   format_currency(delta, event.currency),
              label:             event.title,
              category:          event.category.to_s,
              source:            event.source.to_s,
              currency_symbol:   CheckTimeline::Currency.symbol(event.currency),
              timestamp_label:   format_timestamp(event.timestamp)
            }
          end

          # ── Exception markers ────────────────────────────────────────────
          exceptions = timeline.events
            .select  { |e| e.source == :raygun }
            .map do |e|
              x = ((e.timestamp - t_start).to_f / span).clamp(0.0, 1.0)
              {
                event_id:        e.id,
                x:               x.round(6),
                label:           e.title,
                severity:        e.severity.to_s,
                timestamp_label: format_timestamp(e.timestamp)
              }
            end

          # ── Version markers ──────────────────────────────────────────────
          versions = timeline.events
            .select  { |e| e.category == :version }
            .map do |e|
              x = ((e.timestamp - t_start).to_f / span).clamp(0.0, 1.0)
              {
                event_id:        e.id,
                x:               x.round(6),
                label:           e.title,
                severity:        e.severity.to_s,
                timestamp_label: format_timestamp(e.timestamp)
              }
            end

          # ── Y-axis range ─────────────────────────────────────────────────
          # Include authoritative_total in the max calculation so the Y-axis
          # peak reflects total_cents (net + tax + gratuity), not just the
          # sum of individually-timestamped line items.
          values    = points.map { |p| p[:value] }
          min_value = values.min || 0
          max_value = [values.max || 0, authoritative_total || 0].max

          # Infer currency symbol from first amount-bearing event
          sym = timeline.events.lazy
                        .select { |e| e.amount && e.currency }
                        .map    { |e| CheckTimeline::Currency.symbol(e.currency) }
                        .first || "£"

          {
            points:     points,
            exceptions: exceptions,
            versions:   versions,
            currency:   sym,
            min_value:  min_value,
            max_value:  max_value
          }.to_json
        end

        # ── Per-event amount formatting for the template ─────────────────────

        # Renders a formatted amount string for an event card.
        # Returns nil if the event carries no amount.
        def format_event_amount(event)
          return nil if event.amount.nil?

          format_currency(event.amount, event.currency)
        end

        # Returns the currency symbol string for a given event.
        def event_currency_symbol(event)
          CheckTimeline::Currency.symbol(event.currency)
        end
      end
    end
  end
end
