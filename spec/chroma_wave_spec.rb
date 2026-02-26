# frozen_string_literal: true

RSpec.describe ChromaWave do
  it 'has a version number' do
    expect(ChromaWave::VERSION).not_to be_nil
  end

  it 'defines the ChromaWave module' do
    expect(described_class).to be_a(Module)
  end

  it 'defines the Native module' do
    expect(ChromaWave::Native).to be_a(Module)
  end
end
