# frozen_string_literal: true

require_relative "test_helper"

class ReadmeExamplesTest < Test::Unit::TestCase
  test "Ruby usage examples execute against temporary images" do
    Dir.mktmpdir do |dir|
      input = File.join(dir, "screenshot.png")
      output = File.join(dir, "small.png")
      shots = File.join(dir, "shots")
      thumbs = File.join(dir, "thumbs")
      FileUtils.mkdir_p(shots)
      image = Tessel::Image.new(4, 4, fill: "#8090a0")
      image.write(input)
      image.write(File.join(shots, "one.png"))

      Retouch.open(input).resize("50%").border(1, "#303846").save(output)
      assert_equal [4, 4], [Tessel.read(output).width, Tessel.read(output).height]

      transformed = Retouch.open(input).crop("2x2+1+1").grayscale.to_image
      assert_equal [2, 2], [transformed.width, transformed.height]

      Retouch.batch(File.join(shots, "*.png"), to: File.join(thumbs, "{name}.png")) do |pipeline|
        pipeline.thumbnail("320x")
      end
      assert File.file?(File.join(thumbs, "one.png"))
    end
  end
end
