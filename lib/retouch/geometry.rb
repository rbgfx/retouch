# frozen_string_literal: true

module Retouch
  class Geometry
    attr_reader :width, :height, :offset_x, :offset_y, :mode

    def self.parse(value)
      text = String(value)
      match = /\A(?:(?<width>\d+(?:\.\d+)?%?)?x(?<height>\d+(?:\.\d+)?%?)?|(?<single>\d+(?:\.\d+)?%))(?<mode>[!^>])?(?<x>[+-]\d+)?(?<y>[+-]\d+)?\z/.match(text)
      raise ArgumentError, "invalid geometry: #{text}" unless match

      width = match[:width] || match[:single]
      height = match[:height] || match[:single]
      raise ArgumentError, "geometry needs at least one dimension" unless width || height

      mode = { "!" => :stretch, "^" => :cover, ">" => :shrink }.fetch(match[:mode], :fit)
      raise ArgumentError, "geometry needs both offsets" if match[:x].nil? != match[:y].nil?

      new(width && dimension(width), height && dimension(height), (match[:x] || 0).to_i, (match[:y] || 0).to_i, mode)
    end

    def self.dimension(value)
      number = Float(value.delete_suffix("%"), exception: false)
      raise ArgumentError, "geometry dimensions must be positive" unless number&.positive?

      value.end_with?("%") ? number / 100.0 : number.round
    end
    private_class_method :dimension

    def initialize(width, height, offset_x, offset_y, mode)
      @width = width
      @height = height
      @offset_x = offset_x
      @offset_y = offset_y
      @mode = mode
    end

    def crop_size(source_width, source_height)
      raise ArgumentError, "crop geometry needs both dimensions" unless width && height

      [scaled_dimension(source_width, width), scaled_dimension(source_height, height)]
    end

    def target_size(source_width, source_height)
      width_ratio = width.is_a?(Float) ? width : nil
      height_ratio = height.is_a?(Float) ? height : nil
      target_width = width_ratio ? source_width * width_ratio : width
      target_height = height_ratio ? source_height * height_ratio : height
      return [scaled_dimension(source_width, width_ratio), scaled_dimension(source_height, height_ratio)] if width_ratio && height_ratio
      return [scaled_dimension(source_width, target_width), scaled_dimension(source_height, target_height)] if mode == :stretch && target_width && target_height

      scale = if target_width && target_height
                horizontal = target_width.to_f / source_width
                vertical = target_height.to_f / source_height
                mode == :cover ? [horizontal, vertical].max : [horizontal, vertical].min
              elsif target_width
                target_width.to_f / source_width
              elsif target_height
                target_height.to_f / source_height
              else
                1.0
              end
      scale = [scale, 1.0].min if mode == :shrink
      [(source_width * scale).round.clamp(1, 1_000_000), (source_height * scale).round.clamp(1, 1_000_000)]
    end

    private

    def scaled_dimension(source, value)
      (value.is_a?(Float) ? source * value : value).round.clamp(1, 1_000_000)
    end
  end
end
