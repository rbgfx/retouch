# frozen_string_literal: true

module Retouch
  module ImageIO
    module_function

    def read(path, frame: 0)
      frame = Integer(frame)
      raise ArgumentError, "frame must not be negative" if frame.negative?

      signature = File.binread(path, 8)
      if signature.start_with?("GIF87a", "GIF89a")
        require_optional("flipbook", "GIF input") { require "flipbook" }
        frames = Flipbook.read(path)
        image = frames.fetch(frame) { raise ArgumentError, "GIF frame is out of range: #{frame}" }
        return with_format(image, "GIF")
      end
      format = if signature.start_with?(Tessel::SIGNATURE)
                 "PNG"
               elsif signature.start_with?("P3", "P6")
                 "PPM"
               elsif signature.start_with?("BM")
                 "BMP"
               end
      with_format(Tessel.read(path), format || "unknown")
    rescue Tessel::UnsupportedError => e
      raise Error, "unsupported image format for #{path}: #{e.message}", cause: e
    end

    def write(image, path, level: 6, strip: false)
      raise TypeError, "image must be a Tessel::Image" unless image.is_a?(Tessel::Image)

      image = Tessel::Image.from_rgba(image.width, image.height, image.bytes) if strip
      extension = File.extname(path).downcase
      case extension
      when ".gif", ".apng"
        require_optional("flipbook", "GIF/APNG output") { require "flipbook" }
        Flipbook.write(path, [image], format: extension.delete_prefix("."), colors: 256)
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

    def require_optional(gem, feature)
      yield
    rescue LoadError => e
      raise Error, "#{feature} requires the #{gem} gem", cause: e
    end

    def with_format(image, format)
      metadata = image.metadata.merge("format" => format)
      Tessel::Image.from_rgba(image.width, image.height, image.bytes, metadata:)
    end
  end
end
