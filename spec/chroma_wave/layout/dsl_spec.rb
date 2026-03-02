# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::DSL do
  let(:font) { ChromaWave::Font.default(size: 12) }
  let(:color) { ChromaWave::Color::BLACK }

  # Empty DSL blocks are intentional — they test empty-input behavior.
  # rubocop:disable Lint/EmptyBlock

  describe '.evaluate' do
    context 'with an empty block' do
      it 'returns no children' do
        children = described_class.evaluate {}
        expect(children).to be_empty
      end
    end

    context 'with a text element' do
      it 'creates a TextContent node' do
        f = font
        c = color
        children = described_class.evaluate { text 'hello', font: f, color: c }
        expect(children.first).to be_a(ChromaWave::Layout::TextContent)
        expect(children.first.text).to eq('hello')
      end
    end

    context 'with a row container' do
      it 'creates a horizontal ContainerNode with children' do
        f = font
        c = color
        children = described_class.evaluate do
          row(gap: 10) { text 'hi', font: f, color: c }
        end
        node = children.first
        expect(node).to be_a(ChromaWave::Layout::ContainerNode)
        expect(node).to be_horizontal
        expect(node.gap).to eq(10)
      end
    end

    context 'with a column container' do
      it 'creates a vertical ContainerNode' do
        f = font
        c = color
        children = described_class.evaluate do
          column(padding: 5) { text 'hi', font: f, color: c }
        end
        expect(children.first).to be_vertical
        expect(children.first.padding.top).to eq(5)
      end
    end

    context 'with nested containers' do
      it 'builds correct tree depth' do
        f = font
        c = color
        children = described_class.evaluate do
          column { row { text 'inner', font: f, color: c } }
        end
        expect(children.first.children.first.children.first).to be_a(ChromaWave::Layout::TextContent)
      end
    end

    context 'with a spacer' do
      it 'defaults to flex: 1' do
        children = described_class.evaluate { spacer }
        expect(children.first).to be_a(ChromaWave::Layout::SpacerContent)
        expect(children.first.flex).to eq(1)
      end

      it 'accepts a custom flex value' do
        children = described_class.evaluate { spacer(flex: 3) }
        expect(children.first.flex).to eq(3)
      end
    end

    context 'with a canvas_block' do
      it 'captures the block' do
        blk = proc { |layer| layer }
        children = described_class.evaluate { canvas_block(&blk) }
        expect(children.first).to be_a(ChromaWave::Layout::CanvasBlockContent)
        expect(children.first.block).to eq(blk)
      end
    end

    context 'with node sizing kwargs' do
      it 'captures flex and alignment' do
        f = font
        c = color
        node = described_class.evaluate do
          text 'hi', font: f, color: c, flex: 2, align: :center, valign: :bottom
        end.first
        expect(node.flex).to eq(2)
        expect(node.align).to eq(:center)
        expect(node.valign).to eq(:bottom)
      end

      it 'captures fixed dimensions' do
        f = font
        c = color
        node = described_class.evaluate do
          text 'hi', font: f, color: c, width: 100, height: 50
        end.first
        expect(node.fixed_width).to eq(100)
        expect(node.fixed_height).to eq(50)
      end
    end

    context 'with container styling kwargs' do
      it 'captures padding, gap, background, and border' do
        bg = ChromaWave::Color::LIGHT_GRAY
        bd = ChromaWave::Color::BLACK
        node = described_class.evaluate do
          row(padding: 8, gap: 8, background: bg, border: bd, border_width: 2) {}
        end.first
        expect(node.gap).to eq(8)
        expect(node.background).to eq(bg)
        expect(node.border).to eq(bd)
        expect(node.border_width).to eq(2)
      end

      it 'captures child_align and child_valign' do
        node = described_class.evaluate do
          row(child_align: :center, child_valign: :bottom) {}
        end.first
        expect(node.child_align).to eq(:center)
        expect(node.child_valign).to eq(:bottom)
      end
    end

    context 'with an icon element' do
      it 'creates an IconContent node' do
        icon_font = ChromaWave::IconFont.lucide(size: 16)
        c = color
        children = described_class.evaluate { icon :house, font: icon_font, color: c }
        node = children.first
        expect(node).to be_a(ChromaWave::Layout::IconContent)
        expect(node.name).to eq(:house)
        expect(node.font).to eq(icon_font)
      end
    end

    context 'with an image element' do
      it 'creates an ImageContent node' do
        source = instance_double(ChromaWave::Image, width: 100, height: 80)
        children = described_class.evaluate { image source, fit: :cover }
        node = children.first
        expect(node).to be_a(ChromaWave::Layout::ImageContent)
        expect(node.source).to eq(source)
        expect(node.fit).to eq(:cover)
      end

      it 'defaults to fit: :contain' do
        source = instance_double(ChromaWave::Image, width: 50, height: 50)
        children = described_class.evaluate { image source }
        expect(children.first.fit).to eq(:contain)
      end
    end

    context 'with negative flex' do
      it 'raises ArgumentError' do
        f = font
        c = color
        expect do
          described_class.evaluate { text 'hi', font: f, color: c, flex: -1 }
        end.to raise_error(ArgumentError, /flex must be positive/)
      end
    end

    context 'with invalid align/valign values' do
      it 'raises ArgumentError for invalid align' do
        f = font
        c = color
        expect do
          described_class.evaluate { text 'hi', font: f, color: c, align: :middle }
        end.to raise_error(ArgumentError, /align must be one of/)
      end

      it 'raises ArgumentError for invalid valign' do
        f = font
        c = color
        expect do
          described_class.evaluate { text 'hi', font: f, color: c, valign: :middle }
        end.to raise_error(ArgumentError, /valign must be one of/)
      end
    end

    context 'with unknown keyword arguments' do
      it 'raises ArgumentError for unknown text kwargs' do
        f = font
        c = color
        expect do
          described_class.evaluate { text 'hi', font: f, color: c, typo: 1 }
        end.to raise_error(ArgumentError, /unknown keyword/)
      end

      it 'raises ArgumentError for unknown container kwargs' do
        expect do
          described_class.evaluate { row(typo: 1) {} }
        end.to raise_error(ArgumentError, /unknown keyword/)
      end

      it 'raises ArgumentError for unknown spacer kwargs' do
        expect do
          described_class.evaluate { spacer(typo: 1) }
        end.to raise_error(ArgumentError, /unknown keyword/)
      end
    end
  end
  # rubocop:enable Lint/EmptyBlock
end
