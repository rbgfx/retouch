# frozen_string_literal: true

require "json"
require "optparse"

module Retouch
  class CLI
    OPERATIONS = %w[resize thumbnail crop flip flop rotate pad extend border trim].freeze

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
      @options = { level: 6 }
      read_global_options
      raise ArgumentError, "PNG level must be between 0 and 9" unless @options[:level].between?(0, 9)
    end

    def run
      return help if @options[:help] || @args.empty?
      return info_command if @args.first == "info"
      return help(@args[1]) if @args.first == "help"

      operation_at = @args.index { |token| OPERATIONS.include?(token) }
      return fail_usage("missing operation") unless operation_at

      inputs = @args.shift(operation_at)
      return fail_usage("exactly one input file is required") unless inputs.one?
      return fail_usage("an output path with -o is required") unless @options[:output]

      input = inputs.first
      operations = parse_operations(@args)
      return announce("retouch #{input} #{operations.map(&:first).join(" ")} -o #{@options[:output]}") if @options[:dry_run]
      raise Error, "input file does not exist: #{input}" unless File.file?(input)
      raise Error, "refusing to overwrite #{@options[:output]}; use --force" if File.exist?(@options[:output]) && !@options[:force]

      FileUtils.mkdir_p(File.dirname(@options[:output])) unless File.dirname(@options[:output]) == "."
      pipeline = operations.reduce(Retouch.open(input)) do |current, (name, args, options)|
        announce("applying #{name}") if @options[:verbose]
        current.public_send(name, *args, **options)
      end
      pipeline.save(@options[:output], level: @options[:level], strip: @options[:strip])
      announce(@options[:output])
      0
    rescue ArgumentError, OptionParser::ParseError
      raise
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
        when "--level" then @options[:level] = Integer(require_value(token))
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
                        when "resize", "thumbnail", "crop" then [[required(tokens, "geometry")], read_options(tokens, filter: :symbol, gravity: :symbol)]
                        when "rotate" then [[required(tokens, name)], read_options(tokens, background: :string)]
                        when "pad" then [[required(tokens, name)], read_options(tokens, color: :string)]
                        when "extend" then [[required(tokens, name), required(tokens, name)], read_options(tokens, color: :string, gravity: :symbol)]
                        when "border" then [[required(tokens, name), tokens.first&.start_with?("#") ? tokens.shift : "#000000"], {}]
                        when "trim" then [[], read_options(tokens, fuzz: :integer, color: :string)]
                        when "flip", "flop" then [[], {}]
                        end
        operations << [name, args, options]
      end
      operations
    end

    def read_options(tokens, specification)
      options = {}
      while tokens.first&.start_with?("--")
        option = tokens.shift.delete_prefix("--").tr("-", "_").to_sym
        type = specification[option]
        raise OptionParser::InvalidOption, "--#{option}" unless type

        value = required(tokens, option)
        options[option] = case type
                          when :integer then Integer(value)
                          when :symbol then value.tr("-", "_").to_sym
                          else value
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
      @args.shift
      return fail_usage("info expects one input file") unless @args.one?

      path = @args.first
      announce(JSON.pretty_generate({ path:, **Operations.info(ImageIO.read(path)) }))
      0
    rescue StandardError => e
      @err.puts("retouch: #{e.message}")
      1
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

        @out.puts("retouch INPUT #{operation} [ARGUMENTS] -o OUTPUT")
        return 0
      end
      @out.puts <<~HELP
        Retouch resizes and reshapes PNG, PPM, and BMP images.

        Usage: retouch INPUT OPERATION [ARGUMENTS] -o OUTPUT
               retouch help OPERATION
               retouch info INPUT

        Operations: resize thumbnail crop rotate flip flop pad extend border trim
        Options: -o, --output PATH  --force  --dry-run  --verbose  --quiet
                 --strip  --level 0..9  -h, --help
      HELP
      0
    end
  end
end
