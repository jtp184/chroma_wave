# frozen_string_literal: true

RSpec.describe ChromaWave::Layout::Renderer do
  let(:white) { ChromaWave::Color::WHITE }
  let(:black) { ChromaWave::Color::BLACK }
  let(:red) { ChromaWave::Color::RED }
  let(:gray) { ChromaWave::Color::LIGHT_GRAY }
  let(:canvas) { ChromaWave::Canvas.new(width: 100, height: 100) }
  let(:renderer) { described_class.new(canvas) }

  let(:container_class) { ChromaWave::Layout::ContainerNode }
  let(:node_class) { ChromaWave::Layout::Node }
  let(:spacer_class) { ChromaWave::Layout::SpacerContent }

  # Helper: assign a box to a node
  def assign_box(node, x:, y:, width:, height:)
    node.box.x = x
    node.box.y = y
    node.box.width = width
    node.box.height = height
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

  describe 'zero-size nodes' do
    it 'skips rendering for zero-width nodes' do
      root = container_class.new(direction: :vertical, children: [], background: black)
      assign_box(root, x: 0, y: 0, width: 0, height: 50)

      renderer.render(root)

      expect(count_non_white(canvas)).to eq(0)
    end
  end
end
