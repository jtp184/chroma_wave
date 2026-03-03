# frozen_string_literal: true

RSpec.describe 'Dirty region tracking' do # rubocop:disable RSpec/DescribeClass
  let(:white) { ChromaWave::Color::WHITE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:red)   { ChromaWave::Color::RED }

  describe 'Canvas dirty state' do
    subject(:canvas) { ChromaWave::Canvas.new(width: 100, height: 50) }

    describe '#dirty? on a fresh canvas' do
      it 'returns false' do
        expect(canvas).not_to be_dirty
      end
    end

    describe '#dirty_region on a fresh canvas' do
      it 'returns nil' do
        expect(canvas.dirty_region).to be_nil
      end
    end

    describe '#set_pixel' do
      it 'marks the canvas dirty' do
        canvas.set_pixel(10, 20, black)
        expect(canvas).to be_dirty
      end

      it 'tracks a single-pixel dirty region' do
        canvas.set_pixel(10, 20, black)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 10, y: 20, width: 1, height: 1))
      end

      it 'does not mark dirty for out-of-bounds pixels' do
        canvas.set_pixel(-1, 0, black)
        canvas.set_pixel(100, 0, black)
        expect(canvas).not_to be_dirty
      end
    end

    describe '#clear' do
      it 'marks the entire canvas dirty' do
        canvas.clear(black)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 0, y: 0, width: 100, height: 50))
      end
    end

    describe '#fill_rect' do
      it 'marks the filled region dirty (clipped)' do
        canvas.fill_rect(10, 20, 30, 15, black)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 10, y: 20, width: 30, height: 15))
      end

      it 'clips the dirty region to canvas bounds' do
        canvas.fill_rect(-5, -5, 20, 20, black)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 0, y: 0, width: 15, height: 15))
      end

      it 'does not mark dirty when rect is fully out of bounds' do
        canvas.fill_rect(200, 200, 10, 10, black)
        expect(canvas).not_to be_dirty
      end
    end

    describe '#blit' do
      it 'marks the blit region dirty' do
        src = ChromaWave::Canvas.new(width: 20, height: 10, background: red)
        canvas.blit(src, x: 5, y: 5)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 5, y: 5, width: 20, height: 10))
      end

      it 'clips the dirty region for negative offsets' do
        src = ChromaWave::Canvas.new(width: 10, height: 10, background: red)
        canvas.blit(src, x: -3, y: -3)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 0, y: 0, width: 7, height: 7))
      end

      it 'clips the dirty region at canvas bounds' do
        src = ChromaWave::Canvas.new(width: 20, height: 20, background: red)
        canvas.blit(src, x: 90, y: 40)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 90, y: 40, width: 10, height: 10))
      end
    end

    describe '#load_rgba_bytes' do
      it 'marks the loaded region dirty' do
        bytes = (black.to_rgba_bytes * 12) # 4x3
        canvas.load_rgba_bytes(bytes, width: 4, height: 3, x: 10, y: 20)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 10, y: 20, width: 4, height: 3))
      end
    end

    describe '#blit_glyph' do
      it 'marks the glyph region dirty' do
        bitmap = "\xFF\xFF\xFF\xFF".b # 2x2 fully opaque
        canvas.blit_glyph(bitmap, x: 5, y: 5, width: 2, height: 2, color: black)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 5, y: 5, width: 2, height: 2))
      end
    end

    describe 'dirty region expansion' do
      it 'expands to union of all mutations' do
        canvas.set_pixel(10, 10, black)
        canvas.set_pixel(50, 40, black)
        region = canvas.dirty_region
        expect(region.x).to eq(10)
        expect(region.y).to eq(10)
        expect(region.width).to eq(41)  # 50 - 10 + 1
        expect(region.height).to eq(31) # 40 - 10 + 1
      end

      it 'expands for fill_rect after set_pixel' do
        canvas.set_pixel(0, 0, black)
        canvas.fill_rect(80, 30, 10, 10, red)
        region = canvas.dirty_region
        expect(region.x).to eq(0)
        expect(region.y).to eq(0)
        expect(region.width).to eq(90)  # 80 + 10
        expect(region.height).to eq(40) # 30 + 10
      end
    end

    describe '#clean!' do
      it 'resets dirty state' do
        canvas.set_pixel(10, 10, black)
        expect(canvas).to be_dirty

        canvas.clean!
        expect(canvas).not_to be_dirty
        expect(canvas.dirty_region).to be_nil
      end

      it 'returns self for chaining' do
        expect(canvas.clean!).to equal(canvas)
      end

      it 'allows dirty tracking to restart after cleaning' do
        canvas.set_pixel(10, 10, black)
        canvas.clean!
        canvas.set_pixel(50, 40, red)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 50, y: 40, width: 1, height: 1))
      end
    end

    describe '#mark_dirty' do
      it 'marks an arbitrary rect dirty with keywords' do
        canvas.mark_dirty(x: 5, y: 10, width: 20, height: 15)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 5, y: 10, width: 20, height: 15))
      end

      it 'accepts a Rect object' do
        rect = ChromaWave::Rect.new(x: 3, y: 7, width: 12, height: 8)
        canvas.mark_dirty(rect)
        expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 3, y: 7, width: 12, height: 8))
      end

      it 'returns self for chaining' do
        expect(canvas.mark_dirty(x: 0, y: 0, width: 1, height: 1)).to equal(canvas)
      end

      it 'raises ArgumentError when keyword args are missing' do
        expect { canvas.mark_dirty(x: 5, y: 10) }
          .to raise_error(ArgumentError, /mark_dirty requires/)
      end

      it 'raises ArgumentError with no arguments' do
        expect { canvas.mark_dirty }
          .to raise_error(ArgumentError, /mark_dirty requires/)
      end
    end
  end

  describe 'Canvas dup/clone preserves dirty state' do
    it 'copies dirty state to the duplicate' do
      canvas = ChromaWave::Canvas.new(width: 20, height: 20)
      canvas.set_pixel(5, 5, black)
      copy = canvas.dup
      expect(copy).to be_dirty
      expect(copy.dirty_region).to eq(canvas.dirty_region)
    end

    it 'produces independent dirty state' do
      canvas = ChromaWave::Canvas.new(width: 20, height: 20)
      canvas.set_pixel(5, 5, black)
      copy = canvas.dup
      copy.clean!
      expect(canvas).to be_dirty
      expect(copy).not_to be_dirty
    end

    it 'copies clean state correctly' do
      canvas = ChromaWave::Canvas.new(width: 20, height: 20)
      copy = canvas.dup
      expect(copy).not_to be_dirty
    end
  end

  describe 'Layer dirty propagation' do
    it 'propagates set_pixel to parent canvas dirty region' do
      canvas = ChromaWave::Canvas.new(width: 100, height: 100)
      layer = canvas.layer(x: 10, y: 20, width: 50, height: 30)
      layer.set_pixel(5, 5, black)
      # Layer translates (5,5) to parent (15,25)
      expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 15, y: 25, width: 1, height: 1))
    end

    it 'propagates clear to parent canvas dirty region' do
      canvas = ChromaWave::Canvas.new(width: 100, height: 100)
      layer = canvas.layer(x: 10, y: 20, width: 50, height: 30)
      layer.clear(black)
      # Layer.clear calls parent.fill_rect with translated coords
      expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 10, y: 20, width: 50, height: 30))
    end

    it 'propagates load_rgba_bytes to parent canvas dirty region' do
      canvas = ChromaWave::Canvas.new(width: 100, height: 100)
      layer = canvas.layer(x: 10, y: 20, width: 50, height: 30)
      bytes = (black.to_rgba_bytes * 4) # 2x2
      layer.load_rgba_bytes(bytes, width: 2, height: 2, x: 0, y: 0)
      expect(canvas.dirty_region).to eq(ChromaWave::Rect.new(x: 10, y: 20, width: 2, height: 2))
    end
  end

  describe 'Drawing primitives dirty propagation' do
    subject(:canvas) { ChromaWave::Canvas.new(width: 100, height: 100) }

    it 'tracks dirty from draw_line via set_pixel' do
      pen = ChromaWave::Pen.new(stroke: black)
      canvas.draw_line(10, 10, 50, 50, pen: pen)
      expect(canvas).to be_dirty
      region = canvas.dirty_region
      expect(region.x).to be <= 10
      expect(region.y).to be <= 10
    end

    it 'tracks dirty from draw_rect via set_pixel' do
      pen = ChromaWave::Pen.new(stroke: black)
      canvas.draw_rect(10, 10, 30, 20, pen: pen)
      expect(canvas).to be_dirty
    end

    it 'tracks dirty from draw_circle via set_pixel' do
      pen = ChromaWave::Pen.new(stroke: black)
      canvas.draw_circle(50, 50, 10, pen: pen)
      expect(canvas).to be_dirty
    end

    it 'tracks dirty from fill_rect via Canvas#fill_rect' do
      pen = ChromaWave::Pen.new(fill: black)
      canvas.draw_rect(10, 10, 30, 20, pen: pen)
      expect(canvas).to be_dirty
    end
  end

  describe 'Display#show_dirty' do
    # epd_2in7_v2 has RegionalRefresh capability
    let(:regional_model) { :epd_2in7_v2 }
    # epd_2in13_v4 does NOT have RegionalRefresh
    let(:non_regional_model) { :epd_2in13_v4 }

    describe 'on a RegionalRefresh-capable display' do
      let(:display) { ChromaWave::MockDevice.new(model: regional_model) }

      after { display.close }

      it 'is a no-op when canvas is clean' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        result = display.show_dirty(canvas)
        expect(result).to equal(display)
        expect(display.operation_count).to eq(0)
      end

      it 'uses display_region for dirty canvas' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        display.show(canvas) # initial full show
        display.clear_operations!

        canvas.set_pixel(10, 10, black)
        display.show_dirty(canvas)

        # Should have used regional refresh (show_region op)
        expect(display.operations(:show_region)).not_to be_empty
      end

      it 'cleans the canvas after successful display' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        display.show_dirty(canvas)
        expect(canvas).not_to be_dirty
      end

      it 'returns self' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        expect(display.show_dirty(canvas)).to equal(display)
      end
    end

    describe 'on a rotated RegionalRefresh-capable display' do
      let(:display) { ChromaWave::MockDevice.new(model: regional_model, rotation: 90) }

      after { display.close }

      it 'passes logical-space framebuffer to display_region (no double rotation)' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        # If show_dirty double-rotates, display_region's validate_logical_framebuffer!
        # would raise because the FB dimensions wouldn't match logical display size.
        expect { display.show_dirty(canvas) }.not_to raise_error
        expect(display.operations(:show_region)).not_to be_empty
      end
    end

    describe 'on a non-RegionalRefresh display' do
      let(:display) { ChromaWave::MockDevice.new(model: non_regional_model) }

      after { display.close }

      it 'is a no-op when canvas is clean' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        display.show_dirty(canvas)
        expect(display.operation_count).to eq(0)
      end

      it 'falls back to full refresh for dirty canvas' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        display.show_dirty(canvas)
        # Should have used full show (not show_region)
        expect(display.operations(:show_region)).to be_empty
        expect(display.operations(:show)).not_to be_empty
      end

      it 'cleans the canvas after successful display' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        display.show_dirty(canvas)
        expect(canvas).not_to be_dirty
      end
    end

    describe 'show does NOT clean the canvas' do
      let(:display) { ChromaWave::MockDevice.new(model: non_regional_model) }

      after { display.close }

      it 'preserves dirty state after show' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        display.show(canvas)
        expect(canvas).to be_dirty
      end
    end

    describe 'mode: :partial' do
      context 'with a PartialRefresh-capable display' do
        let(:display) { ChromaWave::MockDevice.new(model: non_regional_model) }

        after { display.close }

        it 'uses partial refresh when requested' do
          canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
          canvas.set_pixel(10, 10, black)
          display.show_dirty(canvas, mode: :partial)
          expect(canvas).not_to be_dirty
        end
      end

      context 'with an unknown mode' do
        let(:display) { ChromaWave::MockDevice.new(model: non_regional_model) }

        after { display.close }

        it 'raises ArgumentError' do
          canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
          canvas.set_pixel(10, 10, black)
          expect { display.show_dirty(canvas, mode: :bogus) }
            .to raise_error(ArgumentError, /unknown mode/)
        end
      end
    end
  end

  describe 'ManagedRefresh#show_dirty' do
    let(:regional_model) { :epd_2in7_v2 }
    let(:non_regional_model) { :epd_2in13_v4 }

    context 'with a regional display and managed refresh' do
      let(:display) do
        ChromaWave::MockDevice.new(model: regional_model, managed_refresh: true)
      end

      after { display.close }

      it 'tracks as partial refresh' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        display.show_dirty(canvas)
        expect(display.refresh_scheduler.partial_count).to eq(1)
      end
    end

    context 'with a non-regional display and managed refresh' do
      let(:display) do
        ChromaWave::MockDevice.new(model: non_regional_model, managed_refresh: true)
      end

      after { display.close }

      it 'tracks as full refresh' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        canvas.set_pixel(10, 10, black)
        display.show_dirty(canvas)
        expect(display.refresh_scheduler.partial_count).to eq(0)
      end
    end

    context 'when canvas is clean' do
      let(:display) do
        ChromaWave::MockDevice.new(model: regional_model, managed_refresh: true)
      end

      after { display.close }

      it 'is a no-op (no tracking)' do
        canvas = ChromaWave::Canvas.new(width: display.width, height: display.height)
        display.show_dirty(canvas)
        expect(display.refresh_scheduler.partial_count).to eq(0)
      end
    end
  end

  describe 'Renderer#render_region' do
    let(:renderer) { ChromaWave::Renderer.new(pixel_format: :mono, dither: :threshold) }

    it 'returns a Framebuffer' do
      canvas = ChromaWave::Canvas.new(width: 20, height: 20, background: black)
      region = { x: 0, y: 0, width: 10, height: 10 }
      fb = renderer.render_region(canvas, region)
      expect(fb).to be_a(ChromaWave::Framebuffer)
      expect(fb.width).to eq(20)
      expect(fb.height).to eq(20)
    end

    it 'accepts an into: parameter' do
      canvas = ChromaWave::Canvas.new(width: 20, height: 20, background: black)
      existing = ChromaWave::Framebuffer.new(20, 20, ChromaWave::PixelFormat::MONO)
      region = { x: 0, y: 0, width: 10, height: 10 }
      result = renderer.render_region(canvas, region, into: existing)
      expect(result).to equal(existing)
    end
  end
end
