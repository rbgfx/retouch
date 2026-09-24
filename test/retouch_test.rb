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
    geometry = Retouch::Geometry.parse("80x60+10-20")
    assert_equal [10, -20], [geometry.offset_x, geometry.offset_y]
    assert_raise(ArgumentError) { Retouch::Geometry.parse("0x20") }
    assert_raise(ArgumentError) { Retouch::Geometry.parse("x") }
    assert_raise(ArgumentError) { Retouch::Geometry.parse("garbage") }
    assert_raise(ArgumentError) { Retouch::Geometry.parse("20x").crop_size(10, 10) }
  end

  test "gravity covers all nine anchors and rejects unknown positions" do
    assert_equal [80, 70], Retouch::Gravity.offset(100, 80, 20, 10, :south_east)
    assert_equal [0, 0], Retouch::Gravity.offset(100, 80, 20, 10, "north-west")
    assert_equal [40, 35], Retouch::Gravity.offset(100, 80, 20, 10, :center)
    assert_raise(ArgumentError) { Retouch::Gravity.offset(10, 10, 1, 1, :middle) }
  end

  test "pipelines are lazy and do not mutate their source" do
    image = sample_image
    result = Retouch.from_image(image).flop.grayscale.to_image
    assert_equal [255, 0, 0, 255], image[0, 0]
    assert_equal [182, 182, 182, 255], result[0, 0]
    assert_instance_of Retouch::Pipeline, Retouch.from_image(image)
    assert_equal image.bytes, Retouch.from_image(image).to_image.bytes
  end

  test "resize filters preserve dimensions, constants, and transparent edge colors" do
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
    solid = Tessel::Image.new(3, 3, fill: [80, 120, 160, 255])
    assert_equal solid.bytes, Retouch::Operations.blur(solid, sigma: 1.5).bytes
  end

  test "shape operations preserve orientation, metadata, and transparent padding" do
    image = sample_image
    assert_equal image[0, 0], Retouch::Operations.rotate(image, 90)[1, 0]
    assert_equal image[0, 0], Retouch::Operations.rotate(image, 180)[1, 1]
    assert_equal [3, 3], [Retouch::Operations.rotate(image, 30).width, Retouch::Operations.rotate(image, 30).height]
    assert_equal image[1, 0], Retouch::Operations.flop(image)[0, 0]
    assert_equal image[0, 1], Retouch::Operations.flip(image)[0, 0]
    assert_equal image[1, 1], Retouch::Operations.crop(image, "1x1+1+1")[0, 0]
    assert_equal [4, 4], [Retouch::Operations.pad(image, 1).width, Retouch::Operations.pad(image, 1).height]
    assert_equal [4, 3], [Retouch::Operations.extend(image, 4, 3, gravity: :south_east).width, Retouch::Operations.extend(image, 4, 3).height]
    assert_equal [4, 4], [Retouch::Operations.border(image, 1, "#112233").width, Retouch::Operations.border(image, 1, "#112233").height]
    trim_image = Tessel::Image.new(3, 3, fill: "#ff0000")
    trim_image[1, 1] = [0, 0, 255, 255]
    assert_equal [1, 1], [Retouch::Operations.trim(trim_image).width, Retouch::Operations.trim(trim_image).height]
    assert_equal "PNG", Retouch::Operations.crop(Retouch::ImageIO.with_format(image, "PNG"), "1x1").metadata.fetch("format")
  end

  test "color operations and quantization preserve alpha" do
    image = sample_image
    assert_equal [182, 182, 182, 255], Retouch::Operations.grayscale(image)[1, 0]
    assert_equal [0, 255, 255, 255], Retouch::Operations.invert(image)[0, 0]
    assert_equal [255, 26, 26, 255], Retouch::Operations.brightness(image, 0.1)[0, 0]
    assert_equal 255, Retouch::Operations.contrast(image, 0.5)[0, 0][3]
    assert_equal 255, Retouch::Operations.gamma(image, 2)[0, 0][3]
    assert_equal 255, Retouch::Operations.saturate(image, 0)[0, 0][3]
    assert_equal [255, 0, 0, 255], Retouch::Operations.tint(image, "#000000", amount: 0)[0, 0]
    assert_equal 128, Retouch::Operations.opacity(image, 0.5)[0, 0][3]
    assert_equal 0, Retouch::Operations.opacity(image, 0)[0, 0][3]
    assert_raise(ArgumentError) { Retouch::Operations.tint(image, "#ffffff", amount: 2) }
    assert_raise(ArgumentError) { Retouch::Operations.gamma(image, 0) }
    quantized = Retouch::Operations.quantize(image, colors: 2, dither: :ordered)
    assert_equal image.width, quantized.width
    assert_equal 0, quantized[1, 1][3]
  end

  test "blur, sharpen, and pixelate handle alpha correctly" do
    image = sample_image
    assert_equal image.width, Retouch::Operations.sharpen(image, amount: 1.5, sigma: 0.5).width
    source = Tessel::Image.new(2, 1)
    source[0, 0] = [255, 0, 0, 0]
    source[1, 0] = [0, 0, 255, 255]
    pixel = Retouch::Operations.pixelate(source, 2)[0, 0]
    assert_equal [0, 0, 255, 128], pixel
    assert_raise(ArgumentError) { Retouch::Operations.blur(image, sigma: 0) }
    assert_raise(ArgumentError) { Retouch::Operations.pixelate(image, 0) }
  end

  test "overlay supports blend modes and respects explicit offsets" do
    image = Tessel::Image.new(2, 2, fill: "#ffffff")
    source = Tessel::Image.new(1, 1, fill: "#000000")
    %i[normal multiply screen overlay darken lighten add].each do |blend|
      assert_equal 4, Retouch::Operations.overlay(image, source, x: 0, y: 1, blend:)[0, 0].length
    end
    assert_equal [0, 0, 0, 255], Retouch::Operations.overlay(image, source, x: 0, y: 1)[0, 1]
    assert_equal [255, 255, 255, 255], Retouch::Operations.overlay(image, source, x: 0, y: 1)[0, 0]
    assert_equal 127, Retouch::Operations.watermark(image, source, opacity: 0.5)[1, 1][0]
    assert_raise(ArgumentError) { Retouch::Operations.overlay(image, source, blend: :unknown) }
  end

  test "draws text, rectangles, and arrows" do
    require "glyphic"
    glyph = Glyphic::Glyph.new(advance: 1, bearing_x: 0, bearing_y: 1, width: 1, height: 1, alpha: "\xff".b)
    font = Glyphic::Font.new({ "A".ord => glyph }, line_height: 1, ascent: 1)
    result = Retouch::Operations.text(Tessel::Image.new(8, 8), "A", font:, x: 1, y: 1, padding: 0)
    assert_equal 255, result[1, 1][3]
    assert_operator Retouch::Operations.montage([sample_image], label: true, labels: ["A"], font:).height, :>, 2
    pixel = Retouch::Operations.rect(sample_image, "1x1+1+1", color: "#ff0000", fill: true)[1, 1]
    assert_equal "#ff0000", "##{pixel.first(3).map { |channel| channel.to_s(16).rjust(2, "0") }.join}"
    assert_equal 8, Retouch::Operations.arrow(Tessel::Image.new(8, 8), 0, 0, 7, 7).width
    assert_raise(ArgumentError) { Retouch::Operations.text(sample_image, "A", font:, padding: -1) }
    assert_raise(ArgumentError) { Retouch::Operations.arrow(sample_image, 0, 0, 1, 1, width: 0) }
  end

  test "montage, append, and max-rectangle spritesheets expose valid coordinates" do
    images = [
      Tessel::Image.new(6, 2, fill: "#ff0000"),
      Tessel::Image.new(3, 4, fill: "#00ff00"),
      Tessel::Image.new(3, 2, fill: "#0000ff")
    ]
    sheet, map = Retouch::Operations.spritesheet(images, gap: 1)
    frames = map.fetch("frames").values
    frames.combination(2) do |left, right|
      overlaps = left["x"] < right["x"] + right["width"] &&
                 left["x"] + left["width"] > right["x"] &&
                 left["y"] < right["y"] + right["height"] &&
                 left["y"] + left["height"] > right["y"]
      assert_false overlaps
    end
    assert_equal({ "w" => sheet.width, "h" => sheet.height }, map.dig("meta", "size"))
    assert_operator sheet.width * sheet.height, :<, 13 * 8
    assert_equal 13, Retouch::Operations.spritesheet([images[0], images[0]], cols: 2, gap: 1).first.width
    assert_equal 4, Retouch::Operations.append([sample_image, sample_image], direction: :vertical).height
    assert_equal 5, Retouch::Operations.append([sample_image, sample_image], gap: 1).width
    assert_raise(ArgumentError) { Retouch::Operations.append(images, direction: :diagonal) }
  end

  test "Tessel formats round-trip and info reports their format" do
    Dir.mktmpdir do |dir|
      %w[png ppm bmp].each do |extension|
        path = File.join(dir, "pixel.#{extension}")
        sample_image.write(path)
        loaded = Retouch.open(path)
        assert_equal sample_image[0, 0], loaded.to_image[0, 0]
        assert_equal(extension == "ppm" ? "PPM" : extension.upcase, loaded.info[:format])
      end
      stripped = File.join(dir, "stripped.png")
      source = Retouch.open(File.join(dir, "pixel.png"))
      assert_empty source.thumbnail("1x").to_image.metadata
      source.thumbnail("1x").save(stripped)
      assert_equal "PNG", Retouch.open(stripped).info[:format]
    end
  end

  test "batch templates, collision checks, overwrite rules, and fork workers work" do
    Dir.mktmpdir do |dir|
      sources = %w[a b].map do |name|
        path = File.join(dir, "#{name}.png")
        sample_image.write(path)
        path
      end
      output = File.join(dir, "out", "{name}-{index:02}.png")
      result = Retouch.batch(sources, to: output, jobs: 2, level: 0, strip: true) { |pipeline| pipeline.thumbnail("1x") }
      assert_equal(%w[a-00.png b-01.png], result.map { |path| File.basename(path) })
      assert_raise(Retouch::Error) { Retouch.batch(sources, to: output) { |pipeline| pipeline } }
      assert_raise(ArgumentError) { Retouch.batch(sources, to: File.join(dir, "same.png")) { |pipeline| pipeline } }
      assert_raise(ArgumentError) { Retouch.batch(sources, to: output, jobs: 0) { |pipeline| pipeline } }
      single = File.join(dir, "single-{name}.png")
      assert_equal [File.join(dir, "single-a.png")], Retouch.batch(sources.first, to: single) { |pipeline| pipeline }
    end
  end

  test "optional Flipbook and Lookalike adapters round-trip and report diffs" do
    Dir.mktmpdir do |dir|
      gif = File.join(dir, "frames.gif")
      second = Tessel::Image.new(2, 2, fill: "#123456")
      Retouch::Operations.animate([sample_image, second], gif, fps: 10)
      assert_equal second[0, 0], Retouch::ImageIO.read(gif, frame: 1)[0, 0]
      assert_equal "GIF", Retouch.open(gif, frame: 1).info[:format]
      diff = Retouch::Operations.diff(sample_image, second)
      assert_operator diff.metadata.fetch("diff_pixels").to_i, :>, 0
      assert_equal 2, diff.width
      assert_raise(ArgumentError) { Retouch.open(gif, frame: -1) }
    end
  end

  test "CLI handles transformations, info, help, aggregate output, and exit codes" do
    Dir.mktmpdir do |dir|
      input = File.join(dir, "input.png")
      other = File.join(dir, "other.png")
      sample_image.write(input)
      Tessel::Image.new(2, 2, fill: "#123456").write(other)
      out = StringIO.new
      err = StringIO.new
      output = File.join(dir, "nested", "small.png")
      assert_equal 0, Retouch::CLI.run([input, "resize", "4x4!", "--filter", "nearest", "-o", output], out:, err:)
      assert_equal 4, Tessel.read(output).width
      assert_equal 1, Retouch::CLI.run([input, "invert", "-o", output], out:, err:)
      assert_equal 0, Retouch::CLI.run([input, "invert", "-o", output, "--force"], out:, err:)
      assert_equal 0, Retouch::CLI.run([input, "resize", "1x", "-o", File.join(dir, "dry.png"), "--dry-run"], out:, err:)
      assert_false File.exist?(File.join(dir, "dry.png"))
      info = StringIO.new
      assert_equal 0, Retouch::CLI.run(["info", input], out: info, err:)
      assert_equal "PNG", JSON.parse(info.string).fetch("format")
      assert_equal 0, Retouch::CLI.run(%w[help resize], out: info, err:)
      assert_include info.string, "GEOMETRY"
      assert_equal 0, Retouch::CLI.run([input, other, "montage", "--cols", "2", "-o", File.join(dir, "sheet.png")], out:, err:)
      assert_equal 4, Tessel.read(File.join(dir, "sheet.png")).width
      batch_template = File.join(dir, "batch-{name}.png")
      assert_equal 0, Retouch::CLI.run([input, other, "thumbnail", "1x", "-o", batch_template, "--jobs", "2", "--verbose"], out:, err:)
      assert File.file?(File.join(dir, "batch-input.png"))
      assert File.file?(File.join(dir, "batch-other.png"))
      assert_include out.string, "completed in"
      assert_equal 0, Retouch::CLI.run([input, other, "spritesheet", "-o", File.join(dir, "sprites.png")], out:, err:)
      assert File.file?(File.join(dir, "sprites.json"))
      assert_equal 0, Retouch::CLI.run(["diff", input, other, "-o", File.join(dir, "diff.png")], out:, err:)
      assert_equal 2, Retouch::CLI.run(["--level", "12"], out:, err:)
      assert_equal 2, Retouch::CLI.run([input, "resize"], out:, err:)
      assert_equal 2, Retouch::CLI.run([input, "unknown", "1x", "-o", output], out:, err:)
      assert_equal 2, Retouch::CLI.run(%w[help unknown], out:, err:)
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
