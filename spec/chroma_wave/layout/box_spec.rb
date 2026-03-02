# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Box do
  describe '#initialize' do
    it 'defaults to origin with zero dimensions' do
      box = described_class.new
      expect(box.x).to eq(0)
      expect(box.y).to eq(0)
      expect(box.width).to eq(0)
      expect(box.height).to eq(0)
    end

    it 'accepts keyword arguments' do
      box = described_class.new(x: 10, y: 20, width: 100, height: 50)
      expect(box.x).to eq(10)
      expect(box.y).to eq(20)
      expect(box.width).to eq(100)
      expect(box.height).to eq(50)
    end
  end

  describe 'mutability' do
    it 'allows setting x, y, width, height' do
      box = described_class.new
      box.x = 5
      box.y = 10
      box.width = 200
      box.height = 100

      expect(box.x).to eq(5)
      expect(box.y).to eq(10)
      expect(box.width).to eq(200)
      expect(box.height).to eq(100)
    end
  end

  describe '#==' do
    it 'returns true for equal boxes' do
      a = described_class.new(x: 1, y: 2, width: 3, height: 4)
      b = described_class.new(x: 1, y: 2, width: 3, height: 4)
      expect(a).to eq(b)
    end

    it 'returns false for different boxes' do
      a = described_class.new(x: 1, y: 2, width: 3, height: 4)
      b = described_class.new(x: 1, y: 2, width: 3, height: 5)
      expect(a).not_to eq(b)
    end

    it 'returns false for non-Box objects' do
      box = described_class.new
      expect(box).not_to eq('not a box')
    end
  end

  describe '#eql?' do
    it 'is aliased to ==' do
      a = described_class.new(x: 1, y: 2, width: 3, height: 4)
      b = described_class.new(x: 1, y: 2, width: 3, height: 4)
      expect(a).to eql(b)
    end
  end

  describe '#hash' do
    it 'returns the same hash for equal boxes' do
      a = described_class.new(x: 1, y: 2, width: 3, height: 4)
      b = described_class.new(x: 1, y: 2, width: 3, height: 4)
      expect(a.hash).to eq(b.hash)
    end

    it 'works as a Hash key' do
      box = described_class.new(x: 1, y: 2, width: 3, height: 4)
      hash = { box => :found }
      lookup = described_class.new(x: 1, y: 2, width: 3, height: 4)
      expect(hash[lookup]).to eq(:found)
    end
  end

  describe '#inspect' do
    it 'returns a readable description' do
      box = described_class.new(x: 10, y: 20, width: 100, height: 50)
      expect(box.inspect).to eq('#<ChromaWave::Layout::Box (10,20) 100x50>')
    end
  end
end
