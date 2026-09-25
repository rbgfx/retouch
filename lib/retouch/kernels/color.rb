# frozen_string_literal: true

module Retouch
  module Kernels
    module_function

    def quantize(image, colors: 256, dither: :none, palette: nil)
      indices, palette = Tessel::Quantize.quantize(image, colors: Integer(colors), dither: dither.to_sym, palette:)
      source = image.bytes
      output = String.new(capacity: source.bytesize, encoding: Encoding::BINARY)
      (image.width * image.height).times do |index|
        red, green, blue = palette.fetch(indices.getbyte(index))
        output << red << green << blue << source.getbyte((index * 4) + 3)
      end
      Tessel::Image.from_rgba(image.width, image.height, output, metadata: image.metadata)
    end
  end
end
