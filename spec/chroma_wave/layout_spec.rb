# frozen_string_literal: true

# rubocop:disable Lint/EmptyBlock
RSpec.describe ChromaWave::Layout do
  let(:font) { ChromaWave::Font.default(size: 12) }
  let(:black) { ChromaWave::Color::BLACK }
  let(:gray) { ChromaWave::Color::LIGHT_GRAY }

  describe '.build' do
    it 'returns a Layout instance with correct dimensions' do
      layout = described_class.build(width: 200, height: 100) {}
      expect(layout).to be_a(described_class)
      expect(layout.width).to eq(200)
      expect(layout.height).to eq(100)
    end

    it 'wraps children in an implicit root column' do
      f = font
      c = black
      layout = described_class.build(width: 200, height: 100) do
        text 'hello', font: f, color: c
      end
      expect(layout.root).to be_vertical
      expect(layout.root.children.length).to eq(1)
    end

    it 'applies a custom background color to the root container' do
      layout = described_class.build(width: 50, height: 50, background: gray) {}
      expect(layout.root.background).to eq(gray)
    end

    it 'raises ArgumentError for zero width' do
      expect { described_class.build(width: 0, height: 100) {} }.to raise_error(ArgumentError, /width must be positive/)
    end

    it 'raises ArgumentError for negative height' do
      expect { described_class.build(width: 100, height: -1) {} }
        .to raise_error(ArgumentError, /height must be positive/)
    end
  end

  describe '#render' do
    it 'returns a Canvas with correct dimensions' do
      f = font
      c = black
      layout = described_class.build(width: 200, height: 100) do
        text 'hello', font: f, color: c
      end
      canvas = layout.render
      expect(canvas.width).to eq(200)
      expect(canvas.height).to eq(100)
    end

    it 'renders text content as non-white pixels' do
      f = font
      c = black
      layout = described_class.build(width: 200, height: 100) do
        text 'Hello World', font: f, color: c
      end
      expect(count_non_white(layout.render)).to be > 0
    end

    it 'renders a dashboard-style layout without error' do
      f = font
      c = black
      g = gray
      canvas = build_dashboard(f, c, g).render
      expect(canvas.width).to eq(250)
      expect(canvas.height).to eq(122)
    end

    it 'is idempotent' do
      f = font
      c = black
      layout = described_class.build(width: 100, height: 50) do
        row(gap: 5) do
          text 'A', font: f, color: c
          spacer
          text 'B', font: f, color: c
        end
      end
      expect(layout.render).to eq(layout.render) # rubocop:disable RSpec/IdenticalEqualityAssertion
    end
  end

  describe '#inspect' do
    it 'returns a readable description' do
      layout = described_class.build(width: 200, height: 100) {}
      expect(layout.inspect).to eq('#<ChromaWave::Layout 200x100>')
    end
  end

  describe 'Display integration', :hardware do
    it 'shows a layout on MockDevice' do |example|
      mock = example.metadata[:mock_device]
      f = font
      c = black
      layout = described_class.build(width: mock.width, height: mock.height) do
        column(padding: 5) do
          text 'Layout test', font: f, color: c
        end
      end
      mock.show(layout)
      expect(mock.operation_count(:show)).to eq(1)
    end
  end

  private

  def build_dashboard(fnt, clr, bg_color)
    described_class.build(width: 250, height: 122) do
      column(padding: 5, gap: 5) do
        row(flex: 1, gap: 10) do
          text 'Status:', font: fnt, color: clr
          spacer
          text 'OK', font: fnt, color: clr
        end
        row(flex: 2, background: bg_color, padding: 5) do
          text 'Main content area', font: fnt, color: clr
        end
        row(flex: 1) { text 'Footer', font: fnt, color: clr, align: :center }
      end
    end
  end
end
# rubocop:enable Lint/EmptyBlock
