# frozen_string_literal: true

module Retouch
  module Operations
    module_function

    def apply(image, name, *arguments, **options)
      raise TypeError, "image must be a Tessel::Image" unless image.is_a?(Tessel::Image)

      method = name.to_sym
      raise ArgumentError, "unknown operation: #{name}" unless respond_to?(method)

      public_send(method, image, *arguments, **options)
    end

    def info(image)
      colors = {}
      alpha = false
      image.bytes.bytes.each_slice(4) do |r, g, b, a|
        colors[[r, g, b, a]] = true
        alpha ||= a < 255
      end
      { width: image.width, height: image.height, format: image.metadata.fetch("format", "RGBA"), colors: colors.length,
        alpha: alpha, metadata: image.metadata.dup }
    end

    def resize(image, geometry, filter: :lanczos3, gravity: :center)
      geometry = Geometry.parse(geometry) unless geometry.is_a?(Geometry)
      width, height = geometry.target_size(image.width, image.height)
      output = resample(image, width, height, filter)
      if geometry.mode == :cover && geometry.width && geometry.height
        crop_width, crop_height = geometry.crop_size(image.width, image.height)
        x, y = Gravity.offset(output.width, output.height, crop_width, crop_height, gravity)
        x = geometry.offset_x unless geometry.offset_x.zero?
        y = geometry.offset_y unless geometry.offset_y.zero?
        output = output.crop(x.clamp(0, [output.width - crop_width, 0].max), y.clamp(0, [output.height - crop_height, 0].max), crop_width, crop_height)
      end
      output
    end

    def thumbnail(image, geometry, **options)
      result = resize(image, geometry, **options)
      Tessel::Image.from_rgba(result.width, result.height, result.bytes)
    end

    def crop(image, geometry, gravity: :north_west, **_options)
      geometry = Geometry.parse(geometry) unless geometry.is_a?(Geometry)
      width, height = geometry.crop_size(image.width, image.height)
      x, y = if geometry.offset_x.zero? && geometry.offset_y.zero?
               Gravity.offset(image.width, image.height, width, height, gravity)
             else
               [geometry.offset_x, geometry.offset_y]
             end
      copy_metadata(image.crop(x, y, width, height), image)
    end

    def flip(image) = image.flip_vertical

    def flop(image)
      output = Tessel::Image.new(image.width, image.height, metadata: image.metadata)
      image.height.times do |y|
        image.width.times { |x| output[image.width - x - 1, y] = image[x, y] }
      end
      output
    end

    def rotate(image, degrees, background: [0, 0, 0, 0])
      angle = Float(degrees) % 360
      raise ArgumentError, "degrees must be finite" unless angle.finite?

      return image.dup if angle.zero?
      return rotate_quarter(image, 1) if angle == 90
      return rotate_quarter(image, 2) if angle == 180
      return rotate_quarter(image, 3) if angle == 270

      radians = angle * Math::PI / 180
      cosine = Math.cos(radians)
      sine = Math.sin(radians)
      width = ((image.width * cosine.abs) + (image.height * sine.abs)).ceil
      height = ((image.width * sine.abs) + (image.height * cosine.abs)).ceil
      output = Tessel::Image.new(width, height, fill: background, metadata: image.metadata)
      source_cx = (image.width - 1) / 2.0
      source_cy = (image.height - 1) / 2.0
      target_cx = (width - 1) / 2.0
      target_cy = (height - 1) / 2.0
      height.times do |y|
        width.times do |x|
          dx = x - target_cx
          dy = y - target_cy
          sx = (cosine * dx) + (sine * dy) + source_cx
          sy = (-sine * dx) + (cosine * dy) + source_cy
          output[x, y] = sample_bilinear(image, sx, sy, background) if sx.between?(0, image.width - 1) && sy >= 0 && sy <= image.height - 1
        end
      end
      output
    end

    def pad(image, amount, color: [0, 0, 0, 0])
      amount = Integer(amount)
      raise ArgumentError, "padding must not be negative" if amount.negative?

      extend(image, image.width + (2 * amount), image.height + (2 * amount), color:, gravity: :center)
    end

    def extend(image, width, height, color: [0, 0, 0, 0], gravity: :center)
      width = Integer(width)
      height = Integer(height)
      raise ArgumentError, "canvas dimensions must be positive" unless width.positive? && height.positive?
      raise ArgumentError, "canvas cannot be smaller than image" if width < image.width || height < image.height

      x, y = Gravity.offset(width, height, image.width, image.height, gravity)
      Tessel::Image.new(width, height, fill: color, metadata: image.metadata).tap { |canvas| canvas.blit(image, x, y) }
    end

    def border(image, width, color = "#000000", **_options)
      width = Integer(width)
      raise ArgumentError, "border width must be positive" unless width.positive?

      pad(image, width, color:)
    end

    def trim(image, color: nil, fuzz: 0)
      fuzz = Integer(fuzz)
      raise ArgumentError, "fuzz must be between 0 and 255" unless fuzz.between?(0, 255)

      target = Tessel::Color.pack(color || image[0, 0] || [0, 0, 0, 0]).bytes
      bounds = [image.width, image.height, -1, -1]
      image.height.times do |y|
        image.width.times do |x|
          pixel = image[x, y]
          next if pixel.zip(target).all? { |a, b| (a - b).abs <= fuzz }

          bounds[0] = [bounds[0], x].min
          bounds[1] = [bounds[1], y].min
          bounds[2] = [bounds[2], x].max
          bounds[3] = [bounds[3], y].max
        end
      end
      return image.dup if bounds[2].negative?

      copy_metadata(image.crop(bounds[0], bounds[1], bounds[2] - bounds[0] + 1, bounds[3] - bounds[1] + 1), image)
    end

    def grayscale(image)
      map_rgb(image) do |r, g, b|
        v = ((0.2126 * r) + (0.7152 * g) + (0.0722 * b)).round
        [v, v, v]
      end
    end

    def invert(image) = map_lut(image, (0..255).map { |value| 255 - value })

    def brightness(image, amount)
      offset = Float(amount)
      offset *= 255 if offset.abs <= 1
      map_lut(image, (0..255).map { |value| (value + offset).round.clamp(0, 255) })
    end

    def contrast(image, amount)
      factor = Float(amount)
      factor = (1.0 + factor) if factor.abs <= 1
      map_lut(image, (0..255).map { |value| (((value - 127.5) * factor) + 127.5).round.clamp(0, 255) })
    end

    def gamma(image, value)
      gamma = Float(value)
      raise ArgumentError, "gamma must be positive" unless gamma.positive?

      lut = (0..255).map { |v| (255 * ((v / 255.0)**(1.0 / gamma))).round }
      map_lut(image, lut)
    end

    def saturate(image, amount)
      factor = Float(amount)
      map_rgb(image) do |r, g, b|
        gray = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        [r, g, b].map { |v| (gray + ((v - gray) * factor)).round.clamp(0, 255) }
      end
    end

    def tint(image, color, amount: 0.5)
      tint = Tessel::Color.pack(color).bytes
      amount = Float(amount)
      raise ArgumentError, "tint amount must be between 0 and 1" unless amount.between?(0, 1)

      map_rgb(image) { |r, g, b| [r, g, b].zip(tint.first(3)).map { |a, c| ((a * (1 - amount)) + (c * amount)).round } }
    end

    def opacity(image, amount)
      factor = Float(amount)
      factor /= 100 if factor > 1
      raise ArgumentError, "opacity must be between 0 and 1 (or 0 and 100)" unless factor.between?(0, 1)

      map_rgba(image) { |r, g, b, a| [r, g, b, (a * factor).round] }
    end

    def quantize(image, colors: 256, dither: :none)
      indices, palette = Tessel::Quantize.quantize(image, colors: Integer(colors), dither: dither.to_sym)
      bytes = image.bytes
      output = Tessel::Image.new(image.width, image.height, metadata: image.metadata)
      indices.bytes.each_with_index do |index, pixel|
        r, g, b = palette[index]
        output[pixel % image.width, pixel / image.width] = [r, g, b, bytes.getbyte((pixel * 4) + 3)]
      end
      output
    end

    def blur(image, sigma: 1.0)
      sigma = Float(sigma)
      raise ArgumentError, "sigma must be positive and at most 100" unless sigma.positive? && sigma <= 100

      radius = (sigma * 3).ceil
      weights = (-radius..radius).map { |n| Math.exp(-(n * n) / (2 * sigma * sigma)) }
      total = weights.sum
      weights.map! { |weight| weight / total }
      convolve(convolve(image, weights, horizontal: true), weights, horizontal: false)
    end

    def sharpen(image, amount: 1.0, sigma: 1.0)
      blurred = blur(image, sigma:)
      original = image.bytes
      soft = blurred.bytes
      result = String.new(capacity: original.bytesize, encoding: Encoding::BINARY)
      original.bytesize.times do |i|
        result << (i % 4 == 3 ? original.getbyte(i) : (original.getbyte(i) + (Float(amount) * (original.getbyte(i) - soft.getbyte(i)))).round.clamp(0, 255))
      end
      Tessel::Image.from_rgba(image.width, image.height, result, metadata: image.metadata)
    end

    def pixelate(image, size)
      size = Integer(size)
      raise ArgumentError, "pixel size must be positive" unless size.positive?

      output = image.dup
      (0...image.height).step(size) do |y|
        (0...image.width).step(size) do |x|
          sw = [size, image.width - x].min
          sh = [size, image.height - y].min
          sums = [0.0, 0.0, 0.0, 0.0]
          (y...(y + sh)).each do |row|
            (x...(x + sw)).each do |col|
              red, green, blue, alpha = image[col, row]
              sums[0] += red * alpha / 255.0
              sums[1] += green * alpha / 255.0
              sums[2] += blue * alpha / 255.0
              sums[3] += alpha
            end
          end
          alpha = (sums[3] / (sw * sh)).round
          color = if sums[3].positive?
                    [*sums.first(3).map { |value| (value * 255 / sums[3]).round }, alpha]
                  else
                    [0, 0, 0, 0]
                  end
          output.fill_rect(x, y, sw, sh, color)
        end
      end
      output
    end

    def overlay(image, source, x: nil, y: nil, gravity: :center, opacity: 1.0, blend: :normal)
      source = source.to_image if source.is_a?(Pipeline)
      raise TypeError, "overlay must be a Tessel::Image or Retouch::Pipeline" unless source.is_a?(Tessel::Image)

      default_x, default_y = Gravity.offset(image.width, image.height, source.width, source.height, gravity)
      x ||= default_x
      y ||= default_y
      opacity = Float(opacity)
      opacity /= 100 if opacity > 1
      raise ArgumentError, "opacity must be between 0 and 1" unless opacity.between?(0, 1)

      output = image.dup
      source.height.times do |sy|
        source.width.times do |sx|
          dx = Integer(x) + sx
          dy = Integer(y) + sy
          next unless dx.between?(0, image.width - 1) && dy.between?(0, image.height - 1)

          source_pixel = source[sx, sy]
          next if source_pixel[3].zero?

          source_pixel[3] = (source_pixel[3] * opacity).round
          output[dx, dy] = composite_pixel(output[dx, dy], source_pixel, blend.to_sym)
        end
      end
      output
    end

    def watermark(image, source, gravity: :south_east, opacity: 0.5, **options)
      overlay(image, source, gravity:, opacity:, **options)
    end

    def text(image, value, at: :north_west, x: nil, y: nil, size: 16, color: "#ffffff", font: nil, background: nil, padding: 4, **_options)
      padding = Integer(padding)
      raise ArgumentError, "padding must not be negative" if padding.negative?

      font = font_for(font, size, "text")
      width, height = font.measure(String(value))
      x ||= Gravity.offset(image.width, image.height, width + (padding * 2), height + (padding * 2), at).first
      y ||= Gravity.offset(image.width, image.height, width + (padding * 2), height + (padding * 2), at).last
      output = image.dup
      output.fill_rect(x, y, width + (padding * 2), height + (padding * 2), background) if background
      font.draw(output, x + padding, y + padding, String(value), color:)
      output
    end

    def rect(image, geometry, color: "#ffffff", fill: false, width: 1)
      geometry = Geometry.parse(geometry) unless geometry.is_a?(Geometry)
      x = geometry.offset_x
      y = geometry.offset_y
      w, h = geometry.crop_size(image.width, image.height)
      output = image.dup
      if fill
        output.fill_rect(x, y, w, h, color, blend: :alpha)
      else
        width = Integer(width)
        raise ArgumentError, "stroke width must be positive" unless width.positive?

        output.fill_rect(x, y, w, width, color, blend: :alpha)
        output.fill_rect(x, y + h - width, w, width, color, blend: :alpha)
        output.fill_rect(x, y, width, h, color, blend: :alpha)
        output.fill_rect(x + w - width, y, width, h, color, blend: :alpha)
      end
      output
    end

    def arrow(image, x1, y1, x2, y2, color: "#ffffff", width: 2, head: 10)
      output = image.dup
      x1, y1, x2, y2, width, head = [x1, y1, x2, y2, width, head].map { |v| Float(v) }
      raise ArgumentError, "arrow width and head must be positive" unless width.positive? && head.positive?

      draw_line(output, x1, y1, x2, y2, color, width)
      angle = Math.atan2(y2 - y1, x2 - x1)
      [angle + 2.6, angle - 2.6].each do |side|
        draw_line(output, x2, y2, x2 - (head * Math.cos(side)), y2 - (head * Math.sin(side)), color, width)
      end
      output
    end

    def montage(images, cols: 3, gap: 0, background: "#ffffff", label: false, labels: nil, font: nil)
      images = images.map { |image| image.is_a?(Pipeline) ? image.to_image : image }
      raise ArgumentError, "montage needs at least one image" if images.empty?

      cols = Integer(cols)
      gap = Integer(gap)
      raise ArgumentError, "cols must be positive and gap non-negative" unless cols.positive? && gap >= 0

      if label
        font = font_for(font, 12, "montage labels")
        labels ||= images.each_index.map(&:to_s)
        raise ArgumentError, "montage needs one label per image" unless labels.length == images.length
      end
      cell_width = images.map(&:width).max
      label_height = label ? font.line_height + 4 : 0
      cell_height = images.map(&:height).max + label_height
      rows = (images.length.to_f / cols).ceil
      output = Tessel::Image.new((cols * cell_width) + ((cols - 1) * gap), (rows * cell_height) + ((rows - 1) * gap), fill: background)
      images.each_with_index do |image, index|
        col = index % cols
        row = index / cols
        x = (col * (cell_width + gap)) + ((cell_width - image.width) / 2)
        y = (row * (cell_height + gap)) + ((cell_height - label_height - image.height) / 2)
        output.blit(image, x, y)
        font.draw(output, col * (cell_width + gap), y + image.height + 2, String(labels[index]), color: "#000000") if label
      end
      output
    end

    def append(images, direction: :horizontal, gap: 0, background: [0, 0, 0, 0])
      images = images.map { |image| image.is_a?(Pipeline) ? image.to_image : image }
      raise ArgumentError, "append needs at least one image" if images.empty?

      gap = Integer(gap)
      raise ArgumentError, "gap must not be negative" if gap.negative?

      raise ArgumentError, "direction must be :horizontal or :vertical" unless %i[horizontal vertical].include?(direction.to_sym)

      horizontal = direction.to_sym == :horizontal
      width = horizontal ? images.sum(&:width) + (gap * (images.length - 1)) : images.map(&:width).max
      height = horizontal ? images.map(&:height).max : images.sum(&:height) + (gap * (images.length - 1))
      output = Tessel::Image.new(width, height, fill: background)
      offset = 0
      images.each do |image|
        x, y = horizontal ? [offset, (height - image.height) / 2] : [(width - image.width) / 2, offset]
        output.blit(image, x, y)
        offset += (horizontal ? image.width : image.height) + gap
      end
      output
    end

    def spritesheet(images, cols: nil, gap: 0, background: [0, 0, 0, 0])
      images = images.map { |image| image.is_a?(Pipeline) ? image.to_image : image }
      raise ArgumentError, "spritesheet needs at least one image" if images.empty?

      gap = Integer(gap)
      raise ArgumentError, "gap must not be negative" if gap.negative?

      if cols
        cols = Integer(cols)
        raise ArgumentError, "cols must be positive" unless cols.positive?

        cell_width = images.map(&:width).max
        cell_height = images.map(&:height).max
        positions = images.each_index.map do |i|
          [(i % cols) * (cell_width + gap), (i / cols) * (cell_height + gap)]
        end
        columns = [cols, images.length].min
        width = (columns * cell_width) + ((columns - 1) * gap)
        height = ((images.length.to_f / cols).ceil * cell_height) + (((images.length.to_f / cols).ceil - 1) * gap)
      else
        positions, width, height = pack_sprites(images, gap)
      end
      sheet = Tessel::Image.new(width, height, fill: background)
      images.each_with_index { |image, i| sheet.blit(image, *positions[i]) }
      frames = images.each_with_index.to_h do |image, i|
        [i.to_s, { "x" => positions[i][0], "y" => positions[i][1], "width" => image.width, "height" => image.height }]
      end
      [sheet, { "frames" => frames, "meta" => { "size" => { "w" => sheet.width, "h" => sheet.height }, "scale" => "1" } }]
    end

    def animate(images, path, fps: nil, delay: nil, loop: true, format: nil, **options)
      require_optional("flipbook", "animate") { require "flipbook" }
      Flipbook.write(path, images.map { |image| image.is_a?(Pipeline) ? image.to_image : image }, fps:, delay:, loop:, format:, **options)
    end

    def diff(expected, actual, max_delta: 0)
      expected = expected.to_image if expected.is_a?(Pipeline)
      actual = actual.to_image if actual.is_a?(Pipeline)
      require_optional("lookalike", "diff") { require "lookalike" }
      comparison = Lookalike.compare(expected, actual, max_delta:)
      diff = comparison.diff_image || Tessel::Image.new(expected.width, expected.height)
      ratio = comparison.diff_pixels.to_f / ([expected.width, actual.width].max * [expected.height, actual.height].max)
      metadata = diff.metadata.merge("diff_pixels" => comparison.diff_pixels.to_s, "diff_ratio" => ratio.to_s)
      Tessel::Image.from_rgba(diff.width, diff.height, diff.bytes, metadata:)
    end

    def resample(image, width, height, filter)
      filter = filter.to_sym
      raise ArgumentError, "unknown resize filter: #{filter}" unless %i[nearest bilinear bicubic lanczos3].include?(filter)
      return image.scale_nearest(width, height) if filter == :nearest

      horizontal = axis_weights(image.width, width, filter)
      vertical = axis_weights(image.height, height, filter)
      source = image.bytes
      intermediate = String.new(capacity: width * image.height * 4, encoding: Encoding::BINARY)
      image.height.times do |y|
        width.times do |x|
          sums = [0.0, 0.0, 0.0, 0.0]
          horizontal[x].each do |sx, weight|
            offset = ((y * image.width) + sx) * 4
            alpha = source.getbyte(offset + 3) / 255.0
            sums[0] += source.getbyte(offset) * alpha * weight
            sums[1] += source.getbyte(offset + 1) * alpha * weight
            sums[2] += source.getbyte(offset + 2) * alpha * weight
            sums[3] += source.getbyte(offset + 3) * weight
          end
          sums.each { |v| intermediate << v.round.clamp(0, 255) }
        end
      end
      result = String.new(capacity: width * height * 4, encoding: Encoding::BINARY)
      height.times do |y|
        width.times do |x|
          sums = [0.0, 0.0, 0.0, 0.0]
          vertical[y].each do |sy, weight|
            offset = ((sy * width) + x) * 4
            4.times { |channel| sums[channel] += intermediate.getbyte(offset + channel) * weight }
          end
          alpha = sums[3].round.clamp(0, 255)
          if alpha.positive?
            3.times { |channel| result << (sums[channel] * 255 / alpha).round.clamp(0, 255) }
          else
            result << "\0\0\0".b
          end
          result << alpha
        end
      end
      Tessel::Image.from_rgba(width, height, result, metadata: image.metadata)
    end

    def axis_weights(source, target, filter)
      radius = { bilinear: 1, bicubic: 2, lanczos3: 3 }.fetch(filter)
      scale = [source.to_f / target, 1.0].max
      (0...target).map do |out|
        center = ((out + 0.5) * source / target) - 0.5
        first = (center - (radius * scale)).floor
        last = (center + (radius * scale)).ceil
        weights = Hash.new(0.0)
        (first..last).each do |index|
          distance = (center - index) / scale
          weight = case filter
                   when :bilinear then [1 - distance.abs, 0].max
                   when :bicubic then cubic(distance)
                   when :lanczos3 then lanczos(distance)
                   end
          weights[index.clamp(0, source - 1)] += weight
        end
        total = weights.values.sum
        weights.map { |index, weight| [index, weight / total] }
      end
    end

    def cubic(x)
      x = x.abs
      return (((1.5 * x) - 2.5) * x * x) + 1 if x < 1
      return (((((-0.5 * x) + 2.5) * x) - 4) * x) + 2 if x < 2

      0.0
    end

    def lanczos(x)
      x = x.abs
      return 1.0 if x.zero?
      return 0.0 if x >= 3

      Math.sin(Math::PI * x) * Math.sin(Math::PI * x / 3) * 3 / (Math::PI * Math::PI * x * x)
    end

    def convolve(image, weights, horizontal:)
      radius = weights.length / 2
      source = image.bytes.unpack("C*")
      output = String.new(capacity: image.width * image.height * 4, encoding: Encoding::BINARY)
      span = horizontal ? image.width : image.height
      contributions = Array.new(span) do |position|
        weights.each_index.map { |tap| (position + tap - radius).clamp(0, span - 1) }
      end
      y = 0
      while y < image.height
        x = 0
        while x < image.width
          red = 0.0
          green = 0.0
          blue = 0.0
          alpha_sum = 0.0
          taps = contributions[horizontal ? x : y]
          i = 0
          while i < weights.length
            offset = horizontal ? ((y * image.width) + taps[i]) * 4 : ((taps[i] * image.width) + x) * 4
            alpha = source[offset + 3] / 255.0
            weight = weights[i]
            red += source[offset] * alpha * weight
            green += source[offset + 1] * alpha * weight
            blue += source[offset + 2] * alpha * weight
            alpha_sum += source[offset + 3] * weight
            i += 1
          end
          alpha = alpha_sum.round.clamp(0, 255)
          if alpha.positive?
            output << (red * 255 / alpha).round.clamp(0, 255)
            output << (green * 255 / alpha).round.clamp(0, 255)
            output << (blue * 255 / alpha).round.clamp(0, 255)
          else
            output << "\0\0\0".b
          end
          output << alpha
          x += 1
        end
        y += 1
      end
      Tessel::Image.from_rgba(image.width, image.height, output, metadata: image.metadata)
    end

    def map_rgba(image)
      output = String.new(capacity: image.width * image.height * 4, encoding: Encoding::BINARY)
      image.bytes.bytes.each_slice(4) { |rgba| yield(*rgba).each { |v| output << Integer(v).clamp(0, 255) } }
      Tessel::Image.from_rgba(image.width, image.height, output, metadata: image.metadata)
    end

    def map_rgb(image, &block)
      map_rgba(image) { |r, g, b, a| [*block.call(r, g, b), a] }
    end

    def map_lut(image, lookup)
      source = image.bytes
      output = String.new(capacity: source.bytesize, encoding: Encoding::BINARY)
      offset = 0
      while offset < source.bytesize
        output << lookup[source.getbyte(offset)]
        output << lookup[source.getbyte(offset + 1)]
        output << lookup[source.getbyte(offset + 2)]
        output << source.getbyte(offset + 3)
        offset += 4
      end
      Tessel::Image.from_rgba(image.width, image.height, output, metadata: image.metadata)
    end

    def copy_metadata(output, source)
      Tessel::Image.from_rgba(output.width, output.height, output.bytes, metadata: source.metadata)
    end

    def rotate_quarter(image, turns)
      width, height = turns.odd? ? [image.height, image.width] : [image.width, image.height]
      output = Tessel::Image.new(width, height, metadata: image.metadata)
      image.height.times do |y|
        image.width.times do |x|
          dx, dy = case turns
                   when 1 then [image.height - y - 1, x]
                   when 2 then [image.width - x - 1, image.height - y - 1]
                   else [y, image.width - x - 1]
                   end
          output[dx, dy] = image[x, y]
        end
      end
      copy_metadata(output, image)
    end

    def sample_bilinear(image, x, y, background)
      x0 = x.floor
      y0 = y.floor
      fx = x - x0
      fy = y - y0
      pixels = [[x0, y0, (1 - fx) * (1 - fy)], [x0 + 1, y0, fx * (1 - fy)], [x0, y0 + 1, (1 - fx) * fy], [x0 + 1, y0 + 1, fx * fy]]
      sums = [0.0, 0.0, 0.0, 0.0]
      pixels.each do |px, py, weight|
        color = image[px.clamp(0, image.width - 1), py.clamp(0, image.height - 1)] || Tessel::Color.pack(background).bytes
        alpha = color[3] / 255.0
        3.times { |c| sums[c] += color[c] * alpha * weight }
        sums[3] += color[3] * weight
      end
      alpha = sums[3].round.clamp(0, 255)
      [*(alpha.positive? ? sums.first(3).map { |v| (v * 255 / alpha).round.clamp(0, 255) } : [0, 0, 0]), alpha]
    end

    def composite_pixel(destination, source, mode)
      raise ArgumentError, "unknown blend mode: #{mode}" unless %i[normal multiply screen overlay darken lighten add].include?(mode)

      sa = source[3] / 255.0
      da = destination[3] / 255.0
      out_a = sa + (da * (1 - sa))
      return [0, 0, 0, 0] if out_a.zero?

      rgb = 3.times.map do |c|
        s = source[c]
        d = destination[c]
        mixed = case mode
                when :normal then s
                when :multiply then s * d / 255.0
                when :screen then 255 - ((255 - s) * (255 - d) / 255.0)
                when :overlay then d < 128 ? 2 * s * d / 255.0 : 255 - (2 * (255 - s) * (255 - d) / 255.0)
                when :darken then [s, d].min
                when :lighten then [s, d].max
                when :add then [s + d, 255].min
                end
        source_only = (1 - da) * sa * s
        destination_only = (1 - sa) * da * d
        overlap = sa * da * mixed
        ((source_only + destination_only + overlap) / out_a).round.clamp(0, 255)
      end
      [*rgb, (out_a * 255).round]
    end

    def draw_line(image, x1, y1, x2, y2, color, width)
      steps = [(x2 - x1).abs, (y2 - y1).abs].max.ceil
      radius = [width / 2.0, 0.5].max
      (0..steps).each do |n|
        t = steps.zero? ? 0 : n.to_f / steps
        x = (x1 + ((x2 - x1) * t)).round
        y = (y1 + ((y2 - y1) * t)).round
        image.fill_rect((x - radius).floor, (y - radius).floor, radius.ceil * 2, radius.ceil * 2, color, blend: :alpha)
      end
    end

    def font_for(font, size, operation)
      require_optional("glyphic", operation) { require "glyphic" }
      font ||= ENV.fetch("RETOUCH_FONT", nil)
      raise ArgumentError, "#{operation} needs font: or RETOUCH_FONT pointing to a BDF/TTF font" unless font
      return font if font.respond_to?(:draw)
      return Glyphic::BDF.load(font) if File.extname(font).downcase == ".bdf"

      Glyphic::TrueType.load(font, size: Integer(size))
    end

    def pack_sprites(images, gap)
      sizes = images.map { |image| [image.width + gap, image.height + gap] }
      bin_width = [sizes.map(&:first).max, Math.sqrt(sizes.sum { |w, h| w * h }).ceil].max
      free = [[0, 0, bin_width, sizes.sum(&:last)]]
      positions = Array.new(images.length)
      order = images.each_index.sort_by { |i| [-[sizes[i][0], sizes[i][1]].max, -(sizes[i][0] * sizes[i][1]), i] }
      order.each do |index|
        width, height = sizes[index]
        choice = free.filter_map do |x, y, free_width, free_height|
          next if width > free_width || height > free_height

          leftover_width = free_width - width
          leftover_height = free_height - height
          [[[leftover_width, leftover_height].min, [leftover_width, leftover_height].max, y, x], [x, y, width, height]]
        end.min_by(&:first)
        raise Error, "could not pack sprite #{index}" unless choice

        placed = choice.last
        positions[index] = placed.first(2)
        free = free.flat_map { |rect| split_free_rect(rect, placed) }
        free.uniq!
        free.reject! { |rect| free.any? { |other| other != rect && contains_rect?(other, rect) } }
      end
      width = images.each_index.map { |i| positions[i][0] + images[i].width }.max
      height = images.each_index.map { |i| positions[i][1] + images[i].height }.max
      [positions, width, height]
    end

    def split_free_rect(free, placed)
      x, y, width, height = free
      px, py, pwidth, pheight = placed
      return [free] if px >= x + width || px + pwidth <= x || py >= y + height || py + pheight <= y

      result = []
      result << [x, y, px - x, height] if px > x
      result << [px + pwidth, y, x + width - px - pwidth, height] if px + pwidth < x + width
      result << [x, y, width, py - y] if py > y
      result << [x, py + pheight, width, y + height - py - pheight] if py + pheight < y + height
      result.select { |_, _, w, h| w.positive? && h.positive? }
    end

    def contains_rect?(outer, inner)
      x, y, width, height = outer
      ix, iy, iwidth, iheight = inner
      ix >= x && iy >= y && ix + iwidth <= x + width && iy + iheight <= y + height
    end

    def require_optional(gem, operation)
      yield
    rescue LoadError => e
      raise Error, "#{operation} requires the #{gem} gem", cause: e
    end
  end
end
