# frozen_string_literal: true

require_relative 'shared_examples'

RSpec.describe ChromaWave::Dither::FloydSteinberg do
  include DitherSpecHelpers

  let(:gray_format) { ChromaWave::PixelFormat::GRAY4 }

  it_behaves_like 'a dither strategy'

  describe '#call' do
    it 'produces at least as many transitions as threshold on a gradient' do
      canvas = build_gradient_canvas(width: 16, height: 1)

      threshold_fb = render_with(ChromaWave::Dither::Threshold, gray_format, canvas)
      fs_fb = render_with(described_class, gray_format, canvas)

      expect(count_transitions(fs_fb, 16)).to be >= count_transitions(threshold_fb, 16)
    end
  end

  describe '.strategy_name' do
    it 'returns :floyd_steinberg' do
      expect(described_class.strategy_name).to eq(:floyd_steinberg)
    end
  end
end
