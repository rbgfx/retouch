# frozen_string_literal: true

require "tessel"
require "fileutils"
require_relative "retouch/version"
require_relative "retouch/geometry"
require_relative "retouch/gravity"
require_relative "retouch/operations"
require_relative "retouch/pipeline"
require_relative "retouch/cli"
require_relative "retouch/io"

module Retouch
  class Error < StandardError; end

  def self.open(path)
    Pipeline.new(ImageIO.read(path))
  end

  def self.from_image(image)
    Pipeline.new(image)
  end
end
