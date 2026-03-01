# frozen_string_literal: true

# RSpec helper for hardware-related examples using MockDevice.
#
# Tag examples with +:hardware+ to get a MockDevice injected via metadata.
# The default model is +:epd_2in13_v4+; override with +model:+ metadata.
#
# @example
#   it 'displays content', :hardware do |example|
#     mock = example.metadata[:mock_device]
#     mock.show(canvas)
#     expect(mock.operation_count(:show)).to eq(1)
#   end
#
#   it 'uses a color display', :hardware, model: :epd_13in3b do |example|
#     mock = example.metadata[:mock_device]
#     expect(mock.pixel_format).to eq(ChromaWave::PixelFormat::COLOR4)
#   end
RSpec.configure do |config|
  config.around(:each, :hardware) do |example|
    mock = ChromaWave::MockDevice.new(
      model: example.metadata[:model] || :epd_2in13_v4,
      busy_duration: example.metadata[:busy_duration] || 0
    )
    example.metadata[:mock_device] = mock
    example.run
  ensure
    mock&.close
  end
end
