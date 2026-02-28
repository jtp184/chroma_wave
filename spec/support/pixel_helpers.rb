# frozen_string_literal: true

# Shared helpers for pixel-level assertions on Canvas surfaces.
module PixelHelpers
  # Counts the number of non-white pixels on a canvas.
  #
  # @param canvas [ChromaWave::Canvas] the canvas to inspect
  # @return [Integer] count of pixels that are not Color::WHITE
  def count_non_white(canvas)
    count = 0
    canvas.width.times do |x|
      canvas.height.times do |y|
        count += 1 unless canvas.get_pixel(x, y) == ChromaWave::Color::WHITE
      end
    end
    count
  end

  # Returns true if any pixel is neither black nor white (i.e. anti-aliased).
  #
  # @param canvas [ChromaWave::Canvas] the canvas to inspect
  # @return [Boolean]
  def has_grey_pixel?(canvas)
    canvas.width.times do |x|
      canvas.height.times do |y|
        pixel = canvas.get_pixel(x, y)
        return true unless [ChromaWave::Color::WHITE, ChromaWave::Color::BLACK].include?(pixel)
      end
    end
    false
  end

  # Returns true if any non-white pixel exists below min_y.
  #
  # @param canvas [ChromaWave::Canvas] the canvas to inspect
  # @param min_y [Integer] minimum y coordinate to check
  # @return [Boolean]
  def has_lower_pixel?(canvas, min_y)
    canvas.width.times do |x|
      (min_y...canvas.height).each do |y|
        return true unless canvas.get_pixel(x, y) == ChromaWave::Color::WHITE
      end
    end
    false
  end

  # Returns the x coordinate of the first non-white pixel.
  #
  # @param canvas [ChromaWave::Canvas] the canvas to inspect
  # @return [Integer] x coordinate, or canvas.width if all white
  def first_non_white_x(canvas)
    canvas.width.times do |x|
      canvas.height.times do |y|
        return x unless canvas.get_pixel(x, y) == ChromaWave::Color::WHITE
      end
    end
    canvas.width
  end
end
