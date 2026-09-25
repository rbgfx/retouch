# frozen_string_literal: true

module Retouch
  module ImageIO
    module_function

    def read(path)
      signature = File.binread(path, 8)
      format = if signature.start_with?(Tessel::SIGNATURE)
                 "PNG"
               elsif signature.start_with?("P3", "P6")
                 "PPM"
               elsif signature.start_with?("BM")
                 "BMP"
               elsif signature.start_with?("GIF87a", "GIF89a")
                 "GIF"
               end
      return with_format(Operations.open_gif(path, frame: 0), format) if format == "GIF"

      with_format(Tessel.read(path), format || "unknown")
    rescue Tessel::UnsupportedError => e
      raise Error, "unsupported image format for #{path}: #{e.message}", cause: e
    end

    def write(image, path, level: 6, strip: false)
      raise TypeError, "image must be a Tessel::Image" unless image.is_a?(Tessel::Image)

      image = Tessel::Image.from_rgba(image.width, image.height, image.bytes) if strip
      extension = File.extname(path).downcase
      case extension
      when ".png"
        image.write(path, level: Integer(level))
      when ".ppm", ".pnm"
        image.write(path, binary: true)
      when ".bmp"
        image.write(path)
      else
        raise Error, "unsupported output format: #{extension.empty? ? "(no extension)" : extension}"
      end
      path
    rescue ArgumentError, Tessel::Error => e
      raise Error, e.message, cause: e
    end

    def with_format(image, format)
      metadata = image.metadata.merge("format" => format)
      Tessel::Image.from_rgba(image.width, image.height, image.bytes, metadata:)
    end
  end
end
