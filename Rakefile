# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rbs"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib"
  task.pattern = "test/**/*_test.rb"
end
RuboCop::RakeTask.new(:lint) { |task| task.options = ["--cache", "false"] }

task :types do
  sh "bundle exec rbs -I sig validate"
end

task verify: %i[lint test types]
task default: :verify
