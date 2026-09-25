# frozen_string_literal: true

require_relative "test_helper"

class FlipbookIntegrationTest < Test::Unit::TestCase
  test "Flipbook 0.3 reads GIF frames and writes GIF and APNG animations" do
    begin
      require "flipbook"
    rescue LoadError
      omit "optional flipbook >= 0.3.0 is not installed"
    end
    omit "flipbook >= 0.3.0 is required" if Gem::Version.new(Flipbook::VERSION) < Gem::Version.new("0.3.0")

    Dir.mktmpdir do |dir|
      red = Tessel::Image.new(2, 2, fill: "#ff0000")
      green = Tessel::Image.new(2, 2, fill: "#00ff00")
      gif = File.join(dir, "animation.gif")
      apng = File.join(dir, "animation.apng")

      Retouch::Operations.animate([red, green], gif, fps: 2)
      all_frames = Retouch.open_gif(gif)
      assert_equal 2, all_frames.length
      assert_equal [255, 0, 0, 255], all_frames[0][0, 0]
      assert_equal [0, 255, 0, 255], all_frames[1][0, 0]
      assert_equal [255, 0, 0, 255], Retouch.open_gif(gif, frame: :first).to_image[0, 0]
      assert_equal [0, 255, 0, 255], Retouch.open_gif(gif, frame: 1).to_image[0, 0]
      assert_equal "GIF", Retouch.open(gif).info[:format]

      Retouch::Operations.animate([red, green], apng, fps: 2)
      bytes = File.binread(apng)
      assert_equal Tessel::SIGNATURE, bytes.byteslice(0, 8)
      assert_include bytes, "acTL"
      assert_include bytes, "fdAT"

      first = File.join(dir, "first.png")
      second = File.join(dir, "second.png")
      cli_gif = File.join(dir, "cli.gif")
      red.write(first)
      green.write(second)
      assert_equal 0, Retouch::CLI.run([first, second, "animate", "--delay", "0.08", "--no-loop", "-o", cli_gif], out: StringIO.new, err: StringIO.new)
      assert_equal 2, Retouch.open_gif(cli_gif).length

      cli_apng = File.join(dir, "cli.apng")
      assert_equal 0, Retouch::CLI.run([first, second, "animate", "--fps", "12", "-o", cli_apng], out: StringIO.new, err: StringIO.new)
      assert_include File.binread(cli_apng), "acTL"

      invalid_err = StringIO.new
      assert_equal 2, Retouch::CLI.run([first, second, "animate", "--fps", "12", "--delay", "0.08", "-o", File.join(dir, "invalid.gif")], out: StringIO.new, err: invalid_err)
      assert_include invalid_err.string, "use either --fps or --delay"
    end
  end
end
