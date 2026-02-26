# frozen_string_literal: true

RSpec.describe ChromaWave::Error do
  it 'inherits from StandardError' do
    expect(described_class).to be < StandardError
  end

  it 'can be instantiated with a message' do
    expect(described_class.new('test error').message).to eq('test error')
  end

  it 'can be raised and rescued' do
    expect { raise described_class, 'boom' }
      .to raise_error(described_class, 'boom')
  end

  describe ChromaWave::DeviceError do
    it 'inherits from ChromaWave::Error' do
      expect(described_class).to be < ChromaWave::Error
    end

    it 'can be rescued as StandardError' do
      expect { raise described_class, 'device' }
        .to raise_error(StandardError)
    end

    it 'can be instantiated with a message' do
      expect(described_class.new('device failed').message).to eq('device failed')
    end
  end

  describe ChromaWave::InitError do
    it 'inherits from ChromaWave::DeviceError' do
      expect(described_class).to be < ChromaWave::DeviceError
    end

    it 'can be raised and rescued' do
      expect { raise described_class, 'init failed' }
        .to raise_error(described_class, 'init failed')
    end
  end

  describe ChromaWave::BusyTimeoutError do
    it 'inherits from ChromaWave::DeviceError' do
      expect(described_class).to be < ChromaWave::DeviceError
    end

    it 'can be raised and rescued' do
      expect { raise described_class, 'timeout' }
        .to raise_error(described_class, 'timeout')
    end
  end

  describe ChromaWave::SPIError do
    it 'inherits from ChromaWave::DeviceError' do
      expect(described_class).to be < ChromaWave::DeviceError
    end

    it 'can be raised and rescued' do
      expect { raise described_class, 'spi failure' }
        .to raise_error(described_class, 'spi failure')
    end
  end

  describe ChromaWave::DependencyError do
    it 'inherits from ChromaWave::Error' do
      expect(described_class).to be < ChromaWave::Error
    end

    it 'does not inherit from DeviceError' do
      expect(described_class).not_to be < ChromaWave::DeviceError
    end

    it 'can be raised and rescued' do
      expect { raise described_class, 'missing dep' }
        .to raise_error(described_class, 'missing dep')
    end
  end

  describe ChromaWave::FormatMismatchError do
    it 'inherits from ArgumentError' do
      expect(described_class).to be < ArgumentError
    end

    it 'does not inherit from ChromaWave::Error' do
      expect(described_class).not_to be < ChromaWave::Error
    end

    it 'can be raised and rescued as ArgumentError' do
      expect { raise described_class, 'wrong format' }
        .to raise_error(ArgumentError, 'wrong format')
    end
  end

  describe ChromaWave::ModelNotFoundError do
    it 'inherits from ArgumentError' do
      expect(described_class).to be < ArgumentError
    end

    it 'does not inherit from ChromaWave::Error' do
      expect(described_class).not_to be < ChromaWave::Error
    end

    it 'can be raised and rescued as ArgumentError' do
      expect { raise described_class, 'no such model' }
        .to raise_error(ArgumentError, 'no such model')
    end
  end
end
