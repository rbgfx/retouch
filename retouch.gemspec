# frozen_string_literal: true

require_relative "lib/retouch/version"

Gem::Specification.new do |spec|
  spec.name = "retouch"
  spec.version = Retouch::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Ruby image resizing and shape tools"
  spec.description = "A small Ruby image editor and command line tool for resizing and shape operations."
  spec.homepage = "https://github.com/rbgfx/retouch"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |file|
      file.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ test/ .github/]) || file == "Gemfile.lock"
    end
  end
  spec.bindir = "exe"
  spec.executables = ["retouch"]
  spec.require_paths = ["lib"]

  spec.add_dependency "tessel", ">= 0.2.0", "< 1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rbs", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "test-unit", "~> 3.6"
end
