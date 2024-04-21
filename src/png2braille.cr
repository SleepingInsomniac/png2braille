require "png"
require "png/filter"
require "dot_display"

require "option_parser"

BLACK    = PNG::Gray(UInt8).new(0)
WHITE    = PNG::Gray(UInt8).new(255)
MAX_DIFF = BLACK.dist(WHITE)

NAME    = "png2braille"
VERSION = {{ `shards version`.chomp.stringify }}
USAGE   = "Usage: #{NAME} <path>"

struct Options
  property max_width : UInt32? = nil
  property invert : Bool = false
  property dither : Bool = true
  property threshold : Float64 = 0.5
end

options = Options.new

OptionParser.parse do |parser|
  parser.banner = USAGE

  parser.on("-v", "--version", "Show version") do
    puts "#{NAME} version #{VERSION}\nhttps://github.com/SleepingInsomniac/png2braille"
    exit(0)
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end

  parser.on("--max-width SIZE", "set the max width") do |size|
    options.max_width = size.to_u32
  end

  parser.on("--invert", "Invert the image") do
    options.invert = true
  end

  parser.on("--no-dither", "Skip dithering") do
    options.dither = false
  end

  parser.on("--threshold FLOAT", "Threshold for b/w (0.0 - 1.0) default: 0.5") do |value|
    options.threshold = value.to_f64
  end
end

if path = ARGV.pop?
  canvas = PNG.read(path)

  if max_width = options.max_width
    ratio = max_width / canvas.width
    width = (canvas.width * ratio).to_u32
    height = (canvas.height * ratio).to_u32
    canvas = canvas.resize_bilinear(width, height)
  end

  canvas = PNG::Filter.grayscale(canvas)

  if options.dither
    diffuse = Slice(Int16).new((canvas.width * canvas.height).to_i32) do |i|
      y, x = i.divmod(canvas.width)
      canvas[x, y][0].to_i16
    end

    canvas.height.times do |y|
      canvas.width.times do |x|
        i = y * canvas.width + x
        color = diffuse[i]
        new_color = color > 127u8 ? 255u8 : 0u8
        canvas[x, y] = new_color
        quant_error = color - new_color

        n = i + 1; diffuse[n] = (diffuse[n] + quant_error * 7 / 16).round.to_i16 if n < diffuse.size
        n = i + canvas.width - 1; diffuse[n] = (diffuse[n] + quant_error * 3 / 16).round.to_i16 if n < diffuse.size
        n = i + canvas.width; diffuse[n] = (diffuse[n] + quant_error * 5 / 16).round.to_i16 if n < diffuse.size
        n = i + canvas.width + 1; diffuse[n] = (diffuse[n] + quant_error * 1 / 16).round.to_i16 if n < diffuse.size
      end
    end
  end

  dots = DotDisplay.new(canvas.width, canvas.height)

  canvas.height.times do |y|
    canvas.width.times do |x|
      c = canvas.color(x, y)
      d = c.dist(BLACK)
      dots[x, y] = options.invert ? d > MAX_DIFF * options.threshold : d < MAX_DIFF * options.threshold
    end
  end

  puts dots.to_s
else
  STDERR.puts USAGE
  exit(1)
end
