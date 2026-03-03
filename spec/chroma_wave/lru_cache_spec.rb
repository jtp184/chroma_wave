# frozen_string_literal: true

RSpec.describe ChromaWave::LruCache do
  subject(:cache) { described_class.new(capacity: 3) }

  describe '#fetch' do
    it 'stores and retrieves a value' do
      cache.fetch(:a) { 1 }
      expect(cache.fetch(:a) { 2 }).to eq(1)
    end

    it 'evicts the oldest entry when capacity is exceeded' do
      cache.fetch(:a) { 1 }
      cache.fetch(:b) { 2 }
      cache.fetch(:c) { 3 }
      cache.fetch(:d) { 4 }
      expect(cache.fetch(:a) { 99 }).to eq(99)
    end

    it 'refreshes accessed entries to avoid eviction' do
      cache.fetch(:a) { 1 }
      cache.fetch(:b) { 2 }
      cache.fetch(:c) { 3 }
      cache.fetch(:a) { 99 } # refresh :a
      cache.fetch(:d) { 4 }  # should evict :b
      expect(cache.fetch(:a) { 99 }).to eq(1)
      expect(cache.fetch(:b) { 88 }).to eq(88)
    end

    it 'never exceeds capacity' do
      10.times { |i| cache.fetch(i) { i * 10 } }
      expect(cache.size).to eq(3)
    end
  end

  describe '#size' do
    it 'starts at 0' do
      expect(cache.size).to eq(0)
    end

    it 'grows with inserts' do
      cache.fetch(:a) { 1 }
      cache.fetch(:b) { 2 }
      expect(cache.size).to eq(2)
    end

    it 'does not grow on hits' do
      cache.fetch(:a) { 1 }
      cache.fetch(:a) { 2 }
      expect(cache.size).to eq(1)
    end
  end
end
