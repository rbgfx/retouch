# frozen_string_literal: true

require "json"
require "optparse"

module Retouch
  class CLI
    OPERATIONS = %w[
      resize thumbnail crop flip flop rotate pad extend border trim
      grayscale invert brightness contrast gamma saturate tint opacity quantize
      blur sharpen pixelate overlay watermark text rect arrow
      montage append spritesheet animate diff
    ].freeze
    MULTI_IMAGE_OPERATIONS = %w[montage append spritesheet animate diff].freeze
    OPERATION_USAGE = {
      "resize" => "GEOMETRY [--filter nearest|bilinear|bicubic|lanczos3] [--gravity POSITION]",
      "thumbnail" => "GEOMETRY [--filter FILTER]",
      "crop" => "GEOMETRY [--gravity POSITION]",
      "rotate" => "DEGREES [--background COLOR]",
      "pad" => "PIXELS [--color COLOR]",
      "extend" => "WIDTH HEIGHT [--color COLOR] [--gravity POSITION]",
      "border" => "PIXELS [COLOR]",
      "trim" => "[--color COLOR] [--fuzz 0..255]",
      "brightness" => "-255..255",
      "contrast" => "FACTOR",
      "gamma" => "GAMMA",
      "saturate" => "FACTOR",
      "tint" => "COLOR [--amount 0..1]",
      "opacity" => "0..1",
      "quantize" => "[--colors 2..256] [--dither none|ordered|floyd-steinberg]",
      "blur" => "SIGMA",
      "sharpen" => "SIGMA [--amount FACTOR]",
      "pixelate" => "BLOCK_SIZE",
      "overlay" => "IMAGE [--x X] [--y Y] [--gravity POSITION] [--opacity 0..1] [--mode MODE]",
      "watermark" => "IMAGE [composite options]",
      "text" => "TEXT [--at POSITION] [--size PIXELS] [--font FILE] [--background COLOR]",
      "rect" => "X Y WIDTH HEIGHT [COLOR] [--fill]",
      "arrow" => "X1 Y1 X2 Y2 [COLOR] [--width PIXELS] [--head PIXELS]",
      "montage" => "[--cols N] [--gap PIXELS] [--background COLOR] [--label]",
      "append" => "[--direction vertical|horizontal] [--gap PIXELS]",
      "spritesheet" => "[--max-width PIXELS] [--gap PIXELS]",
      "animate" => "(--fps RATE | --delay SECONDS) [--no-loop]",
      "diff" => "[--threshold 0..255] [--color COLOR]"
    }.freeze

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
      @options = { level: 6, jobs: 1, loop: true }
      read_global_options
      raise ArgumentError, "PNG level must be between 0 and 9" unless @options[:level].between?(0, 9)
      raise ArgumentError, "jobs must be positive" unless @options[:jobs].positive?
    end

    def run
      return help if @options[:help] || @args.empty?
      return info_command if @args.first == "info"
      return help(@args[1]) if @args.first == "help"

      operation_at = @args.index { |token| OPERATIONS.include?(token) }
      return fail_usage("missing operation") unless operation_at

      inputs = @args.shift(operation_at)
      return fail_usage("at least one input file is required") if inputs.empty?
      return fail_usage("an output path with -o is required") unless @options[:output]

      operation = @args.first
      parsed = parse_cli_operations(@args)
      return 2 unless parsed

      if MULTI_IMAGE_OPERATIONS.include?(operation)
        return fail_usage("#{operation} must be the only operation in its command") unless parsed.one?

        multi_image_command(inputs, operation, parsed.fetch(0))
      else
        image_command(inputs, parsed)
      end
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
        when "--loop" then @options[:loop] = true
        when "--no-loop" then @options[:loop] = false
        when "--level" then @options[:level] = Integer(require_value(token))
        when "--jobs" then @options[:jobs] = Integer(require_value(token))
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

    def parse_operations(tokens)
      operations = []
      until tokens.empty?
        name = tokens.shift
        raise ArgumentError, "unknown operation: #{name}" unless OPERATIONS.include?(name)

        args, options = case name
                        when "resize", "thumbnail", "crop"
                          [[required(tokens, "geometry")], read_options(tokens, filter: :symbol, gravity: :symbol)]
                        when "rotate" then [[Float(required(tokens, name))], read_options(tokens, background: :color)]
                        when "pad" then [[Integer(required(tokens, name))], read_options(tokens, color: :color)]
                        when "extend" then [[Integer(required(tokens, name)), Integer(required(tokens, name))], read_options(tokens, color: :color, gravity: :symbol)]
                        when "border" then [[Integer(required(tokens, name)), tokens.first&.start_with?("#") ? tokens.shift : "#000000"], {}]
                        when "trim" then [[], read_options(tokens, fuzz: :integer, color: :color)]
                        when "brightness", "contrast", "gamma", "saturate", "opacity" then [[Float(required(tokens, name))], {}]
                        when "tint" then [[required(tokens, "color")], read_options(tokens, amount: :float)]
                        when "quantize" then [[], read_options(tokens, colors: :integer, dither: :symbol)]
                        when "blur", "sharpen" then [[Float(required(tokens, name))], read_options(tokens, amount: :float)]
                        when "pixelate" then [[Integer(required(tokens, name))], {}]
                        when "overlay", "watermark"
                          [[ImageIO.read(required(tokens, "overlay image"))], read_options(tokens, x: :integer, y: :integer, gravity: :symbol, opacity: :float, mode: :symbol)]
                        when "text"
                          [[required(tokens, "text")], read_options(tokens, x: :integer, y: :integer, at: :symbol, size: :integer, font: :string, color: :color, background: :color, padding: :integer)]
                        when "rect"
                          [[Integer(required(tokens, "x")), Integer(required(tokens, "y")), Integer(required(tokens, "width")), Integer(required(tokens, "height")), tokens.first&.start_with?("#") ? tokens.shift : "#ffffff"], read_options(tokens, fill: :flag)]
                        when "arrow"
                          [[Integer(required(tokens, "x1")), Integer(required(tokens, "y1")), Integer(required(tokens, "x2")), Integer(required(tokens, "y2")), tokens.first&.start_with?("#") ? tokens.shift : "#ffffff"], read_options(tokens, width: :integer, head: :float)]
                        when "montage" then [[], read_options(tokens, cols: :integer, gap: :integer, background: :color, label: :flag)]
                        when "append" then [[], read_options(tokens, direction: :symbol, gap: :integer, background: :color)]
                        when "spritesheet" then [[], read_options(tokens, max_width: :integer, gap: :integer, background: :color)]
                        when "animate"
                          options = read_options(tokens, fps: :float, delay: :float, colors: :integer, dither: :symbol)
                          raise OptionParser::InvalidArgument, "use either --fps or --delay" if options.key?(:fps) && options.key?(:delay)
                          raise OptionParser::MissingArgument, "--fps or --delay" unless options.key?(:fps) || options.key?(:delay)

                          [[], options]
                        when "diff" then [[], read_options(tokens, threshold: :float, color: :color)]
                        when "grayscale", "invert", "flip", "flop" then [[], {}]
                        end
        operations << [name, args, options]
      end
      operations
    end

    def parse_cli_operations(tokens)
      parse_operations(tokens)
    rescue ArgumentError, OptionParser::ParseError => e
      @err.puts("retouch: #{e.message}")
      nil
    end

    def read_options(tokens, specification)
      options = {}
      while tokens.first&.start_with?("--")
        option = tokens.shift.delete_prefix("--").tr("-", "_").to_sym
        type = specification[option]
        raise OptionParser::InvalidOption, "--#{option}" unless type

        options[option] = if type == :flag
                            true
                          else
                            value = required(tokens, option)
                            case type
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

    def image_command(inputs, operations)
      expanded = expand_inputs(inputs)
      return fail_usage("no input files matched") if expanded.empty?

      batch = expanded.length > 1 || inputs.any? { |input| input.match?(/[?*{\[]/) } || @options[:output].include?("{")
      if batch
        return fail_usage("batch output must use a template such as {name}") if expanded.length > 1 && !@options[:output].include?("{")

        outputs = Batch.run(expanded, to: @options[:output], jobs: @options[:jobs], force: @options[:force], dry_run: @options[:dry_run]) do |input, output|
          apply_operations(Retouch.open(input), operations).save(output, level: @options[:level], strip: @options[:strip])
        end
        outputs.each { |path| announce(path) } if @options[:dry_run] || !@options[:quiet]
        return 0
      end

      output = @options[:output]
      return announce("retouch #{expanded.first} #{operations.map(&:first).join(" ")} -o #{output}") if @options[:dry_run]
      raise Error, "input file does not exist: #{expanded.first}" unless File.file?(expanded.first)
      raise Error, "refusing to overwrite #{output}; use --force" if File.exist?(output) && !@options[:force]

      result = apply_operations(Retouch.open(expanded.first), operations)
      FileUtils.mkdir_p(File.dirname(output)) unless File.dirname(output) == "."
      result.save(output, level: @options[:level], strip: @options[:strip])
      announce(output)
    end

    def multi_image_command(inputs, name, (_operation, _arguments, options))
      paths = expand_inputs(inputs)
      return fail_usage("no input files matched") if paths.empty?
      return fail_usage("#{name} expects at least two images") if paths.length < 2
      return fail_usage("diff expects exactly two images") if name == "diff" && paths.length != 2

      output = @options[:output]
      manifest = spritesheet_manifest_path(output) if name == "spritesheet"
      outputs = name == "spritesheet" ? [output, manifest] : [output]
      return announce("retouch #{paths.join(" ")} #{name} -o #{output}") if @options[:dry_run]
      if !@options[:force] && (existing = outputs.find { |path| File.exist?(path) })
        raise Error, "refusing to overwrite #{existing}; use --force"
      end

      FileUtils.mkdir_p(File.dirname(output)) unless File.dirname(output) == "."
      images = paths.map { |path| ImageIO.read(path) }
      case name
      when "montage"
        options[:labels] = paths.map { |path| File.basename(path) } if options.delete(:label)
        Operations.montage(images, **options).then { |image| ImageIO.write(image, output, level: @options[:level], strip: @options[:strip]) }
      when "append"
        Operations.append(images, **options).then { |image| ImageIO.write(image, output, level: @options[:level], strip: @options[:strip]) }
      when "spritesheet"
        image, placements = Operations.spritesheet(images, **options)
        ImageIO.write(image, output, level: @options[:level], strip: @options[:strip])
        File.write(manifest, JSON.pretty_generate(placements))
      when "animate"
        Operations.animate(images, output, **options, loop: @options[:loop])
      when "diff"
        result = Operations.diff(images[0], images[1], **options)
        ImageIO.write(result[:image], output, level: @options[:level], strip: @options[:strip])
        announce(format("%.2f%% pixels differ", result[:rate] * 100))
      end
      announce(output)
    end

    def apply_operations(pipeline, operations)
      operations.reduce(pipeline) do |current, (name, args, options)|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:verbose]
        result = current.public_send(name, *args, **options)
        if started
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          announce(format("%<operation>s %<elapsed>.3fs", operation: name, elapsed:))
        end
        result
      end
    end

    def expand_inputs(inputs)
      inputs.flat_map do |input|
        input.match?(/[?*{\[]/) ? Dir.glob(input) : input
      end
    end

    def spritesheet_manifest_path(output)
      File.extname(output).empty? ? "#{output}.json" : output.sub(%r{\.[^./]+\z}, ".json")
    end

    def info_command
      @args.shift
      return fail_usage("info expects one input file") unless @args.one?

      path = @args.first
      announce(JSON.pretty_generate({ path:, **Operations.info(ImageIO.read(path)) }))
    end

    def fail_usage(message)
      @err.puts("retouch: #{message}")
      @err.puts("Run 'retouch --help' for usage.")
      2
    end

    def announce(message)
      @out.puts(message) unless @options[:quiet]
      0
    end

    def help(operation = nil)
      if operation
        raise ArgumentError, "unknown operation help: #{operation}" unless OPERATIONS.include?(operation)

        @out.puts("retouch INPUTS #{operation} #{OPERATION_USAGE.fetch(operation, "")} -o OUTPUT")
        return 0
      end
      @out.puts <<~HELP
        Retouch edits PNG, PPM, and BMP images with a Ruby API and CLI.

        Usage: retouch INPUT [INPUT ...] OPERATION [ARGUMENTS] -o OUTPUT
               retouch info INPUT
               retouch help OPERATION

        Operations: #{OPERATIONS.join(" ")}
        Global: -o PATH --force --dry-run --verbose --quiet --strip --level 0..9 --jobs N --loop --no-loop
      HELP
      0
    end
  end
end
