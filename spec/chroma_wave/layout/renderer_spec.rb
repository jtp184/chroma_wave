# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Renderer do
  let(:white) { ChromaWave::Color::WHITE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:red) { ChromaWave::Color::RED }
  let(:gray) { ChromaWave::Color::LIGHT_GRAY }
  let(:canvas) { ChromaWave::Canvas.new(width: 100, height: 100) }
  let(:positions) { {} }
  let(:renderer) { described_class.new(canvas, positions) }

  let(:box_class) { ChromaWave::Layout::Box }
  let(:container_class) { ChromaWave::Layout::ContainerNode }
  let(:node_class) { ChromaWave::Layout::Node }
  let(:spacer_class) { ChromaWave::Layout::SpacerContent }

  # Helper: register a positioned box for a node
  def assign_box(node, x:, y:, width:, height:)
    positions[node] = box_class.new(x: x, y: y, width: width, height: height)
  end

  describe 'background rendering' do
    it 'fills the container region with the background color' do
      root = container_class.new(direction: :vertical, children: [], background: gray)
      assign_box(root, x: 10, y: 10, width: 50, height: 50)

      renderer.render(root)

      expect(canvas.get_pixel(10, 10)).to eq(gray)
      expect(canvas.get_pixel(59, 59)).to eq(gray)
      # Outside the box should be white
      expect(canvas.get_pixel(9, 10)).to eq(white)
      expect(canvas.get_pixel(60, 60)).to eq(white)
    end
  end

  describe 'border rendering' do
    before do
      root = container_class.new(direction: :vertical, children: [], border: black, border_width: 2)
      assign_box(root, x: 0, y: 0, width: 100, height: 100)
      renderer.render(root)
    end

    it 'draws top and bottom border strips' do
      expect(canvas.get_pixel(50, 0)).to eq(black)
      expect(canvas.get_pixel(50, 1)).to eq(black)
      expect(canvas.get_pixel(50, 98)).to eq(black)
      expect(canvas.get_pixel(50, 99)).to eq(black)
    end

    it 'draws left and right border strips' do
      expect(canvas.get_pixel(0, 50)).to eq(black)
      expect(canvas.get_pixel(1, 50)).to eq(black)
      expect(canvas.get_pixel(98, 50)).to eq(black)
      expect(canvas.get_pixel(99, 50)).to eq(black)
    end
  end

  describe 'spacer rendering' do
    it 'produces no visible pixels' do
      spacer = spacer_class.new
      assign_box(spacer, x: 10, y: 10, width: 30, height: 30)

      renderer.render(spacer)

      expect(count_non_white(canvas)).to eq(0)
    end
  end

  describe 'text rendering' do
    it 'draws text onto the canvas' do
      font = ChromaWave::Font.default(size: 12)
      text_node = ChromaWave::Layout::TextContent.new(
        text: 'Hi', font: font, color: black
      )
      assign_box(text_node, x: 5, y: 5, width: 90, height: 30)

      renderer.render(text_node)

      expect(count_non_white(canvas)).to be > 0
    end
  end

  describe 'text alignment' do
    # Renders aligned text and returns the x of the first non-white pixel.
    def render_aligned_text(align)
      font = ChromaWave::Font.default(size: 12)
      node = ChromaWave::Layout::TextContent.new(text: 'Hi', font: font, color: black, align: align)
      pos = { node => box_class.new(x: 0, y: 0, width: 100, height: 30) }
      cvs = ChromaWave::Canvas.new(width: 100, height: 30)
      described_class.new(cvs, pos).render(node)
      first_non_white_x(cvs)
    end

    it 'right-aligned text starts further right than left-aligned' do
      expect(render_aligned_text(:right)).to be > render_aligned_text(:left)
    end
  end

  describe 'canvas_block rendering' do
    it 'calls the block with a layer' do
      received_layer = nil
      block_node = ChromaWave::Layout::CanvasBlockContent.new(
        block: ->(layer) { received_layer = layer }
      )
      assign_box(block_node, x: 10, y: 10, width: 50, height: 50)

      renderer.render(block_node)

      expect(received_layer).to be_a(ChromaWave::Layer)
      expect(received_layer.width).to eq(50)
      expect(received_layer.height).to eq(50)
    end
  end

  describe 'icon rendering' do
    it 'draws an icon onto the canvas' do
      icon_font = ChromaWave::IconFont.lucide(size: 24)
      icon_node = ChromaWave::Layout::IconContent.new(
        name: :house, font: icon_font, color: black
      )
      assign_box(icon_node, x: 5, y: 5, width: 30, height: 30)

      renderer.render(icon_node)

      expect(count_non_white(canvas)).to be > 0
    end
  end

  describe 'image rendering' do
    # Build a small 10x10 red image as raw RGBA bytes for testing
    let(:image_canvas) do
      ChromaWave::Canvas.new(width: 10, height: 10).tap do |c|
        c.clear(red)
      end
    end

    let(:mock_image) do
      rgba = String.new(encoding: Encoding::BINARY)
      10.times do
        10.times do
          rgba << [red.r, red.g, red.b, red.a].pack('C4')
        end
      end

      img = instance_double(ChromaWave::Image, width: 10, height: 10)
      allow(img).to receive_messages(resize: img, crop: img)
      allow(img).to receive(:draw_onto) do |target_canvas, x:, y:|
        target_canvas.load_rgba_bytes(rgba, width: 10, height: 10, x: x, y: y)
      end
      img
    end

    it 'renders an image with :stretch fit' do
      image_node = ChromaWave::Layout::ImageContent.new(
        source: mock_image, fit: :stretch
      )
      assign_box(image_node, x: 10, y: 10, width: 10, height: 10)

      renderer.render(image_node)

      expect(mock_image).to have_received(:resize).with(width: 10, height: 10)
    end

    it 'renders an image with :contain fit' do
      image_node = ChromaWave::Layout::ImageContent.new(
        source: mock_image, fit: :contain
      )
      assign_box(image_node, x: 0, y: 0, width: 20, height: 20)

      renderer.render(image_node)

      # contain scales to fit, preserving aspect ratio
      expect(mock_image).to have_received(:resize).with(width: 20, height: 20)
    end

    it 'renders an image with :cover fit' do
      wide_image = instance_double(ChromaWave::Image, width: 20, height: 10)
      allow(wide_image).to receive(:resize).and_return(mock_image)
      allow(mock_image).to receive(:crop).and_return(mock_image)

      image_node = ChromaWave::Layout::ImageContent.new(
        source: wide_image, fit: :cover
      )
      assign_box(image_node, x: 0, y: 0, width: 10, height: 10)

      renderer.render(image_node)

      # cover scales to fill, then crops excess
      expect(wide_image).to have_received(:resize)
      expect(mock_image).to have_received(:crop)
    end
  end

  describe 'zero-dimension image' do
    it 'skips rendering for zero-width source image' do
      zero_image = instance_double(ChromaWave::Image, width: 0, height: 10)
      image_node = ChromaWave::Layout::ImageContent.new(source: zero_image)
      assign_box(image_node, x: 0, y: 0, width: 50, height: 50)

      expect { renderer.render(image_node) }.not_to raise_error
      expect(count_non_white(canvas)).to eq(0)
    end

    it 'skips rendering for zero-height source image' do
      zero_image = instance_double(ChromaWave::Image, width: 10, height: 0)
      image_node = ChromaWave::Layout::ImageContent.new(source: zero_image)
      assign_box(image_node, x: 0, y: 0, width: 50, height: 50)

      expect { renderer.render(image_node) }.not_to raise_error
      expect(count_non_white(canvas)).to eq(0)
    end
  end

  describe 'zero-size nodes' do
    it 'skips rendering for zero-width nodes' do
      root = container_class.new(direction: :vertical, children: [], background: black)
      assign_box(root, x: 0, y: 0, width: 0, height: 50)

      renderer.render(root)

      expect(count_non_white(canvas)).to eq(0)
    end
  end
end
