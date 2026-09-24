# frozen_string_literal: true

require "bundler/setup"
require "simplecov" if ENV["COVERAGE"] == "1"

if ENV["COVERAGE"] == "1"
  SimpleCov.start do
    add_filter { |source| source.filename.include?("/test/") }
    minimum_coverage Integer(ENV.fetch("COVERAGE_MIN", "85"))
  end
end

require "json"
require "stringio"
require "test/unit"
require "tmpdir"
require "retouch"
