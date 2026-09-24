# frozen_string_literal: true

module Retouch
  module Batch
    module_function

    def run(pattern, to:, force: false, jobs: 1, level: 6, strip: false, &operation)
      raise ArgumentError, "a block is required" unless operation

      files = Array(pattern).flat_map { |item| File.file?(item) ? [item] : Dir.glob(item) }.uniq.sort
      raise Error, "no input files matched" if files.empty?

      jobs = Integer(jobs)
      raise ArgumentError, "jobs must be positive" unless jobs.positive?

      outputs = files.each_with_index.map { |file, index| expand(to, file, index) }
      raise ArgumentError, "output template maps multiple inputs to the same file" unless outputs.uniq.length == outputs.length
      raise Error, "refusing to overwrite #{outputs.find { |path| File.exist?(path) }}" unless force || outputs.none? { |path| File.exist?(path) }

      work = files.zip(outputs).map { |input, output| [input, output] }
      return work.map { |input, output| process(input, output, level:, strip:, &operation) } if jobs == 1 || !Process.respond_to?(:fork)

      work.each_slice(jobs).flat_map do |group|
        children = group.map do |input, output|
          pid = Process.fork do
            process(input, output, level:, strip:, &operation)
            exit! 0
          rescue StandardError
            exit! 1
          end
          [pid, output]
        end
        children.each do |pid, output|
          _, status = Process.wait2(pid)
          raise Error, "batch worker failed for #{output}" unless status.success?
        end
        group.map(&:last)
      end
    end

    def expand(template, path, index)
      template = String(template)
      name = File.basename(path, File.extname(path))
      values = { "name" => name, "ext" => File.extname(path).delete_prefix("."), "dir" => File.dirname(path), "index" => index.to_s }
      template.gsub(/\{(name|ext|dir|index)(?::(\d+))?\}/) do
        key, width = Regexp.last_match.captures
        value = values.fetch(key)
        key == "index" && width ? value.rjust(width.to_i, "0") : value
      end
    end

    def process(input, output, level:, strip:)
      result = yield Retouch.open(input)
      result = Retouch.from_image(result) if result.is_a?(Tessel::Image)
      raise TypeError, "batch block must return a Retouch::Pipeline" unless result.is_a?(Pipeline)

      FileUtils.mkdir_p(File.dirname(output)) unless File.dirname(output) == "."
      result.save(output, level:, strip:)
      output
    end
  end
end
