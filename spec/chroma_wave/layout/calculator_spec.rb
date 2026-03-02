# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Calculator do
  # Shorthand accessors for concise test setup
  let(:padding_class) { ChromaWave::Layout::Padding }
  let(:constraints_class) { ChromaWave::Layout::Constraints }
  let(:container_class) { ChromaWave::Layout::ContainerNode }
  let(:spacer_class) { ChromaWave::Layout::SpacerContent }
  let(:node_class) { ChromaWave::Layout::Node }

  # Helper: builds a container with children, computes layout, returns position map
  def layout(root, width:, height:)
    described_class.new(root: root, width: width, height: height).compute
  end

  describe 'fixed-only children' do
    it 'assigns exact sizes to fixed-width children in a row' do
      child_a = node_class.new(width: 100)
      child_b = node_class.new(width: 200)
      root = container_class.new(direction: :horizontal, children: [child_a, child_b])

      positions = layout(root, width: 400, height: 100)

      expect(positions[child_a].width).to eq(100)
      expect(positions[child_b].width).to eq(200)
      expect(positions[child_a].x).to eq(0)
      expect(positions[child_b].x).to eq(100)
    end
  end

  describe 'flex-only children' do
    it 'distributes space proportionally' do
      children = [
        node_class.new(flex: 1),
        node_class.new(flex: 2),
        node_class.new(flex: 1)
      ]
      root = container_class.new(direction: :vertical, children: children)

      positions = layout(root, width: 100, height: 400)

      expect(positions[children[0]].height).to eq(100)
      expect(positions[children[1]].height).to eq(200)
      expect(positions[children[2]].height).to eq(100)
    end
  end

  describe 'mixed fixed and flex children' do
    it 'gives remaining space to flex child' do
      child_a = node_class.new(width: 100)
      child_b = node_class.new(flex: 1)
      child_c = node_class.new(width: 50)
      root = container_class.new(direction: :horizontal, children: [child_a, child_b, child_c])

      positions = layout(root, width: 300, height: 100)

      expect(positions[child_a].width).to eq(100)
      expect(positions[child_b].width).to eq(150)
      expect(positions[child_c].width).to eq(50)
    end
  end

  describe 'gap spacing' do
    it 'subtracts gaps from distributable space' do
      children = Array.new(3) { node_class.new(flex: 1) }
      root = container_class.new(direction: :horizontal, children: children, gap: 10)

      positions = layout(root, width: 310, height: 100)

      # (310 - 2*10) / 3 = 96.67 -> rounding distributes evenly
      total = children.sum { |c| positions[c].width }
      expect(total).to eq(290)
      children.each { |c| expect(positions[c].width).to be_between(96, 98) }
    end
  end

  describe 'padding' do
    it 'reduces content area by padding' do
      child = node_class.new(flex: 1)
      root = container_class.new(direction: :vertical, children: [child], padding: 20)

      positions = layout(root, width: 200, height: 200)

      expect(positions[child].x).to eq(20)
      expect(positions[child].y).to eq(20)
      expect(positions[child].width).to eq(160)
      expect(positions[child].height).to eq(160)
    end
  end

  describe 'border + padding' do
    it 'subtracts border inset and padding from content area' do
      child = node_class.new(flex: 1)
      root = container_class.new(
        direction: :vertical, children: [child],
        border: ChromaWave::Color::BLACK, border_width: 2, padding: 5
      )

      positions = layout(root, width: 100, height: 100)

      # content = 100 - 2*2 (border) - 2*5 (padding) = 86
      expect(positions[child].width).to eq(86)
      expect(positions[child].height).to eq(86)
      expect(positions[child].x).to eq(7) # 2 border + 5 padding
      expect(positions[child].y).to eq(7)
    end
  end

  describe 'min/max constraints on flex children' do
    it 'clamps flex child to min_width and redistributes' do
      # 200px total, 2 flex children (1:1 = 100 each)
      # child_a has min_width: 130 -> gets 130, child_b gets 70
      child_a = node_class.new(flex: 1, min_width: 130)
      child_b = node_class.new(flex: 1)
      root = container_class.new(direction: :horizontal, children: [child_a, child_b])

      positions = layout(root, width: 200, height: 100)

      expect(positions[child_a].width).to eq(130)
      expect(positions[child_b].width).to eq(70)
    end

    it 'clamps flex child to max_width and redistributes' do
      child_a = node_class.new(flex: 1, max_width: 60)
      child_b = node_class.new(flex: 1)
      root = container_class.new(direction: :horizontal, children: [child_a, child_b])

      positions = layout(root, width: 200, height: 100)

      expect(positions[child_a].width).to eq(60)
      expect(positions[child_b].width).to eq(140)
    end
  end

  describe 'cross-axis alignment' do
    context 'with row child_valign: :center' do
      it 'centers children vertically' do
        child = node_class.new(width: 50, height: 40)
        root = container_class.new(direction: :horizontal, children: [child], child_valign: :center)

        positions = layout(root, width: 200, height: 100)

        expect(positions[child].y).to eq(30)
        expect(positions[child].height).to eq(40)
      end
    end

    context 'with row child_valign: :bottom' do
      it 'aligns children to bottom' do
        child = node_class.new(width: 50, height: 40)
        root = container_class.new(direction: :horizontal, children: [child], child_valign: :bottom)

        positions = layout(root, width: 200, height: 100)

        expect(positions[child].y).to eq(60)
      end
    end

    context 'with column child_align: :center' do
      it 'centers children horizontally' do
        child = node_class.new(width: 60, height: 30)
        root = container_class.new(direction: :vertical, children: [child], child_align: :center)

        positions = layout(root, width: 200, height: 100)

        expect(positions[child].x).to eq(70)
      end
    end
  end

  describe 'nested containers' do
    it 'computes correct inner row positions' do
      leaf = node_class.new(flex: 1)
      inner_row = container_class.new(direction: :horizontal, children: [leaf], padding: 5, flex: 1)
      outer_col = container_class.new(direction: :vertical, children: [inner_row], padding: 10)
      positions = layout(outer_col, width: 200, height: 200)

      expect(positions[inner_row]).to eq(ChromaWave::Layout::Box.new(x: 10, y: 10, width: 180, height: 180))
    end

    it 'computes correct leaf positions through nesting' do
      leaf = node_class.new(flex: 1)
      inner_row = container_class.new(direction: :horizontal, children: [leaf], padding: 5, flex: 1)
      outer_col = container_class.new(direction: :vertical, children: [inner_row], padding: 10)
      positions = layout(outer_col, width: 200, height: 200)

      expect(positions[leaf]).to eq(ChromaWave::Layout::Box.new(x: 15, y: 15, width: 170, height: 170))
    end
  end

  describe 'overflow handling' do
    it 'clamps sizes to zero without error' do
      children = [node_class.new(width: 300), node_class.new(flex: 1)]
      root = container_class.new(direction: :horizontal, children: children)

      positions = nil
      expect { positions = layout(root, width: 200, height: 100) }.not_to raise_error
      expect(positions[children[1]].width).to eq(0)
    end

    it 'handles border + padding exceeding container size' do
      child = node_class.new(flex: 1)
      root = container_class.new(
        direction: :vertical, children: [child],
        border: ChromaWave::Color::BLACK, border_width: 30, padding: 20
      )

      positions = nil
      expect { positions = layout(root, width: 80, height: 80) }.not_to raise_error

      # border(30*2) + padding(20*2) = 100 > 80, content area clamped to 0
      # Container gets its full box, children are skipped (no position assigned)
      expect(positions[root].width).to eq(80)
      expect(positions).not_to have_key(child)
    end
  end

  describe 'flex rounding correction' do
    it 'never produces negative sizes from rounding overshoot' do
      # Many small-flex children in tight space to stress rounding
      children = Array.new(7) { node_class.new(flex: 1) }
      root = container_class.new(direction: :horizontal, children: children)

      positions = layout(root, width: 10, height: 10)

      children.each { |c| expect(positions[c].width).to be >= 0 }
      expect(children.sum { |c| positions[c].width }).to eq(10)
    end
  end

  describe 'empty container' do
    it 'assigns full box to container' do
      root = container_class.new(direction: :horizontal, children: [])
      positions = layout(root, width: 100, height: 50)

      expect(positions[root].width).to eq(100)
      expect(positions[root].height).to eq(50)
    end
  end
end
