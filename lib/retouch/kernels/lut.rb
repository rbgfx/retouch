# frozen_string_literal: true

module Retouch
  module Kernels
    module LUT
      module_function

      def apply(image, operation, value = nil, amount: 1.0)
        bytes = image.bytes.dup
        number = value.nil? || operation.to_sym == :tint ? nil : Float(value)
        raise ArgumentError, "value must be finite" if number && !number.finite?

        case operation.to_sym
        when :grayscale
          bytes.bytes.each_slice(4).with_index do |(red, green, blue, _alpha), index|
            gray = (((red * 2126) + (green * 7152) + (blue * 722)) / 10_000.0).round
            bytes.setbyte(index * 4, gray)
            bytes.setbyte((index * 4) + 1, gray)
            bytes.setbyte((index * 4) + 2, gray)
          end
        when :invert
          lut = Array.new(256) { |channel| 255 - channel }
          transform_rgb(bytes) { |channel| lut[channel] }
        when :brightness
          raise ArgumentError, "brightness must be between -255 and 255" unless number&.between?(-255, 255)

          lut = Array.new(256) { |channel| (channel + number).round.clamp(0, 255) }
          transform_rgb(bytes) { |channel| lut[channel] }
        when :contrast
          raise ArgumentError, "contrast must be between 0 and 10" unless number&.between?(0, 10)

          lut = Array.new(256) { |channel| (((channel - 127.5) * number) + 127.5).round.clamp(0, 255) }
          transform_rgb(bytes) { |channel| lut[channel] }
        when :gamma
          raise ArgumentError, "gamma must be positive and at most 10" unless number&.positive? && number <= 10

          lut = Array.new(256) { |channel| (255 * ((channel / 255.0)**(1.0 / number))).round }
          transform_rgb(bytes) { |channel| lut[channel] }
        when :saturate
          raise ArgumentError, "saturation must be between 0 and 10" unless number&.between?(0, 10)

          bytes.bytes.each_slice(4).with_index do |(red, green, blue, _alpha), index|
            gray = (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
            [red, green, blue].each_with_index do |channel, component|
              bytes.setbyte((index * 4) + component, (gray + ((channel - gray) * number)).round.clamp(0, 255))
            end
          end
        when :tint
          raise ArgumentError, "tint amount must be between 0 and 1" unless amount.is_a?(Numeric) && amount.finite? && amount.between?(0, 1)

          tint = Tessel::Color.pack(value).bytes.first(3)
          bytes.bytes.each_slice(4).with_index do |(red, green, blue, _alpha), index|
            [red, green, blue].each_with_index do |channel, component|
              bytes.setbyte((index * 4) + component, ((channel * (1 - amount)) + (tint[component] * amount)).round)
            end
          end
        when :opacity
          raise ArgumentError, "opacity must be between 0 and 1" unless number&.between?(0, 1)

          (3...bytes.bytesize).step(4) { |index| bytes.setbyte(index, (bytes.getbyte(index) * number).round) }
        else
          raise ArgumentError, "unknown LUT operation: #{operation}"
        end
        Tessel::Image.from_rgba(image.width, image.height, bytes, metadata: image.metadata)
      end

      def transform_rgb(bytes)
        bytes.bytesize.times do |index|
          bytes.setbyte(index, yield(bytes.getbyte(index))) if index % 4 != 3
        end
      end
      private_class_method :transform_rgb
    end
  end
end
