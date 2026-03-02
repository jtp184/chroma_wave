# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::IconContent do
  let(:icon_font) { ChromaWave::IconFont.lucide(size: 24) }
  let(:color) { ChromaWave::Color::BLACK }

  describe 'intrinsic sizing' do
    subject(:node) { described_class.new(name: :house, font: icon_font, color: color) }

    it 'reports intrinsic width from icon measurement' do
      expected = icon_font.measure_icon(:house).width
      expect(node.intrinsic_width).to eq(expected)
    end

    it 'reports intrinsic height from icon measurement' do
      expected = icon_font.measure_icon(:house).height
      expect(node.intrinsic_height).to eq(expected)
    end

    it 'memoizes icon measurement' do
      node.intrinsic_width
      node.intrinsic_height

      expect(node.metrics).to equal(node.metrics)
    end
  end
end
