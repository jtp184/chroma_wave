# frozen_string_literal: true

module ChromaWave
  # Immutable measurement result for a block of rendered text.
  #
  # Returned by {Font#measure} with the pixel dimensions and vertical
  # extents of the measured string at the font's current size.
  #
  # @example
  #   metrics = font.measure('Hello, world!')
  #   metrics.width   #=> 142
  #   metrics.height  #=> 19
  #   metrics.ascent  #=> 15
  #   metrics.descent #=> 4
  TextMetrics = Data.define(:width, :height, :ascent, :descent)
end
