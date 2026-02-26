# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.new
loader.push_dir(File.expand_path("..", __FILE__))
loader.setup

# Explicit requires for files that must load in dependency order
# (Zeitwerk handles the rest via auto-loading on first constant reference)
require_relative "check_timeline/currency"
require_relative "check_timeline/event"
require_relative "check_timeline/timeline"
require_relative "check_timeline/sources/base_source"
require_relative "check_timeline/sources/checks_parser"
require_relative "check_timeline/sources/checks_api"
require_relative "check_timeline/sources/check_file"
require_relative "check_timeline/sources/raygun_file"
require_relative "check_timeline/aggregator"
require_relative "check_timeline/renderers/html_renderer"

module CheckTimeline
  VERSION = "1.0.0"
end
