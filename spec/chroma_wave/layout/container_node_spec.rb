# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::ContainerNode do
  describe 'direction validation' do
    it 'accepts :horizontal' do
      expect { described_class.new(direction: :horizontal) }.not_to raise_error
    end

    it 'accepts :vertical' do
      expect { described_class.new(direction: :vertical) }.not_to raise_error
    end

    it 'rejects invalid direction' do
      expect do
        described_class.new(direction: :diagonal)
      end.to raise_error(ArgumentError, /direction must be :horizontal or :vertical/)
    end
  end

  describe 'gap validation' do
    it 'accepts zero gap' do
      expect { described_class.new(direction: :horizontal, gap: 0) }.not_to raise_error
    end

    it 'accepts positive gap' do
      expect { described_class.new(direction: :horizontal, gap: 10) }.not_to raise_error
    end

    it 'rejects negative gap' do
      expect do
        described_class.new(direction: :horizontal, gap: -5)
      end.to raise_error(ArgumentError, /gap must be non-negative/)
    end
  end

  describe 'border_width validation' do
    it 'accepts zero border_width' do
      expect do
        described_class.new(direction: :horizontal, border_width: 0)
      end.not_to raise_error
    end

    it 'accepts positive border_width with a border color' do
      expect do
        described_class.new(direction: :horizontal, border: ChromaWave::Color::BLACK, border_width: 2)
      end.not_to raise_error
    end

    it 'rejects negative border_width' do
      expect do
        described_class.new(direction: :horizontal, border_width: -1)
      end.to raise_error(ArgumentError, /border_width must be non-negative/)
    end
  end

  describe 'child_align validation' do
    it 'accepts valid child_align values' do
      %i[left center right].each do |a|
        expect { described_class.new(direction: :horizontal, child_align: a) }.not_to raise_error
      end
    end

    it 'accepts nil child_align' do
      expect { described_class.new(direction: :horizontal, child_align: nil) }.not_to raise_error
    end

    it 'rejects invalid child_align' do
      expect do
        described_class.new(direction: :horizontal, child_align: :middle)
      end.to raise_error(ArgumentError, /child_align must be one of/)
    end
  end

  describe 'child_valign validation' do
    it 'accepts valid child_valign values' do
      %i[top center bottom].each do |v|
        expect { described_class.new(direction: :horizontal, child_valign: v) }.not_to raise_error
      end
    end

    it 'accepts nil child_valign' do
      expect { described_class.new(direction: :horizontal, child_valign: nil) }.not_to raise_error
    end

    it 'rejects invalid child_valign' do
      expect do
        described_class.new(direction: :horizontal, child_valign: :middle)
      end.to raise_error(ArgumentError, /child_valign must be one of/)
    end
  end

  describe '#intrinsic_width' do
    # Stub node that reports a known intrinsic size.
    def sized_node(w, h)
      node = ChromaWave::Layout::Node.new
      allow(node).to receive_messages(intrinsic_width: w, intrinsic_height: h)
      node
    end

    it 'sums children intrinsic widths + gaps for horizontal container' do
      children = [sized_node(30, 10), sized_node(50, 10)]
      container = described_class.new(direction: :horizontal, children: children, gap: 10)

      # 30 + 10 + 50 = 90
      expect(container.intrinsic_width).to eq(90)
    end

    it 'takes max child intrinsic width for vertical container' do
      children = [sized_node(30, 10), sized_node(50, 10)]
      container = described_class.new(direction: :vertical, children: children, gap: 10)

      expect(container.intrinsic_width).to eq(50)
    end

    it 'includes padding and border inset' do
      child = sized_node(40, 10)
      container = described_class.new(
        direction: :horizontal, children: [child],
        padding: [0, 10, 0, 5], border: ChromaWave::Color::BLACK, border_width: 2
      )

      # child(40) + padding_h(15) + border(2*2) = 59
      expect(container.intrinsic_width).to eq(59)
    end

    it 'returns inset only for empty container' do
      container = described_class.new(direction: :horizontal, children: [], padding: 5)

      expect(container.intrinsic_width).to eq(10)
    end
  end

  describe '#intrinsic_height' do
    def sized_node(w, h)
      node = ChromaWave::Layout::Node.new
      allow(node).to receive_messages(intrinsic_width: w, intrinsic_height: h)
      node
    end

    it 'sums children intrinsic heights + gaps for vertical container' do
      children = [sized_node(10, 20), sized_node(10, 40)]
      container = described_class.new(direction: :vertical, children: children, gap: 5)

      # 20 + 5 + 40 = 65
      expect(container.intrinsic_height).to eq(65)
    end

    it 'takes max child intrinsic height for horizontal container' do
      children = [sized_node(10, 20), sized_node(10, 40)]
      container = described_class.new(direction: :horizontal, children: children)

      expect(container.intrinsic_height).to eq(40)
    end

    it 'includes padding and border inset' do
      child = sized_node(10, 30)
      container = described_class.new(
        direction: :vertical, children: [child],
        padding: [8, 0, 4, 0], border: ChromaWave::Color::BLACK, border_width: 1
      )

      # child(30) + padding_v(12) + border(2*1) = 44
      expect(container.intrinsic_height).to eq(44)
    end
  end

  describe 'border consistency validation' do
    it 'raises when border_width is set without a border color' do
      expect do
        described_class.new(direction: :horizontal, border_width: 2)
      end.to raise_error(ArgumentError, /no border color was provided/)
    end

    it 'accepts border_width with a border color' do
      expect do
        described_class.new(direction: :horizontal, border: ChromaWave::Color::BLACK, border_width: 2)
      end.not_to raise_error
    end

    it 'accepts zero border_width without a border color' do
      expect do
        described_class.new(direction: :horizontal, border_width: 0)
      end.not_to raise_error
    end
  end
end
