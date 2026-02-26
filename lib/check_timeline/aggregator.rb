# frozen_string_literal: true

module CheckTimeline
  # Orchestrates all configured data sources, collects their events, and
  # returns a single populated Timeline sorted chronologically.
  #
  # Usage:
  #   aggregator = Aggregator.new(
  #     check_id: "abc-123",
  #     sources:  [
  #       Sources::ChecksApiSource.new(check_id: "abc-123"),
  #       Sources::RaygunFileSource.new(check_id: "abc-123", files: ["error1.json"])
  #     ]
  #   )
  #   timeline = aggregator.run
  #
  # The aggregator runs each source sequentially by default, or in parallel
  # threads when parallel: true is passed.
  class Aggregator
    attr_reader :check_id, :sources

    def initialize(check_id:, sources: [], parallel: false)
      @check_id = check_id
      @sources  = sources
      @parallel = parallel
    end

    # Runs all sources and returns a populated Timeline.
    # Prints progress to $stdout unless quiet: true is set.
    def run(quiet: false)
      log("Fetching timeline for check: #{check_id}", quiet)
      log("Sources configured: #{sources.size}", quiet)

      all_events, check_total_cents = @parallel ? fetch_parallel(quiet) : fetch_sequential(quiet)

      log("", quiet)
      log("Total events collected: #{all_events.size}", quiet)

      Timeline.new(check_id: check_id, events: all_events, check_total_cents: check_total_cents)
    end

    private

    # ------------------------------------------------------------------
    # Fetching strategies
    # ------------------------------------------------------------------

    def fetch_sequential(quiet)
      check_total_cents = nil
      all_events = sources.flat_map do |source|
        events = fetch_source(source, quiet)
        check_total_cents ||= source.check_total_cents if source.respond_to?(:check_total_cents)
        events
      end
      [all_events, check_total_cents]
    end

    def fetch_parallel(quiet)
      mutex   = Mutex.new
      results = Array.new(sources.size)

      threads = sources.each_with_index.map do |source, index|
        Thread.new do
          events = fetch_source(source, quiet, mutex: mutex)
          results[index] = events
        end
      end

      threads.each(&:join)

      all_events = results.flatten.compact
      check_total_cents = sources.lazy
                                 .select { |s| s.respond_to?(:check_total_cents) }
                                 .filter_map(&:check_total_cents)
                                 .first
      [all_events, check_total_cents]
    end

    def fetch_source(source, quiet, mutex: nil)
      label = source.source_name

      synchronised(mutex) { log("  → Fetching from #{label}...", quiet) }

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      events     = source.safe_fetch
      elapsed    = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      synchronised(mutex) do
        if events.empty?
          log("    ✗ #{label}: no events returned (#{ms(elapsed)})", quiet)
        else
          log("    ✓ #{label}: #{events.size} event(s) (#{ms(elapsed)})", quiet)
        end
      end

      events
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def synchronised(mutex, &block)
      mutex ? mutex.synchronize(&block) : block.call
    end

    def ms(seconds)
      "#{(seconds * 1000).round}ms"
    end

    def log(message, quiet)
      return if quiet

      $stdout.puts message
    end
  end
end
