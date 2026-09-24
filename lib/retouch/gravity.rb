# frozen_string_literal: true

module Retouch
  module Gravity
    DIRECTIONS = {
      north_west: [0, 0], north: [0.5, 0], north_east: [1, 0],
      west: [0, 0.5], center: [0.5, 0.5], east: [1, 0.5],
      south_west: [0, 1], south: [0.5, 1], south_east: [1, 1]
    }.freeze

    module_function

    def offset(container_width, container_height, content_width, content_height, gravity = :center)
      horizontal, vertical = DIRECTIONS.fetch(gravity.to_s.tr("-", "_").to_sym) { raise ArgumentError, "unknown gravity: #{gravity}" }
      [(container_width - content_width) * horizontal, (container_height - content_height) * vertical].map(&:round)
    end
  end
end
