# frozen_string_literal: true

module ChromaWave
  module Drawing
    # QR code and barcode rendering mixin for {Surface}.
    #
    # Provides +draw_qr+ and +draw_barcode+ methods that compose on
    # +fill_rect+ (from {Drawing::Primitives}) so they work on any
    # surface type. The +include_text+ option for barcodes requires
    # +draw_text+ (Canvas/Layer only).
    #
    # Both methods return +self+ for chaining.
    module Codes
      # Maps user-facing symbology symbols to Barby class name strings.
      SYMBOLOGY_MAP = {
        code128: 'Barby::Code128',
        ean13: 'Barby::EAN13',
        ean8: 'Barby::EAN8',
        code39: 'Barby::Code39'
      }.freeze

      # Maps symbology symbols to their require paths.
      SYMBOLOGY_REQUIRES = {
        code128: 'barby/barcode/code_128',
        ean13: 'barby/barcode/ean_13',
        ean8: 'barby/barcode/ean_8',
        code39: 'barby/barcode/code_39'
      }.freeze

      # Draws a QR code onto this surface.
      #
      # Each dark module is rendered as a filled square via +fill_rect+.
      # Sizing can be explicit (+module_size+) or auto-fit
      # (+max_width+ / +max_height+).
      #
      # @param data [String] the data to encode
      # @param x [Integer] top-left x coordinate
      # @param y [Integer] top-left y coordinate
      # @param module_size [Integer, nil] pixel size per QR module (overrides max_width/max_height)
      # @param color [Color] dark module color
      # @param background [Color, nil] background color (nil = transparent)
      # @param error_correction [Symbol] +:low+, +:medium+, +:quartile+, or +:high+
      # @param max_width [Integer, nil] maximum width for auto-fit
      # @param max_height [Integer, nil] maximum height for auto-fit
      # @return [self]
      # @raise [ArgumentError] if no sizing info is provided or error_correction is unknown
      # @raise [DependencyError] if rqrcode is not installed
      def draw_qr(data, x:, y:, module_size: nil, color: Color::BLACK, background: nil, # rubocop:disable Metrics/ParameterLists
                  error_correction: :medium, max_width: nil, max_height: nil)
        QR.send(:require_rqrcode!)
        level = QR.resolve_level(error_correction)
        qr = ::RQRCode::QRCode.new(data, level: level)
        modules = qr.modules
        n = modules.length

        msize = resolve_module_size(module_size, n, max_width, max_height)
        render_qr_background(x, y, n, msize, background) if background
        render_qr_modules(x, y, modules, msize, color)

        self
      end

      # Draws a 1D barcode onto this surface.
      #
      # Bar runs are rendered via +fill_rect+. When +include_text+ is true,
      # the data string is centered below the bars via +draw_text+ (Canvas/Layer
      # only — raises on Framebuffer).
      #
      # @param data [String] the data to encode
      # @param x [Integer] top-left x coordinate
      # @param y [Integer] top-left y coordinate
      # @param symbology [Symbol] +:code128+, +:ean13+, +:ean8+, or +:code39+
      # @param height [Integer] bar height in pixels
      # @param module_width [Integer] pixel width per narrow bar
      # @param color [Color] bar color
      # @param background [Color, nil] background color (nil = transparent)
      # @param include_text [Boolean] render data text below bars
      # @param text_font [Font, nil] font for text (required if include_text)
      # @return [self]
      # @raise [ArgumentError] if symbology is unknown or include_text on a non-text surface
      # @raise [DependencyError] if barby is not installed
      def draw_barcode(data, x:, y:, symbology:, height: 60, module_width: 2, # rubocop:disable Metrics/ParameterLists
                       color: Color::BLACK, background: nil, include_text: true,
                       text_font: nil)
        validate_text_capable!(include_text)
        barcode = build_barcode(symbology, data)
        encoding = barcode.encoding.is_a?(Array) ? barcode.encoding.join : barcode.encoding

        total_width = encoding.length * module_width
        render_barcode_background(x, y, total_width, height, background) if background
        render_barcode_bars(x, y, encoding, module_width, height, color)
        render_barcode_text(data, x, y + height + 2, total_width, text_font, color) if include_text

        self
      end

      private

      # Resolves the effective module_size from explicit or auto-fit parameters.
      #
      # @param module_size [Integer, nil] explicit module size
      # @param n_modules [Integer] number of QR modules per side
      # @param max_width [Integer, nil] maximum width constraint
      # @param max_height [Integer, nil] maximum height constraint
      # @return [Integer] resolved module size (>= 1)
      # @raise [ArgumentError] if no sizing info or module_size < 1
      def resolve_module_size(module_size, n_modules, max_width, max_height)
        if module_size
          unless module_size.is_a?(Integer) && module_size >= 1
            raise ArgumentError,
                  'module_size must be a positive Integer'
          end

          return module_size
        end

        unless max_width || max_height
          raise ArgumentError,
                'provide module_size: or max_width:/max_height: to size the QR code'
        end

        candidates = []
        candidates << (max_width / n_modules) if max_width
        candidates << (max_height / n_modules) if max_height
        [candidates.min, 1].max
      end

      # Fills the QR background as a single rectangle.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param n_modules [Integer] number of modules per side
      # @param msize [Integer] module pixel size
      # @param color [Color] background color
      def render_qr_background(x, y, n_modules, msize, color)
        total = n_modules * msize
        fill_rect(x, y, total, total, color)
      end

      # Renders dark QR modules as filled rectangles.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param modules [Array<Array<Boolean>>] 2D module matrix
      # @param msize [Integer] module pixel size
      # @param color [Color] dark module color
      def render_qr_modules(x, y, modules, msize, color)
        modules.each_with_index do |row, row_idx|
          row.each_with_index do |dark, col_idx|
            next unless dark

            fill_rect(x + (col_idx * msize), y + (row_idx * msize), msize, msize, color)
          end
        end
      end

      # Lazily requires barby, raising DependencyError if not installed.
      #
      # @raise [DependencyError] if barby cannot be loaded
      def require_barby!
        return if defined?(::Barby)

        require 'barby'
      rescue LoadError
        raise DependencyError,
              'barby is required for barcode support. ' \
              'Install it with: gem install barby'
      end

      # Validates that this surface supports text rendering.
      #
      # @param include_text [Boolean] whether text is requested
      # @raise [ArgumentError] if text is requested but surface lacks draw_text
      def validate_text_capable!(include_text)
        return unless include_text
        return if respond_to?(:draw_text)

        raise ArgumentError,
              'include_text: true requires draw_text (available on Canvas and Layer, not Framebuffer)'
      end

      # Builds a Barby barcode instance for the given symbology and data.
      #
      # @param symbology [Symbol] symbology key
      # @param data [String] data to encode
      # @return [Barby::Barcode] the barcode instance
      # @raise [ArgumentError] if symbology is unknown
      def build_barcode(symbology, data)
        require_barby!
        klass_name = SYMBOLOGY_MAP.fetch(symbology) do
          raise ArgumentError, "unknown symbology: #{symbology.inspect} " \
                               "(expected #{SYMBOLOGY_MAP.keys.map(&:inspect).join(', ')})"
        end

        require SYMBOLOGY_REQUIRES.fetch(symbology)
        Object.const_get(klass_name).new(data)
      end

      # Fills the barcode background as a single rectangle.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param total_width [Integer] total barcode width in pixels
      # @param height [Integer] bar height
      # @param color [Color] background color
      def render_barcode_background(x, y, total_width, height, color)
        fill_rect(x, y, total_width, height, color)
      end

      # Renders barcode bars using run-length scanning.
      #
      # Scans the encoding string for consecutive '1' runs and emits
      # one +fill_rect+ per run. O(n) over encoding length.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param encoding [String] binary encoding string ('1'/'0')
      # @param module_width [Integer] pixel width per module
      # @param height [Integer] bar height
      # @param color [Color] bar color
      def render_barcode_bars(x, y, encoding, module_width, height, color)
        run_start = nil

        encoding.each_char.with_index do |ch, i|
          if ch == '1'
            run_start ||= i
          elsif run_start
            run_len = i - run_start
            fill_rect(x + (run_start * module_width), y, run_len * module_width, height, color)
            run_start = nil
          end
        end

        # Flush trailing run
        return unless run_start

        run_len = encoding.length - run_start
        fill_rect(x + (run_start * module_width), y, run_len * module_width, height, color)
      end

      # Renders the data text centered below the barcode bars.
      #
      # @param data [String] the original data string
      # @param x [Integer] barcode top-left x
      # @param text_y [Integer] y coordinate for the text baseline
      # @param total_width [Integer] total barcode width for centering
      # @param font [Font, nil] text font
      # @param color [Color] text color
      def render_barcode_text(data, x, text_y, total_width, font, color)
        draw_text(data, x: x, y: text_y, font: font, color: color,
                        align: :center, max_width: total_width)
      end
    end
  end
end

# Include code rendering into Surface so all surfaces can draw QR/barcodes.
ChromaWave::Surface.include(ChromaWave::Drawing::Codes)
