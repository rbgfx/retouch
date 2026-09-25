# frozen_string_literal: true

require_relative "test_helper"

class RetouchTest < Test::Unit::TestCase
  test "geometry handles fit, stretch, cover, percentages, shrink, and offsets" do
    assert_equal [800, 600], Retouch::Geometry.parse("800x600!").target_size(400, 300)
    assert_equal [200, 150], Retouch::Geometry.parse("50%").target_size(400, 300)
    assert_equal [800, 600], Retouch::Geometry.parse("800x").target_size(400, 300)
    assert_equal [400, 300], Retouch::Geometry.parse("800x600>").target_size(400, 300)
    assert_equal [800, 600], Retouch::Geometry.parse("800x600").target_size(400, 300)
    assert_equal [4, 2], Retouch::Geometry.parse("2x2^").target_size(4, 2)
    assert_raise(ArgumentError) { Retouch::Geometry.parse("0x20") }
    assert_raise(ArgumentError) { Retouch::Geometry.parse("garbage") }
  end

  test "gravity covers all nine anchors and rejects unknown positions" do
    assert_equal [80, 70], Retouch::Gravity.offset(100, 80, 20, 10, :south_east)
    assert_equal [0, 0], Retouch::Gravity.offset(100, 80, 20, 10, "north-west")
    assert_equal [40, 35], Retouch::Gravity.offset(100, 80, 20, 10, :center)
    assert_raise(ArgumentError) { Retouch::Gravity.offset(10, 10, 1, 1, :middle) }
  end

  test "pipelines are lazy and do not mutate their source" do
    image = sample_image
    result = Retouch.from_image(image).flop.resize("4x4!", filter: :nearest).to_image
    assert_equal [255, 0, 0, 255], image[0, 0]
    assert_equal [4, 4], [result.width, result.height]
    assert_instance_of Retouch::Pipeline, Retouch.from_image(image)
    assert_equal image.bytes, Retouch.from_image(image).to_image.bytes
  end

  test "resize filters preserve dimensions and transparent edge colors" do
    image = sample_image
    %i[nearest bilinear bicubic lanczos3].each do |filter|
      result = Retouch.from_image(image).resize("4x4!", filter:).to_image
      assert_equal [4, 4], [result.width, result.height]
      assert_operator result[3, 3][3], :<, 255
    end
    assert_raise(ArgumentError) { Retouch.from_image(image).resize("3x3!", filter: :unknown).to_image }
    transparent_red = Tessel::Image.new(2, 1)
    transparent_red[0, 0] = [255, 0, 0, 0]
    transparent_red[1, 0] = [0, 0, 255, 255]
    pixel = Retouch.from_image(transparent_red).resize("4x1!", filter: :bilinear).to_image[1, 0]
    assert_operator pixel[0], :<, 20
    assert_operator pixel[2], :>, 240
  end

  test "shape operations preserve orientation, metadata, and padding" do
    image = sample_image
    assert_equal image[0, 0], Retouch::Operations.rotate(image, 90)[1, 0]
    assert_equal image[0, 0], Retouch::Operations.rotate(image, 180)[1, 1]
    assert_equal [3, 3], [Retouch::Operations.rotate(image, 30).width, Retouch::Operations.rotate(image, 30).height]
    assert_equal image[1, 0], Retouch::Operations.flop(image)[0, 0]
    assert_equal image[0, 1], Retouch::Operations.flip(image)[0, 0]
    assert_equal image[1, 1], Retouch::Operations.crop(image, "1x1+1+1")[0, 0]
    assert_equal [4, 4], [Retouch::Operations.pad(image, 1).width, Retouch::Operations.pad(image, 1).height]
    assert_equal [4, 3], [Retouch::Operations.extend(image, 4, 3, gravity: :south_east).width, Retouch::Operations.extend(image, 4, 3).height]
    assert_equal [4, 4], [Retouch::Operations.border(image, 1).width, Retouch::Operations.border(image, 1).height]
    trim = Tessel::Image.new(3, 3, fill: "#ff0000")
    trim[1, 1] = [0, 0, 255, 255]
    assert_equal [1, 1], [Retouch::Operations.trim(trim).width, Retouch::Operations.trim(trim).height]
    assert_raise(ArgumentError) { Retouch::Operations.pad(image, -1) }
    assert_raise(ArgumentError) { Retouch::Operations.extend(image, 1, 1) }
  end

  test "Tessel formats round-trip and info reports the format" do
    Dir.mktmpdir do |dir|
      %w[png ppm bmp].each do |extension|
        path = File.join(dir, "pixel.#{extension}")
        sample_image.write(path)
        loaded = Retouch.open(path)
        assert_equal sample_image[0, 0], loaded.to_image[0, 0]
        assert_equal(extension == "ppm" ? "PPM" : extension.upcase, loaded.info[:format])
      end
      stripped = File.join(dir, "stripped.png")
      image = Retouch.open(File.join(dir, "pixel.png"))
      assert_empty image.thumbnail("1x").to_image.metadata
      image.thumbnail("1x").save(stripped)
      assert_equal "PNG", Retouch.open(stripped).info[:format]
    end
  end

  test "CLI transforms one image, reports info, and validates output rules" do
    Dir.mktmpdir do |dir|
      input = File.join(dir, "input.png")
      sample_image.write(input)
      output = File.join(dir, "nested", "small.png")
      out = StringIO.new
      err = StringIO.new

      assert_equal 0, Retouch::CLI.run([input, "resize", "4x4!", "--filter", "nearest", "-o", output], out:, err:)
      assert_equal 4, Tessel.read(output).width
      assert_equal 2, Retouch::CLI.run([input, "invert", "-o", output], out:, err:)
      assert_equal 0, Retouch::CLI.run([input, "resize", "1x", "-o", File.join(dir, "dry.png"), "--dry-run"], out:, err:)
      assert_false File.exist?(File.join(dir, "dry.png"))
      info = StringIO.new
      assert_equal 0, Retouch::CLI.run(["info", input], out: info, err:)
      assert_equal "PNG", JSON.parse(info.string).fetch("format")
      assert_equal 0, Retouch::CLI.run(%w[help resize], out:, err:)
      assert_include out.string, "resize [ARGUMENTS]"
      assert_equal 2, Retouch::CLI.run([input, "unknown", "1x", "-o", output], out:, err:)
      assert_equal 2, Retouch::CLI.run([input, "resize", "1x"], out:, err:)
      assert_equal 2, Retouch::CLI.run([input, File.join(dir, "other.png"), "resize", "1x", "-o", output], out:, err:)
    end
  end

  private

  def sample_image
    @sample_image ||= Tessel::Image.new(2, 2).tap do |image|
      image[0, 0] = [255, 0, 0, 255]
      image[1, 0] = [0, 255, 0, 255]
      image[0, 1] = [0, 0, 255, 255]
      image[1, 1] = [255, 255, 255, 0]
    end
  end
end
