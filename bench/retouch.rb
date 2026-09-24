# frozen_string_literal: true

require "retouch"

def measure(name)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  puts format("%<name>s %<elapsed>.3fs", name:, elapsed:)
end

puts "YJIT: #{RubyVM::YJIT.enabled?}"
image = Tessel::Image.new(1920, 1080, fill: [80, 120, 160, 255])
measure("1920x1080 -> 960x540 bilinear") { Retouch::Operations.resize(image, "960x540", filter: :bilinear) }
measure("1920x1080 -> 960x540 lanczos3") { Retouch::Operations.resize(image, "960x540", filter: :lanczos3) }
measure("1920x1080 blur sigma=3") { Retouch::Operations.blur(image, sigma: 3) }
measure("1920x1080 brightness") { Retouch::Operations.brightness(image, 0.1) }
measure("256x256 -> 1024x1024 nearest") do
  Retouch::Operations.resize(Tessel::Image.new(256, 256), "400%", filter: :nearest)
end
