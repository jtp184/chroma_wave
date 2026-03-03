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
      # @param quiet_zone [Integer] number of empty modules around the QR code (default 4)
      # @return [self]
      # @raise [ArgumentError] if no sizing info is provided or error_correction is unknown
      # @raise [DependencyError] if rqrcode is not installed
      def draw_qr(data, x:, y:, module_size: nil, color: Color::BLACK, background: nil, # rubocop:disable Metrics/ParameterLists
                  error_correction: :medium, max_width: nil, max_height: nil, quiet_zone: 4)
        validate_quiet_zone!(quiet_zone)
        require_rqrcode!
        level = QR.resolve_level(error_correction)
        qr = ::RQRCode::QRCode.new(data, level: level)
        modules = qr.modules
        n = modules.length

        msize = resolve_module_size(module_size, n, max_width, max_height, quiet_zone)
        render_qr_background(x, y, n, msize, quiet_zone, background) if background
        render_qr_modules(x, y, modules, msize, quiet_zone, color)

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
        validate_text_font!(include_text, text_font)
        barcode = Barcode.build_barcode(symbology, data)
        encoding = barcode.encoding.is_a?(Array) ? barcode.encoding.join : barcode.encoding

        total_width = encoding.length * module_width
        render_barcode_background(x, y, total_width, height, background) if background
        render_barcode_bars(x, y, encoding, module_width, height, color)
        render_barcode_text(data, x, y + height + 2, total_width, text_font, color) if include_text

        self
      end

      private

      # Lazily requires rqrcode, raising DependencyError if not installed.
      #
      # @raise [DependencyError] if rqrcode cannot be loaded
      def require_rqrcode!
        QR.send(:require_rqrcode!)
      end

      # Resolves the effective module_size from explicit or auto-fit parameters.
      #
      # @param module_size [Integer, nil] explicit module size
      # @param n_modules [Integer] number of QR modules per side
      # @param max_width [Integer, nil] maximum width constraint
      # @param max_height [Integer, nil] maximum height constraint
      # @param quiet_zone [Integer] quiet zone module count per side
      # @return [Integer] resolved module size (>= 1)
      # @raise [ArgumentError] if no sizing info or module_size < 1
      def resolve_module_size(module_size, n_modules, max_width, max_height, quiet_zone)
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

        total_modules = n_modules + (2 * quiet_zone)
        candidates = []
        candidates << (max_width / total_modules) if max_width
        candidates << (max_height / total_modules) if max_height
        [candidates.min, 1].max
      end

      # Fills the QR background as a single rectangle including the quiet zone.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param n_modules [Integer] number of modules per side
      # @param msize [Integer] module pixel size
      # @param quiet_zone [Integer] quiet zone module count per side
      # @param color [Color] background color
      def render_qr_background(x, y, n_modules, msize, quiet_zone, color)
        total = (n_modules + (2 * quiet_zone)) * msize
        fill_rect(x, y, total, total, color)
      end

      # Renders dark QR modules as filled rectangles, offset by the quiet zone.
      #
      # @param x [Integer] top-left x
      # @param y [Integer] top-left y
      # @param modules [Array<Array<Boolean>>] 2D module matrix
      # @param msize [Integer] module pixel size
      # @param quiet_zone [Integer] quiet zone module count per side
      # @param color [Color] dark module color
      def render_qr_modules(x, y, modules, msize, quiet_zone, color)
        offset = quiet_zone * msize
        modules.each_with_index do |row, row_idx|
          row.each_with_index do |dark, col_idx|
            next unless dark

            fill_rect(x + offset + (col_idx * msize), y + offset + (row_idx * msize), msize, msize, color)
          end
        end
      end

      # Validates the quiet zone parameter.
      #
      # @param quiet_zone [Integer] quiet zone module count
      # @raise [ArgumentError] if quiet_zone is not a non-negative Integer
      def validate_quiet_zone!(quiet_zone)
        return if quiet_zone.is_a?(Integer) && quiet_zone >= 0

        raise ArgumentError, 'quiet_zone must be a non-negative Integer'
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

      # Validates that text_font is provided when include_text is true.
      #
      # @param include_text [Boolean] whether text is requested
      # @param text_font [Font, nil] the font for text rendering
      # @raise [ArgumentError] if include_text is true but text_font is nil
      def validate_text_font!(include_text, text_font)
        return unless include_text
        return unless text_font.nil?

        raise ArgumentError, 'text_font: is required when include_text: true'
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
