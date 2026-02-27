# frozen_string_literal: true

require_relative "../../test_helper"

module CheckTimeline
  module Sources
    class RaygunFileTest < Minitest::Test

      FIXTURES = File.expand_path("../../fixtures", __dir__)

      def fixture(name)
        File.join(FIXTURES, name)
      end

      # -----------------------------------------------------------------------
      # available?
      # -----------------------------------------------------------------------

      def test_available_returns_false_when_no_files_given
        source = RaygunFileSource.new(check_id: "abc-123", files: [])
        refute source.available?
      end

      def test_available_returns_false_when_files_is_nil
        source = RaygunFileSource.new(check_id: "abc-123", files: nil)
        refute source.available?
      end

      def test_available_returns_true_when_at_least_one_file_exists
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        assert source.available?
      end

      def test_available_returns_false_when_file_does_not_exist
        source = RaygunFileSource.new(check_id: "abc-123", files: ["/nonexistent/path/error.json"])
        refute source.available?
      end

      # -----------------------------------------------------------------------
      # fetch — flat Raygun4Ruby format
      # -----------------------------------------------------------------------

      def test_fetch_flat_returns_one_event
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        events = source.fetch
        assert_equal 1, events.size
      end

      def test_fetch_flat_event_is_a_check_timeline_event
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_instance_of CheckTimeline::Event, event
      end

      def test_fetch_flat_event_has_correct_class_name_in_title
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.title, "ActiveRecord::RecordNotFound"
      end

      def test_fetch_flat_event_has_correct_message_in_title
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.title, "Couldn't find Check with id=abc-123"
      end

      def test_fetch_flat_event_has_exception_category
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal :exception, event.category
      end

      def test_fetch_flat_event_has_raygun_source
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal :raygun, event.source
      end

      def test_fetch_flat_event_has_exception_raised_event_type
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal "exception.raised", event.event_type
      end

      def test_fetch_flat_event_has_error_severity
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal :error, event.severity
      end

      def test_fetch_flat_event_timestamp_parses_occurred_on
        source    = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event     = source.fetch.first
        expected  = DateTime.parse("2024-03-15T12:03:45.678Z")
        assert_equal expected, event.timestamp
      end

      def test_fetch_flat_event_timestamp_preserves_milliseconds
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        ms     = (event.timestamp.sec_fraction * 1000).to_i
        assert_equal 678, ms
      end

      def test_fetch_flat_event_description_contains_message
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.description, "Couldn't find Check with id=abc-123"
      end

      def test_fetch_flat_event_description_contains_request_line
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.description, "Request:"
        assert_includes event.description, "GET"
        assert_includes event.description, "https://api.example.com/public/checks/abc-123"
      end

      def test_fetch_flat_event_description_contains_stack_trace
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.description, "Stack trace:"
      end

      def test_fetch_flat_event_description_contains_tags
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.description, "Tags:"
        assert_includes event.description, "production"
      end

      def test_fetch_flat_event_description_contains_machine_name
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.description, "web-worker-01"
      end

      def test_fetch_flat_event_description_contains_app_version
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.description, "main-abc1234"
      end

      def test_fetch_flat_metadata_includes_file_path
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert event.metadata.key?("file")
        assert_includes event.metadata["file"], "raygun_flat.json"
      end

      def test_fetch_flat_metadata_includes_user_custom_data_as_prefixed_keys
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert event.metadata.key?("custom_check_id")
        assert_equal "abc-123", event.metadata["custom_check_id"]
      end

      def test_fetch_flat_metadata_includes_machine_name
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal "web-worker-01", event.metadata["machine_name"]
      end

      def test_fetch_flat_metadata_includes_app_version
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal "main-abc1234", event.metadata["app_version"]
      end

      def test_fetch_flat_metadata_includes_tags
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal "production, api", event.metadata["tags"]
      end

      def test_fetch_flat_metadata_includes_request_http_method
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_equal "GET", event.metadata["http_method"]
      end

      def test_fetch_flat_metadata_includes_request_url
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_flat.json")])
        event  = source.fetch.first
        assert_includes event.metadata["url"], "checks/abc-123"
      end

      def test_fetch_flat_description_does_not_include_unknown_request_line_when_request_is_empty
        # Inline minimal payload with an empty request object — same shape as
        # the real 273334942032.json where "request": {} is present
        Dir.mktmpdir do |dir|
          path = File.join(dir, "empty_request.json")
          File.write(path, JSON.generate({
            "OccurredOn" => "2024-03-15T12:00:00.000Z",
            "error"      => { "className" => "RuntimeError", "message" => "boom", "stackTrace" => [] },
            "request"    => {}
          }))
          source = RaygunFileSource.new(check_id: "abc-123", files: [path])
          event  = source.fetch.first
          refute_includes event.description, "Request: ? ?"
        end
      end

      # -----------------------------------------------------------------------
      # fetch — nested Details envelope format
      # -----------------------------------------------------------------------

      def test_fetch_nested_returns_one_event
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        events = source.fetch
        assert_equal 1, events.size
      end

      def test_fetch_nested_event_has_correct_class_name_in_title
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_includes event.title, "System.NullReferenceException"
      end

      def test_fetch_nested_event_has_correct_message_in_title
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_includes event.title, "Object reference not set"
      end

      def test_fetch_nested_event_has_error_severity_from_http_500
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_equal :error, event.severity
      end

      def test_fetch_nested_event_description_contains_inner_exception
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_includes event.description, "Caused by:"
        assert_includes event.description, "ArgumentError"
        assert_includes event.description, "payment_method cannot be nil"
      end

      def test_fetch_nested_event_description_contains_http_response_status
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_includes event.description, "Response: HTTP 500"
      end

      def test_fetch_nested_event_description_contains_request_url
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_includes event.description, "https://api.example.com/public/checks/abc-123/payments"
      end

      def test_fetch_nested_metadata_includes_user
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_equal "user@example.com", event.metadata["user"]
      end

      def test_fetch_nested_metadata_includes_status_code
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert_equal 500, event.metadata["status_code"]
      end

      def test_fetch_nested_metadata_includes_custom_data
        source = RaygunFileSource.new(check_id: "abc-123", files: [fixture("raygun_nested.json")])
        event  = source.fetch.first
        assert event.metadata.key?("custom_check_id")
        assert_equal "abc-123", event.metadata["custom_check_id"]
      end

      # -----------------------------------------------------------------------
      # Severity derivation
      # -----------------------------------------------------------------------

      def test_severity_is_error_for_500_response
        Dir.mktmpdir do |dir|
          path = write_minimal_payload(dir, status_code: 500)
          event = RaygunFileSource.new(check_id: "x", files: [path]).fetch.first
          assert_equal :error, event.severity
        end
      end

      def test_severity_is_warning_for_404_response
        Dir.mktmpdir do |dir|
          path = write_minimal_payload(dir, status_code: 404)
          event = RaygunFileSource.new(check_id: "x", files: [path]).fetch.first
          assert_equal :warning, event.severity
        end
      end

      def test_severity_is_critical_for_out_of_memory_error
        Dir.mktmpdir do |dir|
          path = write_minimal_payload(dir, class_name: "OutOfMemoryError")
          event = RaygunFileSource.new(check_id: "x", files: [path]).fetch.first
          assert_equal :critical, event.severity
        end
      end

      def test_severity_defaults_to_error_for_unknown_exception_with_no_status
        Dir.mktmpdir do |dir|
          path = write_minimal_payload(dir)
          event = RaygunFileSource.new(check_id: "x", files: [path]).fetch.first
          assert_equal :error, event.severity
        end
      end

      # -----------------------------------------------------------------------
      # Multiple files
      # -----------------------------------------------------------------------

      def test_fetch_multiple_files_returns_one_event_per_file
        source = RaygunFileSource.new(
          check_id: "abc-123",
          files: [fixture("raygun_flat.json"), fixture("raygun_nested.json")]
        )
        assert_equal 2, source.fetch.size
      end

      def test_fetch_multiple_files_events_have_distinct_ids
        source = RaygunFileSource.new(
          check_id: "abc-123",
          files: [fixture("raygun_flat.json"), fixture("raygun_nested.json")]
        )
        ids = source.fetch.map(&:id)
        assert_equal ids.uniq.size, ids.size
      end

      # -----------------------------------------------------------------------
      # Error handling
      # -----------------------------------------------------------------------

      def test_fetch_returns_empty_array_for_nonexistent_file
        source = RaygunFileSource.new(check_id: "abc-123", files: ["/no/such/file.json"])
        assert_empty source.fetch
      end

      def test_fetch_skips_invalid_json_file_and_continues
        Dir.mktmpdir do |dir|
          bad_path  = File.join(dir, "bad.json")
          good_path = fixture("raygun_flat.json")
          File.write(bad_path, "{ not valid json }")

          source = RaygunFileSource.new(check_id: "abc-123", files: [bad_path, good_path])
          events = source.fetch
          assert_equal 1, events.size
        end
      end

      def test_safe_fetch_returns_empty_array_when_not_available
        source = RaygunFileSource.new(check_id: "abc-123", files: [])
        assert_empty source.safe_fetch
      end

      # -----------------------------------------------------------------------
      # Glob resolution
      # -----------------------------------------------------------------------

      def test_constructor_accepts_glob_pattern_and_resolves_matching_files
        Dir.mktmpdir do |dir|
          FileUtils.cp(fixture("raygun_flat.json"),   File.join(dir, "error_1.json"))
          FileUtils.cp(fixture("raygun_nested.json"), File.join(dir, "error_2.json"))

          source = RaygunFileSource.new(check_id: "abc-123", files: "#{dir}/*.json")
          assert_equal 2, source.fetch.size
        end
      end

      # -----------------------------------------------------------------------
      # Stack trace truncation
      # -----------------------------------------------------------------------

      def test_stack_trace_is_truncated_to_max_frames
        Dir.mktmpdir do |dir|
          frames = (1..20).map { |i| { "lineNumber" => i.to_s, "fileName" => "file_#{i}.rb", "methodName" => "method_#{i}" } }
          path   = write_minimal_payload(dir, stack_trace: frames)
          event  = RaygunFileSource.new(check_id: "x", files: [path]).fetch.first
          assert_includes event.description, "more frames"
        end
      end

      private

      def write_minimal_payload(dir, class_name: "RuntimeError", message: "Something went wrong",
                                     status_code: nil, stack_trace: [])
        payload = {
          "OccurredOn" => "2024-03-15T12:00:00.000Z",
          "error"      => {
            "className"  => class_name,
            "message"    => message,
            "stackTrace" => stack_trace
          }
        }

        if status_code
          payload["Details"] = {
            "Error"    => { "ClassName" => class_name, "Message" => message, "StackTrace" => stack_trace },
            "Response" => { "StatusCode" => status_code }
          }
          payload.delete("error")
        end

        path = File.join(dir, "#{SecureRandom.hex(4)}.json")
        File.write(path, JSON.generate(payload))
        path
      end
    end
  end
end
