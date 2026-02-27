# frozen_string_literal: true

RSpec.describe ChromaWave::Layer do
  let(:white) { ChromaWave::Color::WHITE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:red)   { ChromaWave::Color::RED }
  let(:blue)  { ChromaWave::Color::BLUE }

  let(:canvas) { ChromaWave::Canvas.new(width: 20, height: 15, background: white) }

  describe '#initialize' do
    it 'stores width and height' do
      layer = described_class.new(parent: canvas, x: 5, y: 5, width: 10, height: 5)
      expect(layer.width).to eq(10)
      expect(layer.height).to eq(5)
    end

    it 'raises ArgumentError for zero width' do
      expect { described_class.new(parent: canvas, x: 0, y: 0, width: 0, height: 5) }
        .to raise_error(ArgumentError, /width/)
    end

    it 'raises ArgumentError for negative width' do
      expect { described_class.new(parent: canvas, x: 0, y: 0, width: -1, height: 5) }
        .to raise_error(ArgumentError, /width/)
    end

    it 'raises ArgumentError for zero height' do
      expect { described_class.new(parent: canvas, x: 0, y: 0, width: 5, height: 0) }
        .to raise_error(ArgumentError, /height/)
    end

    it 'raises ArgumentError for negative height' do
      expect { described_class.new(parent: canvas, x: 0, y: 0, width: 5, height: -1) }
        .to raise_error(ArgumentError, /height/)
    end
  end

  describe '#inspect' do
    it 'includes class name, dimensions, and offset' do
      layer = described_class.new(parent: canvas, x: 3, y: 7, width: 10, height: 5)
      expect(layer.inspect).to eq('#<ChromaWave::Layer 10x5 at (3,7)>')
    end
  end

  describe 'coordinate translation' do
    subject(:layer) { described_class.new(parent: canvas, x: 5, y: 3, width: 8, height: 6) }

    it 'translates local (0,0) to parent (5,3)' do
      layer.set_pixel(0, 0, red)
      expect(canvas.get_pixel(5, 3)).to eq(red)
    end

    it 'translates local (7,5) to parent (12,8)' do
      layer.set_pixel(7, 5, blue)
      expect(canvas.get_pixel(12, 8)).to eq(blue)
    end

    it 'reads from parent through translation' do
      canvas.set_pixel(5, 3, red)
      expect(layer.get_pixel(0, 0)).to eq(red)
    end
  end

  describe 'Layer bounds clipping' do
    subject(:layer) { described_class.new(parent: canvas, x: 5, y: 5, width: 5, height: 5) }

    it 'clips negative x' do
      expect(layer.set_pixel(-1, 0, red)).to equal(layer)
      expect(canvas.get_pixel(4, 5)).to eq(white)
    end

    it 'clips x >= layer width' do
      expect(layer.set_pixel(5, 0, red)).to equal(layer)
      expect(canvas.get_pixel(10, 5)).to eq(white)
    end

    it 'clips negative y' do
      expect(layer.get_pixel(0, -1)).to be_nil
    end

    it 'clips y >= layer height' do
      expect(layer.get_pixel(0, 5)).to be_nil
    end
  end

  describe 'Layer extending past parent edge' do
    subject(:layer) { described_class.new(parent: canvas, x: 18, y: 13, width: 5, height: 5) }

    it 'delegates to parent clipping for pixels past parent edge' do
      # Layer origin at parent (18,13), writing at local (1,1) → parent (19,14)
      layer.set_pixel(1, 1, red)
      expect(canvas.get_pixel(19, 14)).to eq(red)
    end

    it 'silently clips pixels that exceed parent bounds' do
      # local (3,3) → parent (21,16) which is OOB
      layer.set_pixel(3, 3, red)
      # No crash, get_pixel returns nil from parent for OOB
      expect(layer.get_pixel(3, 3)).to be_nil
    end
  end

  describe 'nested Layers' do
    it 'composes offsets additively' do
      outer = described_class.new(parent: canvas, x: 3, y: 2, width: 10, height: 10)
      inner = described_class.new(parent: outer, x: 4, y: 5, width: 3, height: 3)

      inner.set_pixel(1, 1, red)
      # inner(1,1) → outer(5,6) → canvas(8,8)
      expect(canvas.get_pixel(8, 8)).to eq(red)
    end

    it 'reads through nested translation' do
      canvas.set_pixel(8, 8, blue)
      outer = described_class.new(parent: canvas, x: 3, y: 2, width: 10, height: 10)
      inner = described_class.new(parent: outer, x: 4, y: 5, width: 3, height: 3)

      expect(inner.get_pixel(1, 1)).to eq(blue)
    end
  end

  describe '#clear' do
    it 'fills only the layer region' do
      layer = described_class.new(parent: canvas, x: 2, y: 2, width: 3, height: 3)
      layer.clear(red)

      # Inside layer region
      expect(canvas.get_pixel(2, 2)).to eq(red)
      expect(canvas.get_pixel(4, 4)).to eq(red)

      # Outside layer region
      expect(canvas.get_pixel(0, 0)).to eq(white)
      expect(canvas.get_pixel(5, 5)).to eq(white)
      expect(canvas.get_pixel(1, 2)).to eq(white)
    end
  end

  describe 'Surface protocol' do
    subject(:layer) { described_class.new(parent: canvas, x: 0, y: 0, width: 5, height: 5) }

    it 'includes Surface' do
      expect(layer).to be_a(ChromaWave::Surface)
    end

    it 'responds to in_bounds?' do
      expect(layer.in_bounds?(0, 0)).to be(true)
      expect(layer.in_bounds?(5, 0)).to be(false)
    end

    it 'responds to blit' do
      expect(layer).to respond_to(:blit)
    end
  end

  describe 'works with Framebuffer parent' do
    let(:fb) { ChromaWave::Framebuffer.new(16, 8, :mono) }

    it 'translates coordinates to framebuffer' do
      layer = described_class.new(parent: fb, x: 4, y: 2, width: 4, height: 4)
      fb.clear(:white)
      layer.set_pixel(0, 0, :black)
      expect(fb.get_pixel(4, 2)).to eq(:black)
    end

    it 'reads from framebuffer through translation' do
      fb.clear(:white)
      fb.set_pixel(4, 2, :black)
      layer = described_class.new(parent: fb, x: 4, y: 2, width: 4, height: 4)
      expect(layer.get_pixel(0, 0)).to eq(:black)
    end
  end
end
