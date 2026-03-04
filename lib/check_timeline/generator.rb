# frozen_string_literal: true

module CheckTimeline
  # Programmatic entry point for embedding check-timeline inside other Ruby
  # applications (e.g. the check-service admin panel).
  #
  # The CLI is deliberately not involved — this class talks directly to the
  # source and renderer layers, returning the finished HTML string so the
  # caller can serve it however it likes.
  #
  # Usage:
  #
  #   html = CheckTimeline::Generator.render(
  #     check_id: "8ac70c0e-8760-47b6-92f1-a8bf26e86a77",
  #     gid:      "user@example.com"
  #   )
  #
  # The returned string is a fully self-contained HTML document — all CSS and
  # JS is inlined — ready to be written to a file or served directly as a
  # response body.
  #
  # Options:
  #   check_id: (required) UUID of the check to fetch.
  #   gid:      (required) User identifier sent as X-On-Behalf-Of.
  #             Must be the caller's authenticated identity.
  #   api_key:  (optional) Overrides the CHECKS_API_KEY environment variable.
  #             Useful when the host app already holds the key in memory.
  class Generator
    # Render a timeline for the given check and return the HTML string.
    #
    # Raises +CheckTimeline::Generator::Error+ if no source is available or
    # no events are found.
    def self.render(check_id:, gid:, api_key: nil)
      new(check_id: check_id, gid: gid, api_key: api_key).render
    end

    def initialize(check_id:, gid:, api_key: nil)
      @check_id = check_id.to_s.strip
      @gid      = gid.to_s.strip
      @api_key  = api_key
    end

    def render
      validate!

      source   = build_source
      events   = source.safe_fetch
      timeline = CheckTimeline::Timeline.new(
        check_id:          @check_id,
        events:            events,
        check_total_cents: source.check_total_cents
      )

      raise Error, "No events found for check #{@check_id}" if timeline.empty?

      CheckTimeline::Renderers::HtmlRenderer.new(timeline).render_html
    end

    private

    def validate!
      raise Error, "check_id is required" if @check_id.empty?
      raise Error, "gid is required"      if @gid.empty?

      effective_key = @api_key || ENV[Sources::ChecksApiSource::ENV_API_KEY].to_s
      raise Error, "CHECKS_API_KEY is not set" if effective_key.strip.empty?
    end

    def build_source
      # Temporarily inject a caller-supplied api_key into the environment so
      # ChecksApiSource can pick it up via ENV, then restore the original value.
      # This avoids mutating global state permanently.
      if @api_key
        original = ENV[Sources::ChecksApiSource::ENV_API_KEY]
        ENV[Sources::ChecksApiSource::ENV_API_KEY] = @api_key
        source = Sources::ChecksApiSource.new(check_id: @check_id, gid: @gid)
        ENV[Sources::ChecksApiSource::ENV_API_KEY] = original
        source
      else
        Sources::ChecksApiSource.new(check_id: @check_id, gid: @gid)
      end
    end

    # Raised when the generator cannot produce a timeline.
    class Error < StandardError; end
  end
end
