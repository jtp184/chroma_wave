# frozen_string_literal: true

module ChromaWave
  # Immutable drawing-style descriptor bundling stroke, fill, and stroke width.
  #
  # Built on +Data.define+ for structural equality, freezing, and pattern matching.
  # Colors are duck-typed — anything accepted by +set_pixel+ works.
  #
  # At least one of +stroke+ or +fill+ must be non-nil.
  #
  # @example
  #   Pen.stroke(Color::BLACK)                     # stroke only, width 1
  #   Pen.fill(Color::RED)                         # fill only
  #   Pen.new(stroke: Color::BLACK, fill: Color::RED, stroke_width: 2)
  Pen = Data.define(:stroke, :fill, :stroke_width) do
    # Initializes a Pen with stroke, fill, and stroke width.
    #
    # @param stroke [Object, nil] stroke color (or nil for no stroke)
    # @param fill [Object, nil] fill color (or nil for no fill)
    # @param stroke_width [Integer] stroke thickness (default: 1)
    # @raise [ArgumentError] if neither stroke nor fill is provided
    # @raise [ArgumentError] if stroke_width is not a positive Integer
    def initialize(stroke: nil, fill: nil, stroke_width: 1)
      raise ArgumentError, 'must provide at least one of stroke: or fill:' if stroke.nil? && fill.nil?

      unless stroke_width.is_a?(Integer) && stroke_width.positive?
        raise ArgumentError, 'stroke_width must be a positive Integer'
      end

      super
    end

    # Returns true if this pen has a stroke color.
    #
    # @return [Boolean]
    def stroke?
      !stroke.nil?
    end

    # Returns true if this pen has a fill color.
    #
    # @return [Boolean]
    def fill?
      !fill.nil?
    end

    # Returns a copy with fill stripped, keeping only stroke.
    #
    # Used by +draw_polygon+ when forwarding to +draw_polyline+.
    #
    # @return [Pen] a stroke-only copy
    # @raise [ArgumentError] if this pen has no stroke
    def stroke_only
      with(fill: nil)
    end
  end

  class << Pen
    # Creates a stroke-only Pen.
    #
    # @param color [Object] the stroke color
    # @param width [Integer] stroke thickness (default: 1)
    # @return [Pen]
    def stroke(color, width: 1)
      new(stroke: color, stroke_width: width)
    end

    # Creates a fill-only Pen.
    #
    # @param color [Object] the fill color
    # @return [Pen]
    def fill(color)
      new(fill: color)
    end
  end
end
