# frozen_string_literal: true

module Retouch
  module Operations
    module_function

    def blur(image, sigma)
      Kernels::Convolve.gaussian(image, sigma)
    end

    def sharpen(image, sigma, amount: 1.0)
      amount = Float(amount)
      raise ArgumentError, "sharpen amount must be between 0 and 10" unless amount.finite? && amount.between?(0, 10)

      blurred = blur(image, sigma)
      source = image.bytes
      smooth = blurred.bytes
      output = source.dup
      (0...(image.width * image.height)).each do |index|
        offset = index * 4
        original_alpha = source.getbyte(offset + 3) / 255.0
        smooth_alpha = smooth.getbyte(offset + 3) / 255.0
        3.times do |channel|
          original = source.getbyte(offset + channel) * original_alpha
          blurred_color = smooth.getbyte(offset + channel) * smooth_alpha
          sharpened = original + (amount * (original - blurred_color))
          color = original_alpha.positive? ? (sharpened / original_alpha).round.clamp(0, 255) : 0
          output.setbyte(offset + channel, color)
        end
      end
      Tessel::Image.from_rgba(image.width, image.height, output, metadata: image.metadata)
    end

    def pixelate(image, size)
      size = Integer(size)
      raise ArgumentError, "pixel size must be positive" unless size.positive?
      return image.dup if image.width.zero? || image.height.zero?

      output = image.dup
      (0...image.height).step(size) do |y|
        height = [size, image.height - y].min
        (0...image.width).step(size) do |x|
          width = [size, image.width - x].min
          alpha_sum = red = green = blue = 0.0
          (y...(y + height)).each do |py|
            (x...(x + width)).each do |px|
              color = image[px, py]
              alpha = color[3] / 255.0
              red += color[0] * alpha
              green += color[1] * alpha
              blue += color[2] * alpha
              alpha_sum += color[3]
            end
          end
          count = width * height
          alpha = (alpha_sum / count).round
          color = alpha_sum.positive? ? [(red * 255 / alpha_sum).round, (green * 255 / alpha_sum).round, (blue * 255 / alpha_sum).round, alpha] : [0, 0, 0, 0]
          output.fill_rect(x, y, width, height, color, blend: :copy)
        end
      end
      output
    end
  end
end
