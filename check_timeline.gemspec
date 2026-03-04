# frozen_string_literal: true

require_relative "lib/check_timeline/version"

Gem::Specification.new do |spec|
  spec.name        = "check_timeline"
  spec.version     = CheckTimeline::VERSION
  spec.authors     = ["Soho House Digital"]
  spec.email       = ["engineering@sohohouse.com"]
  spec.summary     = "Generates a self-contained HTML timeline for a Housepay check"
  spec.description = <<~DESC
    check-timeline fetches check, payment, and PaperTrail version events from
    the Checks API and renders them as a fully self-contained, interactive HTML
    timeline. Can be used as a standalone CLI tool or embedded in other Ruby
    applications via CheckTimeline::Generator.render(check_id:, gid:).
  DESC
  spec.homepage    = "https://github.com/SohoHouse/check-timeline"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir[
    "lib/**/*",
    "templates/**/*",
    "bin/*",
    "README.md",
    "LICENSE"
  ].reject { |f| File.directory?(f) }

  spec.bindir        = "bin"
  spec.executables   = ["check-timeline"]
  spec.require_paths = ["lib"]

  # CLI
  spec.add_dependency "thor",           "~> 1.3"

  # HTTP
  spec.add_dependency "faraday",        "~> 2.9"
  spec.add_dependency "faraday-retry",  "~> 2.2"

  # Templating
  spec.add_dependency "erubi",          "~> 1.13"

  # Type system
  spec.add_dependency "dry-struct",     "~> 1.6"
  spec.add_dependency "dry-types",      "~> 1.7"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "pry",      "~> 0.14"
end
