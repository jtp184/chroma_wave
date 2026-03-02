# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Alignment do
  # Include the module in a test harness to test it directly.
  let(:harness) { Object.new.extend(described_class) }

  describe '#align_offset' do
    context 'when content fits in the container' do
      it 'returns 0 for nil alignment (start)' do
        expect(harness.align_offset(30, 100, nil)).to eq(0)
      end

      it 'returns 0 for :left alignment' do
        expect(harness.align_offset(30, 100, :left)).to eq(0)
      end

      it 'returns 0 for :top alignment' do
        expect(harness.align_offset(30, 100, :top)).to eq(0)
      end

      it 'returns centered offset for :center alignment' do
        expect(harness.align_offset(30, 100, :center)).to eq(35)
      end

      it 'returns end offset for :right alignment' do
        expect(harness.align_offset(30, 100, :right)).to eq(70)
      end

      it 'returns end offset for :bottom alignment' do
        expect(harness.align_offset(30, 100, :bottom)).to eq(70)
      end
    end

    context 'when content is larger than the container' do
      it 'returns 0 for all alignments (no negative offset)' do
        expect(harness.align_offset(150, 100, nil)).to eq(0)
        expect(harness.align_offset(150, 100, :center)).to eq(0)
        expect(harness.align_offset(150, 100, :right)).to eq(0)
      end
    end

    context 'when content equals the container' do
      it 'returns 0 for all alignments' do
        expect(harness.align_offset(100, 100, nil)).to eq(0)
        expect(harness.align_offset(100, 100, :center)).to eq(0)
        expect(harness.align_offset(100, 100, :right)).to eq(0)
      end
    end

    context 'with integer division rounding' do
      it 'rounds center offset down (pixel alignment)' do
        # 100 - 31 = 69, 69/2 = 34 (integer division)
        expect(harness.align_offset(31, 100, :center)).to eq(34)
      end
    end
  end
end
