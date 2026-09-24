<div align="center">

# Retouch

Small Ruby image edits, from the terminal or a Ruby pipeline.

[![CI](https://github.com/rbgfx/retouch/actions/workflows/main.yml/badge.svg)](https://github.com/rbgfx/retouch/actions/workflows/main.yml)
[![Gem](https://img.shields.io/gem/v/retouch)](https://rubygems.org/gems/retouch)

</div>

Retouch handles everyday image cleanup without an ImageMagick install. It reads and writes PNG, PPM, and BMP through [Tessel](https://github.com/rbgfx/tessel). GIF input and GIF/APNG output, text rendering, and image diffs are available through optional [Flipbook](https://github.com/rbgfx/flipbook), [Glyphic](https://github.com/rbgfx/glyphic), and [Lookalike](https://github.com/rbgfx/lookalike) gems.

JPEG, WebP, color profiles, and very large photographic workloads are outside the current scope.

## Install

~~~sh
gem install retouch
~~~

Install optional integrations only when needed:

~~~sh
gem install flipbook glyphic lookalike
~~~

## CLI

~~~sh
retouch info screenshot.png
retouch screenshot.png resize 50% border 2 '#303846' -o small.png
retouch screenshot.png crop 800x600+120+40 text 'v1.2' --at south-east --font ./font.ttf -o crop.png
retouch sprite.png resize 400% --filter nearest -o sprite@4x.png
retouch 'shots/*.png' thumbnail 320x -o 'thumbs/{name}.png'
retouch 'frames/*.png' animate --fps 24 -o animation.gif
retouch a.png b.png c.png montage --cols 3 --gap 8 -o sheet.png
retouch diff expected.png actual.png -o diff.png
~~~

Resize geometry follows familiar ImageMagick-style notation, with intentionally limited semantics:

| Geometry | Result |
| --- | --- |
| 800x600 | Fit inside while preserving aspect ratio |
| 800x600! | Stretch to the exact dimensions |
| 800x600^ | Scale to cover, then crop |
| 800x / x600 | Set one dimension and preserve aspect ratio |
| 50% / 50%x25% | Scale relative to source size |
| 800x600> | Shrink only |
| 800x600+10+20 | Dimensions plus crop offset |

Supported resize filters are nearest, bilinear, bicubic, and lanczos3 (default). A crop without offsets starts at the top left; --gravity selects one of nine anchors for crop, cover, overlay, and text.

Use --dry-run, --verbose, --quiet, --force, --strip, --level 0..9, and --jobs N to control batch runs. Batch templates accept {name}, {ext}, {dir}, {index}, and {index:03}. Existing output files are preserved unless --force is used; conflicting templates fail before processing.

## Ruby

~~~ruby
require "retouch"

Retouch.open("screenshot.png")
  .resize("50%")
  .border(2, "#303846")
  .save("small.png")

image = Retouch.open("screenshot.png")
  .crop("800x600+120+40")
  .grayscale
  .to_image

Retouch.batch("shots/*.png", to: "thumbs/{name}.png") do |image|
  image.thumbnail("320x")
end
~~~

Pipelines defer work until to_image or save and never mutate the source image. Available operations are resize/thumbnail/crop, flip/flop/rotate, trim/pad/extend/border, grayscale/invert/brightness/contrast/gamma/saturate/tint/opacity/quantize, blur/sharpen/pixelate, overlay/watermark/text/rect/arrow, and multi-image montage/append/spritesheet/animate/diff.

Text requires a BDF or TrueType font path (font: or RETOUCH_FONT). Without Glyphic, only text reports a missing optional dependency. GIF/APNG and perceptual diff operations similarly report their optional gem when invoked.

Pure Ruby pixel processing trades speed for easy installation. Nearest-neighbor scaling is suitable for pixel art; Lanczos, blur, and arbitrary-angle rotation cost more as image dimensions grow. Retouch does not claim ImageMagick pixel-for-pixel compatibility.

On Ruby 4.0.6 with YJIT, a local run on a solid 1920×1080 image measured bilinear resize to 960×540 at 1.259s, Lanczos3 at 2.282s, Gaussian blur at σ=3 at 13.721s, and brightness at 0.180s. Nearest-neighbor enlargement from 256×256 to 1024×1024 took 0.072s. Treat these as reference measurements, not guarantees; Gaussian blur is currently the slow path.

## API contracts

Inputs are file paths or Tessel::Image values with RGBA8 pixels. Transformations return a new image and leave the input untouched. Geometry, option, and frame errors raise ArgumentError; values of the wrong type raise TypeError; I/O and unavailable optional integrations raise Retouch::Error. Pipeline#save overwrites its destination, while the CLI and Retouch.batch refuse existing outputs unless --force / force: true is supplied.

Retouch supports PNG, PPM, and BMP input/output. GIF input and GIF/APNG output need Flipbook; text and montage labels need Glyphic and a BDF/TrueType font; diff needs Lookalike. JPEG, WebP, color management, and APNG input are unsupported. Pipelines are safe to reuse from independent calls; Tessel image mutability follows Tessel's contract, and --jobs uses processes where fork exists.

## Development

~~~sh
bundle install
bundle exec rake verify
COVERAGE=1 COVERAGE_MIN=85 bundle exec rake test
~~~

The verification task runs RuboCop, test-unit, and RBS validation. The README Ruby examples are exercised by the test suite.

## License

MIT
