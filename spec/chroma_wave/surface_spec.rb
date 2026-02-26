# frozen_string_literal: true

# Minimal Surface includer backed by a Hash for isolated protocol testing.
class TestSurface
  include ChromaWave::Surface

  attr_reader :width, :height

  def initialize(width:, height:)
    @width  = width
    @height = height
    @pixels = {}
  end

  def set_pixel(x, y, color)
    return self unless in_bounds?(x, y)

    @pixels[[x, y]] = color
    self
  end

  def get_pixel(x, y)
    return nil unless in_bounds?(x, y)

    @pixels[[x, y]]
  end
end

RSpec.describe ChromaWave::Surface do
  subject(:surface) { TestSurface.new(width: 10, height: 8) }

  describe '#in_bounds?' do
    it 'returns true for origin' do
      expect(surface.in_bounds?(0, 0)).to be(true)
    end

    it 'returns true for max corner' do
      expect(surface.in_bounds?(9, 7)).to be(true)
    end

    it 'returns false for negative x' do
      expect(surface.in_bounds?(-1, 0)).to be(false)
    end

    it 'returns false for negative y' do
      expect(surface.in_bounds?(0, -1)).to be(false)
    end

    it 'returns false for x == width' do
      expect(surface.in_bounds?(10, 0)).to be(false)
    end

    it 'returns false for y == height' do
      expect(surface.in_bounds?(0, 8)).to be(false)
    end
  end

  describe '#clear' do
    it 'fills all pixels with the given color' do
      surface.clear(:red)
      expect(surface.get_pixel(0, 0)).to eq(:red)
      expect(surface.get_pixel(9, 7)).to eq(:red)
    end

    it 'returns self for chaining' do
      expect(surface.clear(:red)).to equal(surface)
    end
  end

  describe '#blit' do
    let(:source) { TestSurface.new(width: 3, height: 2) }

    before do
      source.set_pixel(0, 0, :a)
      source.set_pixel(1, 0, :b)
      source.set_pixel(2, 0, :c)
      source.set_pixel(0, 1, :d)
      source.set_pixel(1, 1, :e)
      source.set_pixel(2, 1, :f)
    end

    it 'copies source pixels to the destination at offset' do
      surface.blit(source, x: 2, y: 3)
      expect(surface.get_pixel(2, 3)).to eq(:a)
      expect(surface.get_pixel(3, 3)).to eq(:b)
      expect(surface.get_pixel(4, 3)).to eq(:c)
      expect(surface.get_pixel(2, 4)).to eq(:d)
      expect(surface.get_pixel(3, 4)).to eq(:e)
      expect(surface.get_pixel(4, 4)).to eq(:f)
    end

    it 'clips source pixels that fall outside destination' do
      surface.blit(source, x: 9, y: 7)
      expect(surface.get_pixel(9, 7)).to eq(:a)
    end

    it 'clips with negative offset' do
      surface.blit(source, x: -1, y: -1)
      expect(surface.get_pixel(0, 0)).to eq(:e)
      expect(surface.get_pixel(1, 0)).to eq(:f)
    end

    it 'skips nil source pixels' do
      surface.set_pixel(2, 3, :existing)
      sparse = TestSurface.new(width: 3, height: 2)
      sparse.set_pixel(1, 0, :only)
      surface.blit(sparse, x: 2, y: 3)
      expect(surface.get_pixel(2, 3)).to eq(:existing)
      expect(surface.get_pixel(3, 3)).to eq(:only)
    end

    it 'returns self for chaining' do
      expect(surface.blit(source, x: 0, y: 0)).to equal(surface)
    end
  end

  describe 'Framebuffer includes Surface' do
    subject(:fb) { ChromaWave::Framebuffer.new(16, 8, :mono) }

    it 'responds to in_bounds?' do
      expect(fb).to respond_to(:in_bounds?)
    end

    it 'returns true for valid coordinates' do
      expect(fb.in_bounds?(0, 0)).to be(true)
    end

    it 'returns false for out-of-bounds coordinates' do
      expect(fb.in_bounds?(16, 0)).to be(false)
    end

    it 'responds to blit' do
      expect(fb).to respond_to(:blit)
    end

    it 'blits from another framebuffer' do
      src = ChromaWave::Framebuffer.new(4, 4, :mono)
      src.clear(:black)
      fb.clear(:white)
      fb.blit(src, x: 0, y: 0)
      expect(fb.get_pixel(0, 0)).to eq(:black)
      expect(fb.get_pixel(3, 3)).to eq(:black)
      expect(fb.get_pixel(4, 0)).to eq(:white)
    end
  end
end
