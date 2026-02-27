# frozen_string_literal: true

require_relative "../../test_helper"

module CheckTimeline
  module Renderers
    class HtmlRendererTest < Minitest::Test

      # -----------------------------------------------------------------------
      # Helpers
      # -----------------------------------------------------------------------

      def make_timeline(events: [], check_id: "abc-123", check_total_cents: 1200)
        CheckTimeline::Timeline.new(
          check_id:          check_id,
          events:            events,
          check_total_cents: check_total_cents
        )
      end

      def make_renderer(timeline = nil)
        timeline ||= make_timeline(events: [
          build_event_at("2024-03-15T12:00:00.123Z",
            event_type: "check.created",
            title:      "Check #1001 Created",
            category:   :check,
            severity:   :info,
            amount:     1200,
            currency:   "GBP",
            source:     :checks_api,
            metadata:   {
              "check_id"   => "abc-123",
              "created_at" => "2024-03-15T12:00:00.123Z",
              "updated_at" => "2024-03-15T12:05:30.456Z"
            }
          )
        ])
        HtmlRenderer.new(timeline)
      end

      def rendered(renderer = nil)
        (renderer || make_renderer).render_html
      end

      # -----------------------------------------------------------------------
      # render_html — basic shape
      # -----------------------------------------------------------------------

      def test_render_html_returns_a_string
        assert_kind_of String, rendered
      end

      def test_render_html_returns_non_empty_string
        refute_empty rendered
      end

      def test_render_html_starts_with_doctype_or_html_tag
        html = rendered
        assert(html.lstrip.start_with?("<!DOCTYPE") || html.lstrip.start_with?("<html"),
               "Expected HTML to start with DOCTYPE or <html>")
      end

      def test_render_html_contains_closing_html_tag
        assert_includes rendered, "</html>"
      end

      def test_render_html_contains_head_and_body
        html = rendered
        assert_includes html, "<head"
        assert_includes html, "<body"
      end

      # -----------------------------------------------------------------------
      # Check ID
      # -----------------------------------------------------------------------

      def test_render_html_contains_check_id
        html = make_renderer(make_timeline(check_id: "abc-123")).render_html
        assert_includes html, "abc-123"
      end

      # -----------------------------------------------------------------------
      # Event cards — data attributes
      # -----------------------------------------------------------------------

      def test_render_html_contains_event_card_elements
        assert_includes rendered, "event-card"
      end

      def test_render_html_event_card_has_data_category_without_colon_prefix
        html = rendered
        assert_includes html, 'data-category="check"'
        refute_includes html, 'data-category=":check"'
      end

      def test_render_html_event_card_has_data_severity_without_colon_prefix
        html = rendered
        assert_includes html, 'data-severity="info"'
        refute_includes html, 'data-severity=":info"'
      end

      def test_render_html_event_card_has_data_source_without_colon_prefix
        html = rendered
        assert_includes html, 'data-source="checks_api"'
        refute_includes html, 'data-source=":checks_api"'
      end

      def test_render_html_event_card_has_data_searchable_attribute
        html = rendered
        assert_includes html, "data-searchable="
      end

      def test_render_html_event_card_searchable_contains_title
        html = rendered
        assert_includes html, "check #1001 created"
      end

      # -----------------------------------------------------------------------
      # Event card content
      # -----------------------------------------------------------------------

      def test_render_html_shows_event_title
        assert_includes rendered, "Check #1001 Created"
      end

      def test_render_html_shows_event_type
        assert_includes rendered, "check.created"
      end

      def test_render_html_shows_formatted_amount
        assert_includes rendered, "£12.00"
      end

      def test_render_html_shows_event_time_with_milliseconds
        # created_at has 123ms — should appear as HH:MM:SS.123
        html = rendered
        assert_includes html, "12:00:00.123"
      end

      def test_render_html_shows_plain_time_when_no_milliseconds
        tl   = make_timeline(events: [
          build_event_at("2024-03-15T12:00:00.000Z",
            title: "No MS Event", event_type: "check.created",
            category: :check, severity: :info, source: :checks_api
          )
        ])
        html = HtmlRenderer.new(tl).render_html
        # No .000 suffix — just HH:MM:SS
        assert_includes html, "12:00:00"
        refute_includes html, "12:00:00.000"
      end

      # -----------------------------------------------------------------------
      # Metadata table — _at fields
      # -----------------------------------------------------------------------

      def test_render_html_metadata_table_shows_at_fields
        html = rendered
        assert_includes html, "created_at"
        assert_includes html, "updated_at"
      end

      def test_render_html_at_fields_display_raw_iso8601_string_with_milliseconds
        html = rendered
        assert_includes html, "2024-03-15T12:00:00.123Z"
        assert_includes html, "2024-03-15T12:05:30.456Z"
      end

      def test_render_html_at_field_values_have_timestamp_css_class
        html = rendered
        assert_includes html, "metadata-value-timestamp"
      end

      def test_render_html_non_at_metadata_fields_do_not_have_timestamp_class
        tl = make_timeline(events: [
          build_event_at("2024-03-15T12:00:00.000Z",
            title:    "Event",
            event_type: "check.created",
            category: :check,
            severity: :info,
            source:   :checks_api,
            metadata: { "check_id" => "abc-123" }
          )
        ])
        html = HtmlRenderer.new(tl).render_html
        # check_id row should NOT have the timestamp class
        refute_match(/<td[^>]*metadata-value-timestamp[^>]*>abc-123/, html)
      end

      # -----------------------------------------------------------------------
      # Check Value sidebar
      # -----------------------------------------------------------------------

      def test_render_html_shows_check_value_section
        assert_includes rendered, "Check Value"
      end

      def test_render_html_value_amount_uses_check_total_cents
        tl   = make_timeline(events: [build_event(amount: 99_99)], check_total_cents: 1200)
        html = HtmlRenderer.new(tl).render_html
        # The displayed value should be from check_total_cents (£12.00), not
        # the event amount (£99.99)
        assert_includes html, "£12.00"
      end

      def test_render_html_value_display_contains_duration
        assert_includes rendered, "Duration:"
      end

      # -----------------------------------------------------------------------
      # Duration formatting in header
      # -----------------------------------------------------------------------

      def test_render_html_header_shows_duration_for_single_event_as_less_than_one_second
        tl   = make_timeline(events: [build_event_at("2024-03-15T12:00:00.000Z")])
        html = HtmlRenderer.new(tl).render_html
        assert_includes html, "< 1s"
      end

      def test_render_html_header_shows_duration_in_seconds_for_short_span
        tl = make_timeline(events: [
          build_event_at("2024-03-15T12:00:00.000Z"),
          build_event_at("2024-03-15T12:00:47.000Z")
        ])
        html = HtmlRenderer.new(tl).render_html
        assert_includes html, "47s"
      end

      def test_render_html_header_shows_duration_in_minutes_and_seconds
        tl = make_timeline(events: [
          build_event_at("2024-03-15T12:00:00.000Z"),
          build_event_at("2024-03-15T12:14:33.000Z")
        ])
        html = HtmlRenderer.new(tl).render_html
        assert_includes html, "14m 33s"
      end

      # -----------------------------------------------------------------------
      # Severity / source / category sidebar sections
      # -----------------------------------------------------------------------

      def test_render_html_severity_rows_have_onclick_handlers
        html = rendered
        assert_includes html, "toggleSeverityFilter"
      end

      def test_render_html_severity_rows_start_with_active_class
        html = rendered
        assert_includes html, 'class="severity-row active"'
      end

      def test_render_html_severity_rows_pass_plain_string_to_js_not_symbol
        html = rendered
        assert_includes html, "toggleSeverityFilter('info'"
        refute_includes html, "toggleSeverityFilter(':info'"
      end

      def test_render_html_source_rows_have_onclick_handlers
        html = rendered
        assert_includes html, "toggleSourceFilter"
      end

      def test_render_html_source_rows_start_with_active_class
        html = rendered
        assert_includes html, 'class="source-row active"'
      end

      def test_render_html_source_rows_pass_plain_string_to_js_not_symbol
        html = rendered
        assert_includes html, "toggleSourceFilter('checks_api'"
        refute_includes html, "toggleSourceFilter(':checks_api'"
      end

      def test_render_html_category_filter_checkboxes_have_onchange_handlers
        html = rendered
        assert_includes html, "toggleCategoryFilter"
      end

      def test_render_html_category_filter_passes_plain_string_not_symbol
        html = rendered
        assert_includes html, "toggleCategoryFilter('check'"
        refute_includes html, "toggleCategoryFilter(':check'"
      end

      def test_render_html_contains_all_event_categories_in_filter
        html = rendered
        %w[check payment exception unknown].each do |cat|
          assert_includes html, "toggleCategoryFilter('#{cat}'"
        end
      end

      # -----------------------------------------------------------------------
      # JavaScript initialisation
      # -----------------------------------------------------------------------

      def test_render_html_js_initialises_active_categories_from_dom
        html = rendered
        assert_includes html, "allCategories"
        assert_includes html, "new Set(allCategories)"
      end

      def test_render_html_js_initialises_active_severities_from_dom
        html = rendered
        assert_includes html, "allSeverities"
        assert_includes html, "new Set(allSeverities)"
      end

      def test_render_html_js_initialises_active_sources_from_dom
        html = rendered
        assert_includes html, "allSources"
        assert_includes html, "new Set(allSources)"
      end

      def test_render_html_js_contains_toggle_source_filter_function
        assert_includes rendered, "function toggleSourceFilter"
      end

      def test_render_html_js_contains_apply_filters_function
        assert_includes rendered, "function applyFilters"
      end

      def test_render_html_js_apply_filters_checks_source
        assert_includes rendered, "matchesSource"
      end

      # -----------------------------------------------------------------------
      # Date groups
      # -----------------------------------------------------------------------

      def test_render_html_contains_date_group_for_each_event_date
        tl = make_timeline(events: [
          build_event_at("2024-03-15T12:00:00.000Z"),
          build_event_at("2024-03-16T09:00:00.000Z")
        ])
        html = HtmlRenderer.new(tl).render_html
        assert_includes html, "date-group"
        assert_includes html, "2024-03-15"
        assert_includes html, "2024-03-16"
      end

      def test_render_html_groups_same_day_events_under_one_date_group
        tl = make_timeline(events: [
          build_event_at("2024-03-15T10:00:00.000Z", title: "Morning"),
          build_event_at("2024-03-15T15:00:00.000Z", title: "Afternoon")
        ])
        html = HtmlRenderer.new(tl).render_html
        # Only one date group header for the same date
        assert_equal 1, html.scan('data-date="2024-03-15"').size
      end

      # -----------------------------------------------------------------------
      # Empty timeline
      # -----------------------------------------------------------------------

      def test_render_html_shows_empty_state_when_no_events
        tl   = make_timeline(events: [])
        html = HtmlRenderer.new(tl).render_html
        assert_includes html, "empty-state"
        assert_includes html, "No events found"
      end

      def test_render_html_does_not_show_timeline_div_when_empty
        tl   = make_timeline(events: [])
        html = HtmlRenderer.new(tl).render_html
        # The CSS class .event-card appears in the <style> block regardless;
        # assert that no actual card elements are rendered in the body
        refute_includes html, 'class="event-card'
      end

      # -----------------------------------------------------------------------
      # render — writes file to disk
      # -----------------------------------------------------------------------

      def test_render_writes_html_file_to_disk
        Dir.mktmpdir do |dir|
          path = File.join(dir, "out.html")
          make_renderer.render(output_path: path, open_browser: false)
          assert File.exist?(path)
        end
      end

      def test_render_file_content_is_valid_html
        Dir.mktmpdir do |dir|
          path = File.join(dir, "out.html")
          make_renderer.render(output_path: path, open_browser: false)
          content = File.read(path)
          assert_includes content, "<html"
          assert_includes content, "</html>"
        end
      end

      def test_render_returns_the_output_path
        Dir.mktmpdir do |dir|
          path   = File.join(dir, "out.html")
          result = make_renderer.render(output_path: path, open_browser: false)
          assert_equal path, result
        end
      end

      def test_render_creates_parent_directories_if_needed
        Dir.mktmpdir do |dir|
          path = File.join(dir, "nested", "deeply", "out.html")
          make_renderer.render(output_path: path, open_browser: false)
          assert File.exist?(path)
        end
      end

      # -----------------------------------------------------------------------
      # TemplateContext helpers — format_timestamp
      # -----------------------------------------------------------------------

      def test_format_timestamp_includes_milliseconds_when_present
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        make_timeline,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        dt     = DateTime.parse("2024-03-15T12:00:00.769Z")
        result = ctx.format_timestamp(dt)
        assert_includes result, ".769"
      end

      def test_format_timestamp_omits_milliseconds_when_zero
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        make_timeline,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        dt     = DateTime.parse("2024-03-15T12:00:00.000Z")
        result = ctx.format_timestamp(dt)
        refute_includes result, "."
      end

      def test_format_timestamp_returns_dash_for_nil
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        make_timeline,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        assert_equal "—", ctx.format_timestamp(nil)
      end

      # -----------------------------------------------------------------------
      # TemplateContext helpers — format_time_precise
      # -----------------------------------------------------------------------

      def test_format_time_precise_appends_milliseconds_when_non_zero
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        make_timeline,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        dt = DateTime.parse("2024-03-15T12:00:00.123Z")
        assert_equal "12:00:00.123", ctx.format_time_precise(dt)
      end

      def test_format_time_precise_omits_milliseconds_when_zero
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        make_timeline,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        dt = DateTime.parse("2024-03-15T12:00:00.000Z")
        assert_equal "12:00:00", ctx.format_time_precise(dt)
      end

      def test_format_time_precise_returns_dash_for_nil
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        make_timeline,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        assert_equal "—", ctx.format_time_precise(nil)
      end

      def test_format_time_precise_pads_milliseconds_to_three_digits
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        make_timeline,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        dt = DateTime.parse("2024-03-15T12:00:00.010Z")
        assert_equal "12:00:00.010", ctx.format_time_precise(dt)
      end

      # -----------------------------------------------------------------------
      # TemplateContext helpers — stats
      # -----------------------------------------------------------------------

      def test_stats_returns_correct_total_count
        tl  = make_timeline(events: [build_event, build_event, build_event])
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        tl,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        assert_equal 3, ctx.stats[:total]
      end

      def test_stats_returns_correct_error_count
        tl = make_timeline(events: [
          build_event(severity: :info),
          build_event(severity: :error),
          build_event(severity: :critical)
        ])
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        tl,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        assert_equal 2, ctx.stats[:errors]
      end

      def test_stats_includes_formatted_final_value
        tl  = make_timeline(check_total_cents: 1200, events: [build_event(amount: 1200, currency: "GBP")])
        ctx = HtmlRenderer::TemplateContext.new(
          timeline:        tl,
          severity_colors: HtmlRenderer::SEVERITY_COLORS,
          category_meta:   HtmlRenderer::CATEGORY_META,
          source_meta:     HtmlRenderer::SOURCE_META,
          generated_at:    DateTime.now
        )
        assert_equal "£12.00", ctx.stats[:final_value]
      end

      # -----------------------------------------------------------------------
      # Multiple event categories — version events are included
      # -----------------------------------------------------------------------

      def test_render_html_includes_version_category_events
        tl = make_timeline(events: [
          build_event(category: :version, event_type: "version.update", title: "Check Updated",
                      source: :paper_trail)
        ])
        html = HtmlRenderer.new(tl).render_html
        assert_includes html, 'data-category="version"'
      end

      def test_render_html_filter_checkboxes_include_version_category
        # CATEGORIES includes :version — the template iterates CATEGORIES
        tl   = make_timeline(events: [build_event])
        html = HtmlRenderer.new(tl).render_html
        assert_includes html, "toggleCategoryFilter('version'"
      end
    end
  end
end
