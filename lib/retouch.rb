# frozen_string_literal: true

require "tessel"
require "fileutils"
require_relative "retouch/version"
require_relative "retouch/geometry"
require_relative "retouch/gravity"
require_relative "retouch/operations"
require_relative "retouch/pipeline"
require_relative "retouch/batch"
require_relative "retouch/cli"
require_relative "retouch/io"

module Retouch
  class Error < StandardError; end

  def self.open(path, frame: 0)
    Pipeline.new(ImageIO.read(path, frame:))
  end

  def self.from_image(image)
    Pipeline.new(image)
  end

  def self.batch(pattern, to:, force: false, jobs: 1, level: 6, strip: false, &)
    Batch.run(pattern, to:, force:, jobs:, level:, strip:, &)
  end
end
