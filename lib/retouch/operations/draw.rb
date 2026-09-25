# frozen_string_literal: true

module Retouch
  module Operations
    module_function

    BLENDS = %i[normal multiply screen overlay darken lighten add].freeze

    def overlay(image, source, x: nil, y: nil, gravity: :center, opacity: 1.0, mode: :normal)
      source = ImageIO.read(source) unless source.is_a?(Tessel::Image)
      opacity = Float(opacity)
      mode = mode.to_sym
      raise ArgumentError, "opacity must be between 0 and 1" unless opacity.finite? && opacity.between?(0, 1)
      raise ArgumentError, "unknown blend mode: #{mode}" unless BLENDS.include?(mode)

      offset_x, offset_y = Gravity.offset(image.width, image.height, source.width, source.height, gravity)
      offset_x = Integer(x) unless x.nil?
      offset_y = Integer(y) unless y.nil?
      output = image.dup
      source.height.times do |source_y|
        source.width.times do |source_x|
          target_x = source_x + offset_x
          target_y = source_y + offset_y
          next unless target_x.between?(0, image.width - 1) && target_y.between?(0, image.height - 1)

          source_pixel = source[source_x, source_y]
          source_pixel[3] = (source_pixel[3] * opacity).round
          next if source_pixel[3].zero?

          output[target_x, target_y] = blend_pixel(output[target_x, target_y], source_pixel, mode)
        end
      end
      output
    end

    def watermark(image, source, **options)
      overlay(image, source, **options)
    end

    def rect(image, x, y, width, height, color = "#ffffff", fill: false)
      x = Integer(x)
      y = Integer(y)
      width = Integer(width)
      height = Integer(height)
      raise ArgumentError, "rectangle dimensions must be positive" unless width.positive? && height.positive?

      output = image.dup
      if fill
        output.fill_rect(x, y, width, height, color, blend: :alpha)
      else
        output.fill_rect(x, y, width, 1, color, blend: :alpha)
        output.fill_rect(x, y + height - 1, width, 1, color, blend: :alpha)
        output.fill_rect(x, y, 1, height, color, blend: :alpha)
        output.fill_rect(x + width - 1, y, 1, height, color, blend: :alpha)
      end
      output
    end

    def arrow(image, x1, y1, x2, y2, color = "#ffffff", width: 1, head: 8)
      x1, y1, x2, y2 = [x1, y1, x2, y2].map { |value| Integer(value) }
      width = Integer(width)
      head = Float(head)
      raise ArgumentError, "arrow width must be positive" unless width.positive?
      raise ArgumentError, "arrow head length must be non-negative and finite" unless head.finite? && head >= 0

      output = image.dup
      draw_line(output, x1, y1, x2, y2, color, width)
      distance = Math.hypot(x2 - x1, y2 - y1)
      if head.positive? && distance.positive?
        angle = Math.atan2(y2 - y1, x2 - x1)
        [angle + (0.65 * Math::PI), angle - (0.65 * Math::PI)].each do |side|
          draw_line(output, x2, y2, (x2 + (Math.cos(side) * head)).round, (y2 + (Math.sin(side) * head)).round, color, width)
        end
      end
      output
    end

    def text(image, string, x: 0, y: 0, at: nil, size: 16, font: nil, color: "#ffffff", background: nil, padding: 4)
      begin
        require "glyphic"
      rescue LoadError => e
        raise Error, "text requires the glyphic gem (gem install glyphic)", cause: e
      end
      size = Integer(size)
      raise ArgumentError, "font size must be positive" unless size.positive?

      font_object = font ? Glyphic.load(font, size: Integer(size)) : Glyphic.default
      rendered = font_object.render(String(string), color: Tessel::Color.pack(color).bytes)
      if !font && size != font_object.line_height
        scale = size.to_f / font_object.line_height
        rendered = rendered.scale_nearest([(rendered.width * scale).round, 1].max, [(rendered.height * scale).round, 1].max)
      end
      text_width = rendered.width
      text_height = rendered.height
      padding = Integer(padding)
      raise ArgumentError, "text padding must not be negative" if padding.negative?

      if at
        x, y = Gravity.offset(image.width, image.height, text_width + (padding * 2), text_height + (padding * 2), at)
        x += padding
        y += padding
      else
        x = Integer(x)
        y = Integer(y)
      end
      output = image.dup
      output.fill_rect(x - padding, y - padding, text_width + (padding * 2), text_height + (padding * 2), background, blend: :alpha) if background
      output.blit(rendered, x, y)
      output
    end

    def blend_pixel(destination, source, mode)
      source_alpha = source[3] / 255.0
      destination_alpha = destination[3] / 255.0
      output_alpha = source_alpha + (destination_alpha * (1 - source_alpha))
      return [0, 0, 0, 0] if output_alpha.zero?

      rgb = 3.times.map do |channel|
        source_color = source[channel] / 255.0
        destination_color = destination[channel] / 255.0
        blended = case mode
                  when :normal then source_color
                  when :multiply then source_color * destination_color
                  when :screen then 1 - ((1 - source_color) * (1 - destination_color))
                  when :overlay then destination_color <= 0.5 ? 2 * source_color * destination_color : 1 - (2 * (1 - source_color) * (1 - destination_color))
                  when :darken then [source_color, destination_color].min
                  when :lighten then [source_color, destination_color].max
                  when :add then [source_color + destination_color, 1].min
                  end
        premultiplied = ((1 - source_alpha) * destination_alpha * destination_color) + ((1 - destination_alpha) * source_alpha * source_color) + (source_alpha * destination_alpha * blended)
        (premultiplied / output_alpha * 255).round.clamp(0, 255)
      end
      [*rgb, (output_alpha * 255).round.clamp(0, 255)]
    end
    private_class_method :blend_pixel

    def draw_line(image, x1, y1, x2, y2, color, width)
      dx = (x2 - x1).abs
      sx = x1 < x2 ? 1 : -1
      dy = -(y2 - y1).abs
      sy = y1 < y2 ? 1 : -1
      error = dx + dy
      loop do
        image.fill_rect(x1 - (width / 2), y1 - (width / 2), width, width, color, blend: :alpha)
        break if x1 == x2 && y1 == y2

        doubled = 2 * error
        if doubled >= dy
          error += dy
          x1 += sx
        end
        if doubled <= dx
          error += dx
          y1 += sy
        end
      end
    end
    private_class_method :draw_line
  end
end
