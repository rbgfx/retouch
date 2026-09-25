# frozen_string_literal: true

module Retouch
  module Kernels
    module Convolve
      module_function

      def gaussian(image, sigma)
        sigma = Float(sigma)
        raise ArgumentError, "sigma must be positive and at most 100" unless sigma.finite? && sigma.positive? && sigma <= 100

        radius = (sigma * 3).ceil
        weights = (-radius..radius).map { |offset| Math.exp(-(offset * offset) / (2 * sigma * sigma)) }
        total = weights.sum
        weights.map! { |weight| weight / total }
        convolve_axis(convolve_axis(image, weights, horizontal: true), weights, horizontal: false)
      end

      def convolve_axis(image, weights, horizontal:)
        width = image.width
        height = image.height
        source = image.bytes
        output = String.new(capacity: source.bytesize, encoding: Encoding::BINARY)
        axis_length = horizontal ? width : height
        radius = weights.length / 2
        entries = Array.new(axis_length) do |position|
          weights.each_with_index.map do |weight, index|
            sample = (position + index - radius).clamp(0, axis_length - 1)
            [horizontal ? sample * 4 : sample * width * 4, weight]
          end
        end
        height.times do |y|
          width.times do |x|
            red = green = blue = alpha = 0.0
            base = horizontal ? y * width * 4 : x * 4
            entries[horizontal ? x : y].each do |sample_offset, weight|
              offset = base + sample_offset
              sample_alpha = source.getbyte(offset + 3) / 255.0
              red += source.getbyte(offset) * sample_alpha * weight
              green += source.getbyte(offset + 1) * sample_alpha * weight
              blue += source.getbyte(offset + 2) * sample_alpha * weight
              alpha += source.getbyte(offset + 3) * weight
            end
            alpha_byte = alpha.round.clamp(0, 255)
            if alpha_byte.positive?
              output << (red * 255 / alpha).round.clamp(0, 255)
              output << (green * 255 / alpha).round.clamp(0, 255)
              output << (blue * 255 / alpha).round.clamp(0, 255)
            else
              output << "\0\0\0".b
            end
            output << alpha_byte
          end
        end
        Tessel::Image.from_rgba(width, height, output, metadata: image.metadata)
      end
      private_class_method :convolve_axis
    end
  end
end
