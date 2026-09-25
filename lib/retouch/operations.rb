# frozen_string_literal: true

module Retouch
  module Operations
    WEIGHT_SCALE = 1 << 20

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

    def crop(image, geometry, gravity: :north_west)
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
          output[x, y] = sample_bilinear(image, sx, sy, background) if sx.between?(0, image.width - 1) && sy.between?(0, image.height - 1)
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

    def border(image, width, color = "#000000")
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
          sums = [0, 0, 0, 0]
          horizontal[x].each do |sx, weight|
            offset = ((y * image.width) + sx) * 4
            alpha = source.getbyte(offset + 3)
            sums[0] += source.getbyte(offset) * alpha * weight
            sums[1] += source.getbyte(offset + 1) * alpha * weight
            sums[2] += source.getbyte(offset + 2) * alpha * weight
            sums[3] += source.getbyte(offset + 3) * weight
          end
          3.times { |channel| intermediate << round_divide(sums[channel], 255 * WEIGHT_SCALE).clamp(0, 255) }
          intermediate << round_divide(sums[3], WEIGHT_SCALE).clamp(0, 255)
        end
      end
      result = String.new(capacity: width * height * 4, encoding: Encoding::BINARY)
      height.times do |y|
        width.times do |x|
          sums = [0, 0, 0, 0]
          vertical[y].each do |sy, weight|
            offset = ((sy * width) + x) * 4
            4.times { |channel| sums[channel] += intermediate.getbyte(offset + channel) * weight }
          end
          alpha = round_divide(sums[3], WEIGHT_SCALE).clamp(0, 255)
          if alpha.positive?
            3.times { |channel| result << round_divide(sums[channel] * 255, WEIGHT_SCALE * alpha).clamp(0, 255) }
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
        fixed = weights.map { |index, weight| [index, ((weight / total) * WEIGHT_SCALE).round] }
        largest = fixed.each_index.max_by { |i| fixed[i][1].abs }
        fixed[largest][1] += WEIGHT_SCALE - fixed.sum { |_, weight| weight }
        fixed
      end
    end

    def round_divide(value, divisor)
      value.negative? ? -((-value + (divisor / 2)) / divisor) : (value + (divisor / 2)) / divisor
    end

    def cubic(value)
      value = value.abs
      return (((1.5 * value) - 2.5) * value * value) + 1 if value < 1
      return (((((-0.5 * value) + 2.5) * value) - 4) * value) + 2 if value < 2

      0.0
    end

    def lanczos(value)
      value = value.abs
      return 1.0 if value.zero?
      return 0.0 if value >= 3

      Math.sin(Math::PI * value) * Math.sin(Math::PI * value / 3) * 3 / (Math::PI * Math::PI * value * value)
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
        3.times { |channel| sums[channel] += color[channel] * alpha * weight }
        sums[3] += color[3] * weight
      end
      alpha = sums[3].round.clamp(0, 255)
      [*(alpha.positive? ? sums.first(3).map { |value| (value * 255 / alpha).round.clamp(0, 255) } : [0, 0, 0]), alpha]
    end

    private_class_method :resample, :axis_weights, :round_divide, :cubic, :lanczos, :copy_metadata, :rotate_quarter, :sample_bilinear
  end
end
