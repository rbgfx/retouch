# frozen_string_literal: true

require_relative "test_helper"

class ReadmeExamplesTest < Test::Unit::TestCase
  test "Ruby usage examples execute against a temporary image" do
    Dir.mktmpdir do |dir|
      input = File.join(dir, "screenshot.png")
      output = File.join(dir, "small.png")
      Tessel::Image.new(4, 4, fill: "#8090a0").write(input)

      Retouch.open(input).resize("50%").border(1, "#303846").save(output)
      assert_equal [4, 4], [Tessel.read(output).width, Tessel.read(output).height]

      transformed = Retouch.open(input).crop("2x2+1+1").resize("1x1!").to_image
      assert_equal [1, 1], [transformed.width, transformed.height]
    end
  end
end
