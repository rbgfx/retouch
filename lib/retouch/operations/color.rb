# frozen_string_literal: true

module Retouch
  module Operations
    module_function

    %i[grayscale invert brightness contrast gamma saturate opacity].each do |operation|
      define_method(operation) do |image, value = nil|
        Kernels::LUT.apply(image, operation, value)
      end
    end

    def tint(image, color, amount: 1.0)
      Kernels::LUT.apply(image, :tint, color, amount: Float(amount))
    end

    def quantize(image, colors: 256, dither: :none, palette: nil)
      Kernels.quantize(image, colors:, dither:, palette:)
    end
  end
end
