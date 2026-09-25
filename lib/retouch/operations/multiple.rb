# frozen_string_literal: true

module Retouch
  module Operations
    module_function

    def append(images, direction: :vertical, gap: 0, background: [0, 0, 0, 0])
      images = validate_images(images)
      direction = direction.to_sym
      gap = Integer(gap)
      raise ArgumentError, "direction must be vertical or horizontal" unless %i[vertical horizontal].include?(direction)
      raise ArgumentError, "gap must not be negative" if gap.negative?

      if direction == :vertical
        width = images.map(&:width).max
        height = images.sum(&:height) + (gap * (images.length - 1))
      else
        width = images.sum(&:width) + (gap * (images.length - 1))
        height = images.map(&:height).max
      end
      output = Tessel::Image.new(width, height, fill: background)
      x = y = 0
      images.each do |image|
        dx, dy = Gravity.offset(width, height, image.width, image.height, :center)
        output.blit(image, direction == :vertical ? dx : x, direction == :vertical ? y : dy)
        direction == :vertical ? y += image.height + gap : x += image.width + gap
      end
      output
    end

    def montage(images, columns: nil, cols: nil, gap: 0, background: [0, 0, 0, 0], labels: nil)
      images = validate_images(images)
      columns = Integer(columns || cols || Math.sqrt(images.length).ceil)
      gap = Integer(gap)
      raise ArgumentError, "columns must be positive" unless columns.positive?
      raise ArgumentError, "gap must not be negative" if gap.negative?

      column_widths = Array.new([images.length, columns].min, 0)
      row_heights = Array.new((images.length.to_f / columns).ceil, 0)
      images.each_with_index do |image, index|
        column = index % columns
        row = index / columns
        column_widths[column] = [column_widths[column], image.width].max
        row_heights[row] = [row_heights[row], image.height + (labels ? 15 : 0)].max
      end
      output = Tessel::Image.new(column_widths.sum + (gap * (column_widths.length - 1)), row_heights.sum + (gap * (row_heights.length - 1)), fill: background)
      row_y = 0
      row_heights.each_with_index do |row_height, row|
        column_x = 0
        column_widths.each_with_index do |column_width, column|
          index = (row * columns) + column
          break unless images[index]

          image = images[index]
          image_y = row_y + ((row_height - image.height - (labels ? 15 : 0)) / 2)
          output.blit(image, column_x + ((column_width - image.width) / 2), image_y)
          if labels
            label = labels == true ? index.to_s : String(labels.fetch(index))
            output.fill_rect(column_x, row_y + row_height - 15, column_width, 15, [0, 0, 0, 192], blend: :alpha)
            output = text(output, label, x: column_x + 3, y: row_y + row_height - 12, size: 9, color: "#ffffff")
          end
          column_x += column_width + gap
        end
        row_y += row_height + gap
      end
      output
    end

    def spritesheet(images, max_width: 2048, gap: 0, background: [0, 0, 0, 0])
      images = validate_images(images)
      max_width = Integer(max_width)
      gap = Integer(gap)
      raise ArgumentError, "max_width must be positive" unless max_width.positive?
      raise ArgumentError, "gap must not be negative" if gap.negative?
      raise ArgumentError, "an image is wider than max_width" if images.any? { |image| image.width > max_width }

      bound_height = images.sum(&:height) + (gap * images.length)
      free = [{ x: 0, y: 0, width: max_width, height: bound_height }]
      placements = Array.new(images.length)
      images.each_with_index.sort_by { |image, index| [-image.width * image.height, -[image.width, image.height].max, index] }.each do |image, index|
        packed_width = image.width + gap
        packed_height = image.height + gap
        position = free.select { |rect| packed_width <= rect[:width] && packed_height <= rect[:height] }
                       .map do |rect|
          leftover_width = rect[:width] - packed_width
          leftover_height = rect[:height] - packed_height
          score = [
            [leftover_width, leftover_height].min,
            rect[:y],
            rect[:x],
            [leftover_width, leftover_height].max
          ]
          [score, rect[:x], rect[:y]]
        end.min_by(&:first)
        raise ArgumentError, "could not pack images within max_width" unless position

        _score, x, y = position
        packed = { x:, y:, width: packed_width, height: packed_height }
        placements[index] = { index:, x:, y:, width: image.width, height: image.height }
        free = split_free_rectangles(free, packed)
      end
      used_width = placements.map { |item| item[:x] + item[:width] }.max || 0
      height = placements.map { |item| item[:y] + item[:height] }.max || 0
      output = Tessel::Image.new(used_width, height, fill: background)
      images.zip(placements).each { |image, item| output.blit(image, item[:x], item[:y]) }
      [output, placements]
    end

    def diff(expected, actual, threshold: 0, color: "#ff00ff")
      raise TypeError, "expected and actual must be Tessel::Image values" unless expected.is_a?(Tessel::Image) && actual.is_a?(Tessel::Image)
      raise ArgumentError, "images must have the same dimensions" unless expected.width == actual.width && expected.height == actual.height

      threshold = Float(threshold)
      raise ArgumentError, "threshold must be between 0 and 255" unless threshold.finite? && threshold.between?(0, 255)

      marker = Tessel::Color.pack(color).bytes
      output = Tessel::Image.new(expected.width, expected.height)
      different = 0
      expected.height.times do |y|
        expected.width.times do |x|
          left = expected[x, y]
          right = actual[x, y]
          if left.zip(right).map { |a, b| (a - b).abs }.max > threshold
            output[x, y] = marker
            different += 1
          end
        end
      end
      { image: output, pixels: different, total: expected.width * expected.height,
        rate: expected.width.zero? || expected.height.zero? ? 0.0 : different.to_f / (expected.width * expected.height) }
    end

    def animate(frames, path, fps: nil, delay: nil, loop: true, colors: 256, palette: :global, dither: :floyd_steinberg)
      require_flipbook
      Flipbook.write(path, validate_images(frames), fps:, delay:, loop:, colors:, palette:, dither:)
    end

    def open_gif(path, frame: :all, max_pixels: 16_384 * 16_384, max_frames: 10_000, max_total_pixels: 100_000_000)
      require_flipbook
      frames = Flipbook.read(path, max_pixels:, max_frames:, max_total_pixels:)
      return frames if frame == :all

      frames.fetch(frame == :first ? 0 : Integer(frame))
    end

    def validate_images(images)
      images = Array(images)
      raise ArgumentError, "at least one image is required" if images.empty?
      raise TypeError, "images must contain only Tessel::Image values" unless images.all?(Tessel::Image)
      raise ArgumentError, "images must have positive dimensions" unless images.all? { |image| image.width.positive? && image.height.positive? }

      images
    end
    private_class_method :validate_images

    def split_free_rectangles(free, placed)
      split = free.flat_map do |rect|
        overlaps = placed[:x] < rect[:x] + rect[:width] && placed[:x] + placed[:width] > rect[:x] &&
                   placed[:y] < rect[:y] + rect[:height] && placed[:y] + placed[:height] > rect[:y]
        next [rect] unless overlaps

        pieces = []
        pieces << { x: rect[:x], y: rect[:y], width: rect[:width], height: placed[:y] - rect[:y] } if placed[:y] > rect[:y]
        pieces << { x: rect[:x], y: placed[:y] + placed[:height], width: rect[:width], height: rect[:y] + rect[:height] - placed[:y] - placed[:height] } if placed[:y] + placed[:height] < rect[:y] + rect[:height]
        pieces << { x: rect[:x], y: rect[:y], width: placed[:x] - rect[:x], height: rect[:height] } if placed[:x] > rect[:x]
        pieces << { x: placed[:x] + placed[:width], y: rect[:y], width: rect[:x] + rect[:width] - placed[:x] - placed[:width], height: rect[:height] } if placed[:x] + placed[:width] < rect[:x] + rect[:width]
        pieces.select { |piece| piece[:width].positive? && piece[:height].positive? }
      end
      # ponytail: free-rectangle pruning is O(n²); replace it if large atlases make it slow.
      split.reject.with_index do |rect, index|
        split.each_with_index.any? do |other, other_index|
          next false if index == other_index

          contained = other[:x] <= rect[:x] && other[:y] <= rect[:y] &&
                      other[:x] + other[:width] >= rect[:x] + rect[:width] &&
                      other[:y] + other[:height] >= rect[:y] + rect[:height]
          contained && (other != rect || other_index < index)
        end
      end
    end
    private_class_method :split_free_rectangles

    def require_flipbook
      require "flipbook"
      version = Gem::Version.new(Flipbook::VERSION)
      raise Error, "GIF/APNG support requires flipbook >= 0.3.0 (found #{version})" if version < Gem::Version.new("0.3.0")
    rescue LoadError => e
      raise Error, "GIF/APNG support requires flipbook >= 0.3.0 (gem install flipbook)", cause: e
    end
    private_class_method :require_flipbook
  end
end
