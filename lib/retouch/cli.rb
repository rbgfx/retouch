# frozen_string_literal: true

require "json"
require "optparse"

module Retouch
  class CLI
    OPERATIONS = %w[
      info resize thumbnail crop flip flop rotate pad extend border trim grayscale invert brightness
      contrast gamma saturate tint opacity quantize blur sharpen pixelate overlay watermark text rect
      arrow montage append spritesheet animate diff
    ].freeze

    def self.run(argv, out: $stdout, err: $stderr)
      new(argv, out:, err:).run
    rescue ArgumentError, OptionParser::ParseError => e
      err.puts("retouch: #{e.message}")
      2
    end

    def initialize(argv, out:, err:)
      @args = argv.dup
      @out = out
      @err = err
      @pid = Process.pid
      @options = { jobs: 1, level: 6, frame: 0 }
      read_global_options
      raise ArgumentError, "PNG level must be between 0 and 9" unless @options[:level].between?(0, 9)
      raise ArgumentError, "jobs must be positive" unless @options[:jobs].positive?
      raise ArgumentError, "frame must not be negative" if @options[:frame].negative?
    end

    def run
      return help if @options[:help] || @args.empty?

      if @args.first == "info"
        @args.shift
        return info_command
      end
      if @args.first == "help"
        @args.shift
        return help(@args.shift)
      end
      return diff_command if @args.first == "diff"

      operation_at = @args.index { |token| OPERATIONS.include?(token) }
      return fail_usage("missing operation") unless operation_at

      inputs = expand_inputs(@args.shift(operation_at))
      operations = parse_operations(@args)
      return fail_usage("at least one input is required") if inputs.empty?
      return aggregate(inputs, operations) if %w[montage append animate spritesheet].include?(operations.first&.first)

      transform(inputs, operations)
    rescue ArgumentError, OptionParser::ParseError => e
      @err.puts("retouch: #{e.message}")
      2
    rescue StandardError => e
      @err.puts("retouch: #{e.message}")
      @err.puts(e.backtrace.first) if @options[:verbose]
      1
    end

    private

    def read_global_options
      remaining = []
      until @args.empty?
        token = @args.shift
        case token
        when "-h", "--help" then @options[:help] = true
        when "-o", "--output" then @options[:output] = require_value(token)
        when "--dry-run" then @options[:dry_run] = true
        when "--verbose" then @options[:verbose] = true
        when "--quiet" then @options[:quiet] = true
        when "--force" then @options[:force] = true
        when "--strip" then @options[:strip] = true
        when "--jobs" then @options[:jobs] = Integer(require_value(token))
        when "--level" then @options[:level] = Integer(require_value(token))
        when "--frame" then @options[:frame] = Integer(require_value(token))
        else remaining << token
        end
      end
      @args = remaining
    end

    def require_value(option)
      value = @args.shift
      raise OptionParser::MissingArgument, option unless value

      value
    end

    def expand_inputs(inputs)
      inputs.flat_map { |item| File.file?(item) ? [item] : Dir.glob(item) }.uniq.sort
    end

    def parse_operations(tokens)
      operations = []
      until tokens.empty?
        name = tokens.shift
        raise ArgumentError, "unknown operation: #{name}" unless OPERATIONS.include?(name)

        args, options = case name
                        when "resize", "thumbnail", "crop" then parse_geometry_options(tokens)
                        when "rotate", "pad", "brightness", "contrast", "gamma", "saturate", "opacity", "pixelate", "tint" then [[required(tokens, name)], {}]
                        when "extend" then [[required(tokens, name), required(tokens, name)], {}]
                        when "border" then [[required(tokens, name), tokens.first&.start_with?("#") ? tokens.shift : "#000000"], {}]
                        when "quantize" then [[], read_options(tokens, colors: :integer, dither: :symbol)]
                        when "blur" then [[], read_options(tokens, sigma: :float)]
                        when "sharpen" then [[], read_options(tokens, amount: :float, sigma: :float)]
                        when "text" then [[required(tokens, name)], read_options(tokens, at: :symbol, size: :integer, color: :string, font: :string, background: :string, padding: :integer)]
                        when "rect" then [[required(tokens, name)], read_options(tokens, color: :string, fill: :boolean, width: :integer)]
                        when "arrow" then [[required(tokens, name), required(tokens, name), required(tokens, name), required(tokens, name)], read_options(tokens, color: :string, width: :float, head: :float)]
                        when "overlay", "watermark" then [[required(tokens, name)], read_options(tokens, x: :integer, y: :integer, gravity: :symbol, opacity: :float, blend: :symbol)]
                        when "montage" then [[], read_options(tokens, cols: :integer, gap: :integer, background: :string, label: :boolean, font: :string)]
                        when "append" then [[], read_options(tokens, direction: :symbol, gap: :integer, background: :string)]
                        when "spritesheet" then [[], read_options(tokens, cols: :integer, gap: :integer, background: :string)]
                        when "animate" then [[], read_options(tokens, fps: :float, delay: :float, loop: :boolean)]
                        when "trim" then [[], read_options(tokens, fuzz: :integer, color: :string)]
                        when "info", "flip", "flop", "grayscale", "invert" then [[], {}]
                        else raise ArgumentError, "#{name} cannot be used in a pipeline"
                        end
        operations << [name, args, options]
      end
      operations
    end

    def parse_geometry_options(tokens)
      geometry = required(tokens, "geometry")
      options = read_options(tokens, filter: :symbol, gravity: :symbol, fuzz: :integer, color: :string)
      [[geometry], options]
    end

    def read_options(tokens, specification)
      options = {}
      loop do
        break unless tokens.first&.start_with?("--")

        token = tokens.shift.delete_prefix("--")
        disabled = token.start_with?("no-")
        option = token.delete_prefix("no-").tr("-", "_").to_sym
        type = specification[option]
        raise OptionParser::InvalidOption, "--#{option}" unless type

        if type == :boolean
          options[option] = !disabled
        else
          value = required(tokens, option)
          options[option] = case type
                            when :integer then Integer(value)
                            when :float then Float(value)
                            when :symbol then value.tr("-", "_").to_sym
                            else value
                            end
        end
      end
      options
    end

    def required(tokens, name)
      value = tokens.shift
      raise OptionParser::MissingArgument, name unless value

      value
    end

    def info_command
      files = expand_inputs(@args)
      return fail_usage("info needs an input file") if files.empty?

      files.each { |path| announce(JSON.pretty_generate(path: path, **Operations.info(ImageIO.read(path, frame: @options[:frame])))) }
      0
    end

    def diff_command
      @args.shift
      files = expand_inputs(@args)
      raise OptionParser::MissingArgument, "diff expects two image paths" unless files.length == 2

      output = @options[:output] || "diff.png"
      return announce("retouch diff #{files.join(" ")} -o #{output}") if @options[:dry_run]

      image = Operations.diff(ImageIO.read(files[0]), ImageIO.read(files[1]))
      prepare_output(output)
      ImageIO.write(image, output, level: @options[:level], strip: @options[:strip])
      announce(format("diff %<ratio>.2f%% (%<pixels>s pixels)", ratio: image.metadata.fetch("diff_ratio").to_f * 100, pixels: image.metadata.fetch("diff_pixels")))
      announce(output)
      0
    end

    def aggregate(files, operations)
      raise ArgumentError, "aggregate commands cannot be chained" unless operations.length == 1

      operation = operations.first
      name, _args, options = operation
      images = files.map { |path| ImageIO.read(path, frame: @options[:frame]) }
      case name
      when "montage", "append"
        options[:labels] = files.map { |path| File.basename(path) } if name == "montage" && options[:label]
        result = Operations.public_send(name, images, **options)
        write(result)
      when "spritesheet"
        result, map = Operations.spritesheet(images, **options)
        output = @options[:output] || "spritesheet.png"
        return announce("retouch spritesheet #{files.length} images -o #{output}") if @options[:dry_run]

        prepare_output(output, sidecars: [output.sub(/\.[^.]+\z/, ".json")])
        ImageIO.write(result, output, level: @options[:level], strip: @options[:strip])
        File.write(output.sub(/\.[^.]+\z/, ".json"), JSON.pretty_generate(map))
        announce(output)
        0
      when "animate"
        output = @options[:output] || "animation.gif"
        return announce("retouch animate #{files.length} frames -o #{output}") if @options[:dry_run]

        prepare_output(output)
        Operations.animate(images, output, **options)
        announce(output)
        0
      end
    end

    def transform(files, operations)
      return fail_usage("an output path with -o is required") unless @options[:output]

      if files.length > 1
        outputs = files.map.with_index { |file, index| Batch.expand(@options[:output], file, index) }
        collision = outputs.group_by(&:itself).find { |_, same| same.length > 1 }
        raise ArgumentError, "output template collision: #{collision.first}" if collision
        raise Error, "refusing to overwrite output; use --force" if !@options[:force] && outputs.any? { |path| File.exist?(path) }
        return 0 if @options[:dry_run] && files.zip(outputs).each { |input, output| announce("#{output} <= #{input}") }

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        outputs = Batch.run(files, to: @options[:output], force: @options[:force], jobs: @options[:jobs], level: @options[:level], strip: @options[:strip]) do |pipeline|
          pipeline = apply_operations(pipeline, operations)
          pipeline
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        announce(format("batch completed in %<elapsed>.3fs", elapsed:)) if @options[:verbose]
        outputs.each { |path| announce(path) }
        return 0
      end
      input = files.first
      output = Batch.expand(@options[:output], input, 0)
      return announce("retouch #{input} #{operations.map(&:first).join(" ")} -o #{@options[:output]}") if @options[:dry_run]
      raise Error, "refusing to overwrite #{output}; use --force" if File.exist?(output) && !@options[:force]

      FileUtils.mkdir_p(File.dirname(output)) unless File.dirname(output) == "."

      pipeline = Retouch.open(input, frame: @options[:frame])
      pipeline = apply_operations(pipeline, operations)
      pipeline.save(output, level: @options[:level], strip: @options[:strip])
      announce(output)
      0
    end

    def write(image)
      output = @options[:output] || "retouch.png"
      return announce("retouch #{output}") if @options[:dry_run]

      prepare_output(output)
      ImageIO.write(image, output, level: @options[:level], strip: @options[:strip])
      announce(output)
      0
    end

    def announce(message)
      @out.puts(message) unless @options[:quiet] || Process.pid != @pid
      0
    end

    def apply_operations(pipeline, operations)
      image = pipeline.to_image
      operations.each do |name, args, options|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        args = args.dup
        args[0] = ImageIO.read(args[0]) if %w[overlay watermark].include?(name) && args[0].is_a?(String)
        image = Operations.apply(image, name, *args, **options)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        announce(format("%<name>s completed in %<elapsed>.3fs", name:, elapsed:)) if @options[:verbose]
      end
      Retouch.from_image(image)
    end

    def prepare_output(path, sidecars: [])
      paths = [path, *sidecars]
      existing = paths.find { |candidate| File.exist?(candidate) }
      raise Error, "refusing to overwrite #{existing}; use --force" if existing && !@options[:force]

      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
    end

    def fail_usage(message)
      @err.puts("retouch: #{message}")
      @err.puts("Run 'retouch --help' for usage.")
      2
    end

    def help(operation = nil)
      if operation
        details = {
          "resize" => "retouch INPUT resize GEOMETRY [--filter nearest|bilinear|bicubic|lanczos3] [--gravity POSITION] -o OUTPUT",
          "crop" => "retouch INPUT crop GEOMETRY [--gravity POSITION] -o OUTPUT",
          "rotate" => "retouch INPUT rotate DEGREES -o OUTPUT",
          "border" => "retouch INPUT border WIDTH [#RRGGBB] -o OUTPUT",
          "blur" => "retouch INPUT blur [--sigma VALUE] -o OUTPUT",
          "text" => "retouch INPUT text TEXT --font FONT [--at POSITION] [--size PX] -o OUTPUT",
          "montage" => "retouch INPUT... montage [--cols N] [--gap PX] [--label --font FONT] -o OUTPUT",
          "spritesheet" => "retouch INPUT... spritesheet [--cols N] [--gap PX] -o OUTPUT"
        }
        raise ArgumentError, "unknown operation help: #{operation}" unless OPERATIONS.include?(operation) || details.key?(operation)

        @out.puts(details.fetch(operation, "retouch INPUT #{operation} [OPTIONS] -o OUTPUT"))
        return 0
      end
      @out.puts <<~HELP
        Retouch edits PNG, PPM, and BMP images; optional integrations add GIF/APNG, text, and visual diffs.

        Usage: retouch INPUT... OPERATION [ARGUMENTS] -o OUTPUT
               retouch help OPERATION
               retouch info INPUT...
               retouch diff EXPECTED ACTUAL -o OUTPUT

        Operations: resize thumbnail crop rotate flip flop border trim grayscale invert
          brightness contrast gamma saturate tint opacity quantize blur sharpen pixelate
          overlay watermark text rect arrow montage append spritesheet animate

        Global options: -o, --output PATH  --force  --dry-run  --verbose  --quiet
                        --strip  --level 0..9  --jobs N  --frame N  -h, --help
      HELP
      0
    end
  end
end
