# frozen_string_literal: true

RSpec.describe ChromaWave::RefreshScheduler do
  describe '#initialize' do
    it 'uses default values' do
      scheduler = described_class.new
      expect(scheduler.partial_limit).to eq(5)
      expect(scheduler.min_interval).to eq(180)
      expect(scheduler.auto_full_refresh?).to be true
      expect(scheduler.partial_count).to eq(0)
      expect(scheduler.last_refresh_at).to be_nil
    end

    it 'accepts custom partial_limit' do
      scheduler = described_class.new(partial_limit: 10)
      expect(scheduler.partial_limit).to eq(10)
    end

    it 'accepts custom min_interval' do
      scheduler = described_class.new(min_interval: 60)
      expect(scheduler.min_interval).to eq(60)
    end

    it 'accepts auto_full_refresh: false' do
      scheduler = described_class.new(auto_full_refresh: false)
      expect(scheduler.auto_full_refresh?).to be false
    end
  end

  describe '#track_partial!' do
    it 'increments the partial count' do
      scheduler = described_class.new
      expect { scheduler.track_partial! }
        .to change(scheduler, :partial_count).from(0).to(1)
    end

    it 'accumulates across multiple calls' do
      scheduler = described_class.new
      3.times { scheduler.track_partial! }
      expect(scheduler.partial_count).to eq(3)
    end

    it 'sets last_refresh_at' do
      scheduler = described_class.new
      expect(scheduler.last_refresh_at).to be_nil
      scheduler.track_partial!
      expect(scheduler.last_refresh_at).to be_a(Float)
    end
  end

  describe '#track_full!' do
    it 'resets the partial count to zero' do
      scheduler = described_class.new
      3.times { scheduler.track_partial! }
      expect { scheduler.track_full! }
        .to change(scheduler, :partial_count).from(3).to(0)
    end

    it 'sets last_refresh_at' do
      scheduler = described_class.new
      scheduler.track_full!
      expect(scheduler.last_refresh_at).to be_a(Float)
    end

    it 'updates last_refresh_at on subsequent calls' do
      scheduler = described_class.new
      scheduler.track_full!
      first_time = scheduler.last_refresh_at
      scheduler.track_full!
      expect(scheduler.last_refresh_at).to be >= first_time
    end
  end

  describe '#needs_full?' do
    it 'returns false when count is below limit' do
      scheduler = described_class.new(partial_limit: 5)
      4.times { scheduler.track_partial! }
      expect(scheduler.needs_full?).to be false
    end

    it 'returns true when count equals limit' do
      scheduler = described_class.new(partial_limit: 5)
      5.times { scheduler.track_partial! }
      expect(scheduler.needs_full?).to be true
    end

    it 'returns true when count exceeds limit' do
      scheduler = described_class.new(partial_limit: 5)
      6.times { scheduler.track_partial! }
      expect(scheduler.needs_full?).to be true
    end

    it 'returns false after a full refresh resets the count' do
      scheduler = described_class.new(partial_limit: 5)
      5.times { scheduler.track_partial! }
      scheduler.track_full!
      expect(scheduler.needs_full?).to be false
    end
  end

  describe '#check_interval!' do
    it 'does not warn on the first refresh (last_refresh_at is nil)' do
      scheduler = described_class.new(min_interval: 9999)
      expect { scheduler.check_interval! }.not_to output.to_stderr
    end

    it 'warns when elapsed time is less than min_interval' do
      scheduler = described_class.new(min_interval: 9999)
      scheduler.track_partial!
      expect { scheduler.check_interval! }
        .to output(/Refresh interval too short/).to_stderr
    end

    it 'includes elapsed and minimum times in the warning' do
      scheduler = described_class.new(min_interval: 9999)
      scheduler.track_partial!
      expect { scheduler.check_interval! }
        .to output(/< 9999s minimum/).to_stderr
    end

    it 'does not warn when min_interval is 0' do
      scheduler = described_class.new(min_interval: 0)
      scheduler.track_partial!
      expect { scheduler.check_interval! }.not_to output.to_stderr
    end
  end

  describe '#auto_full_refresh?' do
    it 'returns true by default' do
      expect(described_class.new.auto_full_refresh?).to be true
    end

    it 'returns false when disabled' do
      expect(described_class.new(auto_full_refresh: false).auto_full_refresh?).to be false
    end
  end

  describe '#reset!' do
    it 'resets partial count to zero' do
      scheduler = described_class.new
      3.times { scheduler.track_partial! }
      expect { scheduler.reset! }
        .to change(scheduler, :partial_count).from(3).to(0)
    end

    it 'does not change last_refresh_at' do
      scheduler = described_class.new
      scheduler.track_partial!
      timestamp = scheduler.last_refresh_at
      scheduler.reset!
      expect(scheduler.last_refresh_at).to eq(timestamp)
    end
  end

  describe 'input validation' do
    it 'raises ArgumentError for partial_limit: 0' do
      expect { described_class.new(partial_limit: 0) }
        .to raise_error(ArgumentError, /partial_limit must be >= 1/)
    end

    it 'raises ArgumentError for negative partial_limit' do
      expect { described_class.new(partial_limit: -1) }
        .to raise_error(ArgumentError, /partial_limit must be >= 1/)
    end

    it 'raises ArgumentError for negative min_interval' do
      expect { described_class.new(min_interval: -5) }
        .to raise_error(ArgumentError, /min_interval must be >= 0/)
    end

    it 'accepts partial_limit: 1' do
      scheduler = described_class.new(partial_limit: 1)
      expect(scheduler.needs_full?).to be false
      scheduler.track_partial!
      expect(scheduler.needs_full?).to be true
    end

    it 'accepts min_interval: 0' do
      expect { described_class.new(min_interval: 0) }.not_to raise_error
    end
  end
end
