# frozen_string_literal: true

require "tessel"
require "fileutils"
require_relative "retouch/version"
require_relative "retouch/geometry"
require_relative "retouch/gravity"
require_relative "retouch/operations"
require_relative "retouch/pipeline"
require_relative "retouch/io"
require_relative "retouch/kernels/lut"
require_relative "retouch/kernels/convolve"
require_relative "retouch/kernels/color"
require_relative "retouch/operations/color"
require_relative "retouch/operations/filter"
require_relative "retouch/operations/draw"
require_relative "retouch/operations/multiple"
require_relative "retouch/batch"
require_relative "retouch/cli"

module Retouch
  class Error < StandardError; end

  def self.open(path)
    Pipeline.new(ImageIO.read(path))
  end

  def self.from_image(image)
    Pipeline.new(image)
  end

  def self.open_gif(path, frame: :all, **limits)
    result = Operations.open_gif(path, frame:, **limits)
    frame == :all ? result : Pipeline.new(result)
  end
end
