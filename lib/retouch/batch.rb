# frozen_string_literal: true

module Retouch
  class Batch
    def self.expand(inputs)
      Array(inputs).flat_map do |input|
        pattern = String(input)
        if pattern.match?(/[?*{\[]/)
          Dir.glob(pattern)
        else
          pattern
        end
      end.sort
    end

    def self.output_path(template, input, index)
      path = String(template).gsub("{name}", File.basename(input, File.extname(input)))
                             .gsub("{ext}", File.extname(input).delete_prefix("."))
                             .gsub("{dir}", File.dirname(input))
                             .gsub(/\{index(?::(\d+))?\}/) { format("%0*d", Regexp.last_match(1).to_i, index) }
      raise ArgumentError, "unknown output template token in #{path}" if path.match?(/\{[^}]+\}/)

      path
    end

    def self.run(inputs, to:, jobs: 1, force: false, dry_run: false)
      paths = expand(inputs)
      raise Error, "no input files matched" if paths.empty?
      raise Error, "input file does not exist: #{paths.find { |path| !File.file?(path) }}" unless paths.all? { |path| File.file?(path) }

      outputs = paths.each_with_index.map { |path, index| output_path(to, path, index) }
      resolved_outputs = outputs.map { |path| destination_key(path) }
      raise Error, "output template produces duplicate paths" unless resolved_outputs.uniq.length == outputs.length

      jobs = Integer(jobs)
      raise ArgumentError, "jobs must be positive" unless jobs.positive?
      if !force && (existing = outputs.find { |path| File.exist?(path) })
        raise Error, "refusing to overwrite #{existing}; use --force"
      end
      return outputs if dry_run

      worker_count = Process.respond_to?(:fork) ? jobs : 1
      children = []
      failed = false
      paths.zip(outputs).each do |input, output|
        FileUtils.mkdir_p(File.dirname(output)) unless File.dirname(output) == "."
        if worker_count > 1
          children << Process.fork do
            yield input, output
            exit! 0
          rescue StandardError => e
            warn("retouch: #{e.message}")
            exit! 1
          end
          if children.length >= worker_count
            _pid, status = Process.wait2(children.shift)
            failed ||= !status.success?
          end
        else
          yield input, output
        end
      end
      children.each do |pid|
        _child, status = Process.wait2(pid)
        failed ||= !status.success?
      end
      raise Error, "one or more batch jobs failed" if failed

      outputs
    end

    def self.destination_key(path)
      ancestor = File.expand_path(path)
      suffix = []
      until File.exist?(ancestor) || File.symlink?(ancestor)
        suffix.unshift(File.basename(ancestor))
        ancestor = File.dirname(ancestor)
      end
      resolved = File.join(File.realpath(ancestor), *suffix)
      return resolved unless File.file?(resolved)

      stat = File.stat(resolved)
      [stat.dev, stat.ino]
    end
    private_class_method :destination_key
  end

  def self.batch(inputs, to:, jobs: 1, force: false, &block)
    raise ArgumentError, "a transformation block is required" unless block

    Batch.run(inputs, to:, jobs:, force:) do |input, output|
      pipeline = block.call(Retouch.open(input))
      raise TypeError, "batch block must return a Retouch::Pipeline" unless pipeline.is_a?(Pipeline)

      pipeline.save(output)
    end
  end
end
