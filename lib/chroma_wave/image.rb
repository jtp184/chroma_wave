# frozen_string_literal: true

module ChromaWave
  # Loads, transforms, and transfers images to Canvas via ruby-vips.
  #
  # ruby-vips is an optional dependency -- +Image+ raises +DependencyError+
  # with an install hint if it is not available.
  #
  # @example
  #   image = Image.load('photo.jpg')
  #   image = image.resize(width: 200)
  #   image.draw_onto(canvas, x: 10, y: 10)
  class Image
    attr_reader :width, :height

    # Loads an image from a file path.
    #
    # Normalizes the image to RGBA uint8 regardless of input format.
    #
    # @param path [String] path to image file (JPEG, PNG, WebP, etc.)
    # @return [Image]
    # @raise [DependencyError] if ruby-vips is not installed
    # @raise [Vips::Error] if the file cannot be loaded
    def self.load(path)
      require_vips!
      vips_image = ::Vips::Image.new_from_file(path.to_s, access: :sequential)
      new(ensure_rgba(vips_image))
    end

    # Loads an image from a binary buffer.
    #
    # @param data [String] raw image data (JPEG, PNG, etc.)
    # @param format [String] optional format hint (e.g. '.png')
    # @return [Image]
    # @raise [DependencyError] if ruby-vips is not installed
    def self.from_buffer(data, format: '')
      require_vips!
      vips_image = ::Vips::Image.new_from_buffer(data, format)
      new(ensure_rgba(vips_image))
    end

    # Returns a resized copy of this image preserving aspect ratio.
    #
    # When only one dimension is given, the other is calculated to
    # preserve the original aspect ratio.
    #
    # @param width [Integer, nil] target width
    # @param height [Integer, nil] target height
    # @return [Image] resized copy
    # @raise [ArgumentError] if neither width nor height is given
    def resize(width: nil, height: nil)
      raise ArgumentError, 'width or height required' unless width || height

      if width && height
        h_scale = width.to_f / self.width
        v_scale = height.to_f / self.height
        self.class.new(vips_image.resize(h_scale, vscale: v_scale))
      else
        scale = (width || height).to_f / (width ? self.width : self.height)
        self.class.new(vips_image.resize(scale))
      end
    end

    # Returns a cropped copy of this image.
    #
    # @param x [Integer] left edge
    # @param y [Integer] top edge
    # @param width [Integer] crop width
    # @param height [Integer] crop height
    # @return [Image]
    def crop(x:, y:, width:, height:)
      self.class.new(vips_image.crop(x, y, width, height))
    end

    # Bulk-transfers this image's RGBA pixels onto a Canvas.
    #
    # Uses +Canvas#load_rgba_bytes+ which delegates to the C accelerator
    # when available.
    #
    # @param canvas [Canvas] destination canvas
    # @param x [Integer] destination x offset
    # @param y [Integer] destination y offset
    # @return [Canvas] the destination canvas
    def draw_onto(canvas, x:, y:)
      canvas.load_rgba_bytes(to_rgba_bytes, width: width, height: height, x: x, y: y)
    end

    # Creates a new Canvas from this image.
    #
    # @return [Canvas] a canvas with this image's pixels
    def to_canvas
      Canvas.new(width: width, height: height).tap do |canvas|
        draw_onto(canvas, x: 0, y: 0)
      end
    end

    # Returns the raw RGBA pixel data as a binary string.
    #
    # @return [String] raw RGBA bytes (4 bytes per pixel, row-major)
    def to_rgba_bytes
      vips_image.write_to_memory
    end

    private

    attr_reader :vips_image

    # @param vips_image [Vips::Image] RGBA uint8 vips image
    def initialize(vips_image)
      @vips_image = vips_image
      @width = vips_image.width
      @height = vips_image.height
    end

    # Lazily requires ruby-vips, raising DependencyError if not installed.
    #
    # @raise [DependencyError] if ruby-vips cannot be loaded
    def self.require_vips!
      return if defined?(::Vips)

      require 'vips'
    rescue LoadError
      raise DependencyError,
            'ruby-vips is required for Image support. ' \
            'Install it with: gem install ruby-vips'
    end

    # Normalizes a vips image to 4-band RGBA uint8.
    #
    # Handles grayscale (1 band), grayscale+alpha (2 band),
    # RGB (3 band), RGBA (4 band), and CMYK inputs.
    #
    # @param img [Vips::Image] input image
    # @return [Vips::Image] RGBA uint8 image
    def self.ensure_rgba(img)
      img = img.icc_transform('srgb') if img.interpretation == :cmyk
      img = img.cast(:uchar) unless img.format == :uchar

      case img.bands
      when 1 then img.bandjoin([img, img, img.new_from_image(255)])
      when 2 then img[0].then { |grey| grey.bandjoin([grey, grey, img[1]]) }
      when 3 then img.bandjoin(img.new_from_image(255))
      when 4 then img
      else raise ArgumentError, "unsupported band count: #{img.bands}"
      end
    end

    private_class_method :new, :require_vips!, :ensure_rgba
  end
end
