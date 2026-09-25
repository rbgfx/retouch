# frozen_string_literal: true

module Retouch
  class Pipeline
    OPERATIONS = %i[resize thumbnail crop flip flop rotate pad extend border trim].freeze

    def initialize(image, operations = [])
      raise TypeError, "image must be a Tessel::Image" unless image.is_a?(Tessel::Image)

      @source = image.dup
      @operations = operations.freeze
    end

    def to_image
      @operations.reduce(@source.dup) do |image, (name, args, options)|
        args = args.dup
        Operations.apply(image, name, *args, **options)
      end
    end

    def info = Operations.info(to_image)

    def save(path, **options)
      ImageIO.write(to_image, String(path), **options)
    end

    def method_missing(name, *args, **options, &block)
      return super if block || !OPERATIONS.include?(name)

      self.class.new(@source, @operations + [[name, args, options]])
    end

    def respond_to_missing?(name, include_private = false)
      OPERATIONS.include?(name) || super
    end
  end
end
