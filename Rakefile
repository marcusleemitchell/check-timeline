# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs    << "test"
  t.libs    << "lib"
  t.pattern = "test/unit/**/*_test.rb"
  t.verbose = false
  t.warning = false
end

task default: :test
