<h1 align="center">Retouch</h1>

<p align="center">A small Ruby image editor for PNG, PPM, and BMP.</p>

<p align="center">
  <a href="https://github.com/rbgfx/retouch/actions/workflows/main.yml"><img src="https://github.com/rbgfx/retouch/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby 3.1+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="MIT license"></a>
</p>

Retouch provides a small image-processing API and CLI backed by [Tessel](https://github.com/rbgfx/tessel). It runs in pure Ruby and is intended for screenshots, pixel art, and CI image tasks. JPEG, WebP, and color management are outside its current scope.

## Install

```sh
gem install retouch
```

Install optional integrations only when needed:

```sh
gem install glyphic   # text and montage labels
gem install flipbook -v '>= 0.3.0'  # GIF reading, GIF output, and APNG output
```

## Ruby API

Pipelines are lazy: each operation returns a new pipeline, and rendering starts at `to_image` or `save`.

```ruby
require "retouch"

Retouch.open("screenshot.png")
  .resize("640x")
  .brightness(8)
  .border(1, "#303846")
  .save("small.png")
```

Available operations include `resize`, `thumbnail`, `crop`, `trim`, `pad`, `extend`, `border`, `rotate`, `flip`, `flop`, `grayscale`, `invert`, `brightness`, `contrast`, `gamma`, `saturate`, `tint`, `opacity`, `quantize`, `blur`, `sharpen`, `pixelate`, `overlay`, `watermark`, `text`, `rect`, and `arrow`.

```ruby
image = Retouch.open("screen.png")
  .resize("800x")
  .overlay("logo.png", gravity: :south_east, opacity: 0.8, mode: :multiply)
  .text("Build passed", at: :north_west, size: 18, background: "#18202ddd")
image.save("annotated.png")
```

`brightness` adds a channel value from -255 to 255. `contrast` and `saturate` use 1 as unchanged; `gamma` also uses 1 as unchanged. `tint` takes `amount: 0..1`, and `opacity` takes a multiplier from 0 to 1. `quantize` accepts 2–256 colors and Tessel's `:none`, `:ordered`, or `:floyd_steinberg` dithering. `blur` and `sharpen` take a Gaussian sigma. `pixelate(size)` averages each size-by-size block.

GIF frames can be read as composited Tessel images:

```ruby
frames = Retouch.open_gif("animation.gif")
first_frame = Retouch.open_gif("animation.gif", frame: :first).to_image
```

Drawing and composite methods accept hex colors, including alpha (`#rrggbbaa`). Blend modes are `normal`, `multiply`, `screen`, `overlay`, `darken`, `lighten`, and `add`. `text` and `montage` labels need Glyphic; without it, those calls explain how to install the optional gem.

## CLI

```sh
retouch screen.png resize 640x --filter lanczos3 -o small.png
retouch screen.png grayscale contrast 1.1 -o adjusted.png
retouch screen.png crop 320x200+40+20 text "v1.2" --at south-east --size 18 -o crop.png
retouch base.png overlay logo.png --gravity south-east --opacity 0.8 -o marked.png
retouch a.png b.png c.png montage --cols 3 --gap 8 -o sheet.png
retouch a.png b.png append --direction horizontal -o row.png
retouch 'frames/*.png' animate --fps 24 -o preview.gif
retouch 'frames/*.png' animate --delay 0.08 -o preview.apng
retouch expected.png actual.png diff -o diff.png
retouch info screen.png
```

Quote a glob to let Retouch expand it. One-to-one processing accepts output templates and `--jobs`:

```sh
retouch 'screens/*.png' thumbnail 320x -o 'thumbs/{name}-{index:03}.png' --jobs 4
```

Templates support `{name}`, `{ext}`, `{dir}`, `{index}`, and zero-padded `{index:03}`. Duplicate output paths and accidental overwrites are rejected; use `--force` to replace existing files. Without `Process.fork`, jobs run sequentially. `spritesheet` writes a JSON sidecar with each image's coordinates and packs with a simple maximum-rectangles heuristic.

Geometry accepts `WIDTHxHEIGHT`, `WIDTHx`, `xHEIGHT`, percentages, `!` to stretch, `^` to cover, and `>` to shrink only. Crop offsets may be positive or negative. Resize filters are `nearest`, `bilinear`, `bicubic`, and `lanczos3`.

## How Retouch differs from ImageMagick

Retouch uses ImageMagick-style geometry as a familiar shorthand, but it does not implement the full ImageMagick command language or promise pixel-for-pixel compatibility. It is a small Ruby library and CLI built on Tessel, supports a narrower set of formats and operations, and does not provide JPEG/WebP codecs or color management. Choose ImageMagick when broad format support or mature photo-processing filters matter; choose Retouch for lightweight PNG-centered Ruby and CI workflows.

Global options include `--dry-run`, `--verbose`, `--quiet`, `--strip`, and `--level 0..9`. `retouch help OPERATION` shows that operation's syntax.

## Formats and limits

- PNG, PPM, and BMP input and output through Tessel.
- GIF input and GIF/APNG output through optional Flipbook 0.3.0 or newer. `animate` selects GIF or APNG from the output extension; `--fps` and `--delay` are mutually exclusive, and delay is in seconds.
- Multi-image `diff` compares RGBA channels exactly by default and returns a magenta diff image plus the changed-pixel ratio in the Ruby API.
- Large photographic images and high-quality arbitrary-angle rotation can be slow in pure Ruby. JPEG, WebP, and color-managed workflows are not supported.

On Ruby 4.0.6 with YJIT, the local benchmark measured a 1920×1080 Gaussian blur at σ=3 in 5.836 seconds, above the 3-second target. Results depend on Ruby and hardware; use `--verbose` to measure your own workload.

### Release order

Release in dependency order: Tessel 0.2.0 → Flipbook 0.3.0 → Retouch 0.2.0/0.3.0. Retouch keeps Flipbook optional, checks for version 0.3.0 when GIF/APNG features are called, and directs users to install that version. No Retouch release is included in this work.

## Development

```sh
bundle install
bundle exec rake verify
```

## License

MIT. See [LICENSE](LICENSE).
