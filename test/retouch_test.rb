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
    assert_equal [800, 600], Retouch::Geometry.parse("x600").target_size(400, 300)
    assert_equal [200, 50], Retouch::Geometry.parse("50%x25%").target_size(400, 200)
    geometry = Retouch::Geometry.parse("20x10-3+4")
    assert_equal [-3, 4], [geometry.offset_x, geometry.offset_y]
    assert_raise(ArgumentError) { Retouch::Geometry.parse("0x20") }
    assert_raise(ArgumentError) { Retouch::Geometry.parse("garbage") }
    assert_raise(ArgumentError) { Retouch::Geometry.parse("20x10+2") }
  end

  test "gravity covers all nine anchors and rejects unknown positions" do
    expected = {
      north_west: [0, 0], north: [40, 0], north_east: [80, 0],
      west: [0, 35], center: [40, 35], east: [80, 35],
      south_west: [0, 70], south: [40, 70], south_east: [80, 70]
    }
    expected.each { |gravity, offset| assert_equal offset, Retouch::Gravity.offset(100, 80, 20, 10, gravity) }
    assert_equal [0, 0], Retouch::Gravity.offset(100, 80, 20, 10, "north-west")
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

    checker = Tessel::Image.new(2, 2)
    checker[0, 0] = [0, 0, 0, 255]
    checker[1, 0] = [255, 255, 255, 255]
    checker[0, 1] = [255, 255, 255, 255]
    checker[1, 1] = [0, 0, 0, 255]
    average = Retouch.from_image(checker).resize("1x1", filter: :bilinear).to_image[0, 0]
    assert_equal [128, 128, 128, 255], average

    gradient = Tessel::Image.new(4, 1)
    [0, 64, 128, 192].each_with_index { |value, x| gradient[x, 0] = [value, value, value, 255] }
    downscaled_gradient = Retouch::Operations.resize(gradient, "2x1!", filter: :bilinear)
    assert_equal [40, 40, 40, 255], downscaled_gradient[0, 0]
    assert_equal [152, 152, 152, 255], downscaled_gradient[1, 0]
  end

  test "resampling uses normalized fixed-point weights and preserves RGBA output" do
    scale = Retouch::Operations::WEIGHT_SCALE
    %i[bilinear bicubic lanczos3].each do |filter|
      [[13, 5], [5, 13]].each do |source, target|
        weights = Retouch::Operations.send(:axis_weights, source, target, filter)
        weights.each do |taps|
          assert_equal scale, taps.sum(&:last)
          assert(taps.all? { |_, weight| weight.is_a?(Integer) })
        end
      end
    end

    image = Tessel::Image.new(3, 2)
    [[255, 10, 0, 255], [0, 255, 10, 192], [20, 40, 255, 64],
     [255, 0, 255, 0], [0, 0, 0, 128], [250, 220, 30, 255]].each_with_index do |pixel, i|
      image[i % 3, i / 3] = pixel
    end
    points = [[0, 0], [1, 1], [2, 1], [3, 2]]
    reference = {
      bilinear: [[255, 10, 0, 255], [83, 107, 4, 148], [77, 165, 32, 160], [250, 220, 30, 255]],
      bicubic: [[255, 1, 0, 255], [75, 122, 1, 149], [68, 172, 30, 162], [255, 244, 29, 255]],
      lanczos3: [[255, 0, 1, 255], [76, 128, 0, 149], [68, 176, 30, 164], [255, 253, 29, 255]]
    }
    reference.each do |filter, expected_pixels|
      output = Retouch::Operations.resize(image, "4x3!", filter:)
      actual_pixels = points.map { |x, y| output[x, y] }
      actual_pixels.zip(expected_pixels).each do |actual, expected|
        error = actual.zip(expected).map { |value, reference_value| (value - reference_value).abs }.max
        assert_operator error, :<=, 1, "#{filter} changed RGBA pixel by more than one level"
      end
    end

    gradient = Tessel::Image.new(13, 9)
    9.times do |y|
      13.times do |x|
        gradient[x, y] = [((47 * x) + (19 * y) + (13 * x * y)) % 256, ((31 * x) + (83 * y) + (7 * x * y)) % 256,
                          ((71 * x) + (37 * y) + (17 * x * y)) % 256, ((73 * x) + (101 * y) + (11 * x * y)) % 256]
      end
    end
    lanczos = Retouch::Operations.resize(gradient, "19x14!", filter: :lanczos3)
    assert_equal [5, 160, 167, 78], lanczos[14, 4]
  end

  test "shape operations preserve orientation, metadata, and padding" do
    image = sample_image
    assert_equal image[0, 0], Retouch::Operations.rotate(image, 90)[1, 0]
    assert_equal image[0, 0], Retouch::Operations.rotate(image, 180)[1, 1]
    rotated = Retouch::Operations.rotate(image, 30)
    assert_equal [3, 3], [rotated.width, rotated.height]
    center_pixel = Tessel::Image.new(3, 3)
    center_pixel[1, 1] = [255, 0, 0, 255]
    rotated_center = Retouch::Operations.rotate(center_pixel, 30)
    assert_equal [255, 0, 0, 255], rotated_center[2, 2]
    assert_equal image[1, 0], Retouch::Operations.flop(image)[0, 0]
    assert_equal image[0, 1], Retouch::Operations.flip(image)[0, 0]
    assert_equal image[1, 1], Retouch::Operations.crop(image, "1x1+1+1")[0, 0]
    assert_equal [4, 4], [Retouch::Operations.pad(image, 1).width, Retouch::Operations.pad(image, 1).height]
    assert_equal [4, 3], [Retouch::Operations.extend(image, 4, 3, gravity: :south_east).width, Retouch::Operations.extend(image, 4, 3).height]
    assert_equal [4, 4], [Retouch::Operations.border(image, 1).width, Retouch::Operations.border(image, 1).height]
    trim = Tessel::Image.new(3, 3, fill: "#ff0000")
    trim[1, 1] = [0, 0, 255, 255]
    assert_equal [1, 1], [Retouch::Operations.trim(trim).width, Retouch::Operations.trim(trim).height]
    fuzzy_trim = Tessel::Image.new(3, 1, fill: [10, 10, 10, 255])
    fuzzy_trim[1, 0] = [20, 20, 20, 255]
    fuzzy_trim[2, 0] = [11, 10, 10, 255]
    assert_equal [1, 1], [Retouch::Operations.trim(fuzzy_trim, fuzz: 1).width, Retouch::Operations.trim(fuzzy_trim, fuzz: 1).height]
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
      assert_equal 1, Retouch::CLI.run([input, "invert", "-o", output], out:, err:)
      assert_equal 4, Tessel.read(output).width
      quiet = StringIO.new
      assert_equal 0, Retouch::CLI.run([input, "invert", "-o", output, "--force", "--quiet"], out: quiet, err:)
      assert_empty quiet.string
      assert_equal 0, Retouch::CLI.run([input, "resize", "1x", "-o", File.join(dir, "dry.png"), "--dry-run"], out:, err:)
      assert_false File.exist?(File.join(dir, "dry.png"))
      verbose = StringIO.new
      assert_equal 0, Retouch::CLI.run([input, "grayscale", "-o", File.join(dir, "verbose.png"), "--verbose"], out: verbose, err:)
      assert_include verbose.string, "grayscale"
      info = StringIO.new
      assert_equal 0, Retouch::CLI.run(["info", input], out: info, err:)
      assert_equal "PNG", JSON.parse(info.string).fetch("format")
      help = StringIO.new
      assert_equal 0, Retouch::CLI.run(["--help"], out: help, err:)
      assert_include help.string, "Usage: retouch INPUT"
      assert_equal 0, Retouch::CLI.run(%w[help resize], out:, err:)
      assert_include out.string, "resize GEOMETRY"
      assert_equal 2, Retouch::CLI.run([input, "unknown", "1x", "-o", output], out:, err:)
      assert_equal 2, Retouch::CLI.run([input, "resize", "1x"], out:, err:)
      assert_equal 2, Retouch::CLI.run([input, File.join(dir, "other.png"), "resize", "1x", "-o", output], out:, err:)
    end
  end

  test "color operations preserve alpha and apply deterministic LUTs" do
    image = Tessel::Image.new(2, 1)
    image[0, 0] = [255, 0, 0, 128]
    image[1, 0] = [20, 40, 60, 255]
    image.metadata["source"] = "test"

    assert_equal [54, 54, 54, 128], Retouch::Operations.grayscale(image)[0, 0]
    assert_equal [0, 255, 255, 128], Retouch::Operations.invert(image)[0, 0]
    assert_equal [30, 50, 70, 255], Retouch::Operations.brightness(image, 10)[1, 0]
    assert_equal [255, 0, 0, 64], Retouch::Operations.opacity(image, 0.5)[0, 0]
    assert_equal [255, 0, 0, 128], Retouch::Operations.tint(image, "#0000ff", amount: 0)[0, 0]
    assert_equal "test", Retouch::Operations.gamma(image, 1).metadata.fetch("source")
    assert_equal [54, 54, 54, 255], Retouch::Operations.saturate(Tessel::Image.new(1, 1, fill: "#ff0000"), 0)[0, 0]
    assert_equal [128, 128, 128, 255], Retouch::Operations.contrast(Tessel::Image.new(1, 1, fill: "#ff0000"), 0)[0, 0]
    assert_equal [181, 181, 181, 255], Retouch::Operations.gamma(Tessel::Image.new(1, 1, fill: "#808080"), 2)[0, 0]
    assert_equal [1, 129, 255, 255], Retouch::Operations.contrast(Tessel::Image.new(1, 1, fill: [64, 128, 192, 255]), 2)[0, 0]
    assert_equal [128, 0, 128, 128], Retouch::Operations.tint(image, "#0000ff", amount: 0.5)[0, 0]
    assert_raise(ArgumentError) { Retouch::Operations.gamma(image, 0) }
  end

  test "quantize uses Tessel palettes and preserves source alpha" do
    image = Tessel::Image.new(3, 1)
    image[0, 0] = [10, 10, 10, 255]
    image[1, 0] = [240, 240, 240, 128]
    image[2, 0] = [90, 100, 110, 0]
    result = Retouch::Operations.quantize(image, colors: 2, dither: :none)

    assert_equal([255, 128, 0], 3.times.map { |x| result[x, 0][3] })
    assert_operator Tessel::Quantize.palette_for(result, colors: 2).length, :<=, 2
    %i[ordered floyd_steinberg].each do |dither|
      assert_instance_of Tessel::Image, Retouch::Operations.quantize(image, colors: 2, dither:)
    end
    assert_raise(ArgumentError) { Retouch::Operations.quantize(image, colors: 1) }
  end

  test "blur, sharpen, and pixelate preserve dimensions and transparent edges" do
    solid = Tessel::Image.new(3, 3, fill: "#336699")
    blurred = Retouch::Operations.blur(solid, 1)
    assert_equal [3, 3], [blurred.width, blurred.height]
    assert_equal [51, 102, 153, 255], blurred[1, 1]
    assert_equal solid.bytes, Retouch::Operations.sharpen(solid, 1, amount: 0).bytes
    edge = Tessel::Image.new(5, 1)
    [0, 0, 128, 255, 255].each_with_index { |value, x| edge[x, 0] = [value, value, value, 255] }
    sharpened = Retouch::Operations.sharpen(edge, 1)
    assert_equal [0, 255], [sharpened[1, 0][0], sharpened[3, 0][0]]

    blocks = Tessel::Image.new(3, 2)
    3.times { |x| 2.times { |y| blocks[x, y] = [x * 100, y * 100, 0, 255] } }
    pixelated = Retouch::Operations.pixelate(blocks, 2)
    assert_equal [50, 50, 0, 255], pixelated[0, 0]
    assert_equal pixelated[0, 0], pixelated[1, 1]
    assert_equal [200, 50, 0, 255], pixelated[2, 0]
    assert_equal blocks.bytes, Retouch::Operations.pixelate(blocks, 1).bytes
    transparent_edge = Tessel::Image.new(2, 1)
    transparent_edge[0, 0] = [255, 0, 0, 0]
    transparent_edge[1, 0] = [0, 0, 255, 255]
    assert_equal [0, 0, 255, 128], Retouch::Operations.pixelate(transparent_edge, 2)[0, 0]
    assert_equal [0, 0, 255], Retouch::Operations.blur(transparent_edge, 1)[0, 0].first(3)
    assert_raise(ArgumentError) { Retouch::Operations.blur(blocks, 0) }
  end

  test "composites use source-over alpha and drawing clips to the image" do
    background = Tessel::Image.new(2, 2, fill: "#0000ff")
    source = Tessel::Image.new(1, 1, fill: [255, 0, 0, 128])
    combined = Retouch::Operations.overlay(background, source, x: 0, y: 0)
    assert_equal [128, 0, 127, 255], combined[0, 0]
    assert_equal [0, 0, 255, 255], combined[1, 1]
    assert_equal [0, 0, 255, 255], Retouch::Operations.overlay(background, source, opacity: 0)[1, 1]
    assert_equal [0, 0, 127, 255], Retouch::Operations.overlay(background, source, x: 0, y: 0, mode: :multiply)[0, 0]
    %i[normal multiply screen overlay darken lighten add].each do |mode|
      assert_instance_of Tessel::Image, Retouch::Operations.overlay(background, source, mode:)
    end
    transparent_background = Tessel::Image.new(2, 2)
    anchored = Retouch::Operations.overlay(transparent_background, source, gravity: :south_east)
    assert_equal [255, 0, 0, 128], anchored[1, 1]
    assert_equal [0, 0, 0, 0], anchored[0, 0]

    outlined = Retouch::Operations.rect(Tessel::Image.new(5, 5), 1, 1, 3, 3, "#ffffff")
    assert_equal [255, 255, 255, 255], outlined[1, 1]
    assert_equal [0, 0, 0, 0], outlined[2, 2]
    filled = Retouch::Operations.rect(Tessel::Image.new(3, 3), 0, 0, 2, 2, "#ffffff", fill: true)
    assert_equal [255, 255, 255, 255], filled[1, 1]
    assert_equal [0, 0, 0, 0], filled[2, 2]
    arrow = Retouch::Operations.arrow(Tessel::Image.new(5, 3), 0, 1, 4, 1, "#ffffff", head: 0)
    assert_equal [255, 255, 255, 255], arrow[2, 1]
    assert_raise(ArgumentError) { Retouch::Operations.overlay(background, source, mode: :unknown) }
  end

  test "multi-image operations return layouts and exact diff ratios" do
    red = Tessel::Image.new(2, 1, fill: "#ff0000")
    green = Tessel::Image.new(1, 2, fill: "#00ff00")
    vertical = Retouch::Operations.append([red, green], gap: 1, background: "#000000")
    assert_equal [2, 4], [vertical.width, vertical.height]
    assert_equal [255, 0, 0, 255], vertical[0, 0]
    horizontal = Retouch::Operations.append([red, green], direction: :horizontal)
    assert_equal [3, 2], [horizontal.width, horizontal.height]
    montage = Retouch::Operations.montage([red, green], columns: 2, gap: 1)
    assert_equal [4, 2], [montage.width, montage.height]
    sheet, cells = Retouch::Operations.spritesheet([red, green], max_width: 3, gap: 1)
    assert_equal([[0, 0], [0, 2]], cells.map { |cell| [cell[:x], cell[:y]] })
    assert_equal [2, 4], [sheet.width, sheet.height]
    atlas_images = [Tessel::Image.new(2, 2, fill: "#111111"), Tessel::Image.new(1, 1, fill: "#222222"), Tessel::Image.new(2, 1, fill: "#333333")]
    atlas, atlas_cells = Retouch::Operations.spritesheet(atlas_images, max_width: 3)
    assert_equal [3, 3], [atlas.width, atlas.height]
    atlas_cells.combination(2) do |left, right|
      assert_false(left[:x] < right[:x] + right[:width] && right[:x] < left[:x] + left[:width] && left[:y] < right[:y] + right[:height] && right[:y] < left[:y] + left[:height])
    end

    changed = red.dup
    changed[1, 0] = "#0000ff"
    difference = Retouch::Operations.diff(red, changed)
    assert_equal 1, difference[:pixels]
    assert_equal 0.5, difference[:rate]
    assert_equal [0, 0, 0, 0], difference[:image][0, 0]
    assert_equal [255, 0, 255, 255], difference[:image][1, 0]
    assert_equal 0, Retouch::Operations.diff(red, changed, threshold: 255)[:pixels]
    assert_equal 1, Retouch::Operations.diff(red, changed, threshold: 254)[:pixels]
    assert_raise(ArgumentError) { Retouch::Operations.diff(red, changed, threshold: 256) }
    assert_raise(ArgumentError) { Retouch::Operations.diff(red, green) }
  end

  test "batch expands templates, prevents collisions, and writes in parallel" do
    Dir.mktmpdir do |dir|
      first = File.join(dir, "a.png")
      second = File.join(dir, "b.png")
      sample_image.write(first)
      sample_image.write(second)
      template = File.join(dir, "out", "{name}-{index:02}.png")
      outputs = Retouch.batch([first, second], to: template, jobs: 2, &:grayscale)

      assert_equal(["a-00.png", "b-01.png"], outputs.map { |path| File.basename(path) })
      assert_equal 54, Retouch.open(outputs.first).to_image[0, 0][0]
      assert_raise(Retouch::Error) { Retouch.batch([first, second], to: File.join(dir, "same.png")) { |pipeline| pipeline } }
      assert_equal [first, second], Retouch::Batch.expand([first, second])
      assert_equal "a-007.png", File.basename(Retouch::Batch.output_path("{name}-{index:03}.png", first, 7))
    end
  end

  test "CLI supports color operations, multi-image output, and batch templates" do
    Dir.mktmpdir do |dir|
      first = File.join(dir, "one.png")
      second = File.join(dir, "two.png")
      sample_image.write(first)
      sample_image.write(second)
      out = StringIO.new
      err = StringIO.new
      color_output = File.join(dir, "gray.png")
      assert_equal 0, Retouch::CLI.run([first, "grayscale", "-o", color_output], out:, err:)
      assert_equal Tessel.read(color_output)[0, 0][0], Tessel.read(color_output)[0, 0][1]

      appended = File.join(dir, "append.png")
      assert_equal 0, Retouch::CLI.run([first, second, "append", "--direction", "horizontal", "-o", appended], out:, err:)
      assert_equal 4, Tessel.read(appended).width

      difference = File.join(dir, "diff.png")
      assert_equal 0, Retouch::CLI.run([first, second, "diff", "-o", difference], out:, err:)
      assert_true File.file?(difference)

      atlas = File.join(dir, "atlas.png")
      assert_equal 0, Retouch::CLI.run([first, second, "spritesheet", "--max-width", "4", "-o", atlas], out:, err:)
      assert_true File.file?(atlas)
      assert_true File.file?(File.join(dir, "atlas.json"))
      placements = JSON.parse(File.read(File.join(dir, "atlas.json")))
      indices = placements.map { |item| item.fetch("index") }
      assert_equal [0, 1], indices

      batch_template = File.join(dir, "thumbs", "{name}.png")
      assert_equal 0, Retouch::CLI.run([File.join(dir, "*.png"), "thumbnail", "1x", "-o", batch_template], out:, err:)
      assert_true File.file?(File.join(dir, "thumbs", "one.png"))
    end
  end

  test "CLI protects the actual spritesheet manifest path from overwrites" do
    Dir.mktmpdir do |dir|
      first = File.join(dir, "one.png")
      second = File.join(dir, "two.png")
      output = File.join(dir, "atlas.png")
      manifest = File.join(dir, "atlas.json")
      sample_image.write(first)
      sample_image.write(second)
      File.write(manifest, "keep")
      err = StringIO.new

      assert_equal 1, Retouch::CLI.run([first, second, "spritesheet", "-o", output], out: StringIO.new, err: err)
      assert_include err.string, "refusing to overwrite #{manifest}"
      assert_equal "keep", File.read(manifest)
      assert_false File.exist?(output)
    end
  end

  test "optional integrations fail with actionable errors" do
    begin
      require "flipbook"
    rescue LoadError
      assert_raise(Retouch::Error) { Retouch::Operations.animate([sample_image, sample_image], "unused.gif") }
      assert_raise(Retouch::Error) { Retouch.open_gif("unused.gif") }
    end
    begin
      require "glyphic"
    rescue LoadError
      assert_raise(Retouch::Error) { Retouch.from_image(sample_image).text("A").to_image }
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
