# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::TextContent do
  let(:font) { ChromaWave::Font.default(size: 12) }
  let(:color) { ChromaWave::Color::BLACK }

  describe 'intrinsic sizing' do
    subject(:node) { described_class.new(text: 'Hello', font: font, color: color) }

    it 'reports intrinsic width from font measurement' do
      expected = font.measure('Hello').width
      expect(node.intrinsic_width).to eq(expected)
    end

    it 'reports intrinsic height from font measurement' do
      expected = font.measure('Hello').height
      expect(node.intrinsic_height).to eq(expected)
    end

    it 'memoizes font measurement' do
      node.intrinsic_width
      node.intrinsic_height

      expect(node.metrics).to equal(node.metrics)
    end
  end
end
