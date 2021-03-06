# frozen_string_literal: true

require 'spec_helper'

describe SplitIoClient::Cache::Stores::SDKBlocker do
  RSpec.shared_examples 'SDK Blocker' do |cache_adapter|
    let(:config) do
      config = SplitIoClient::SplitConfig.new(cache_adapter: cache_adapter)
      config.block_until_ready = 0.1
      config
    end
    let(:splits_repository) { SplitIoClient::Cache::Repositories::SplitsRepository.new(config) }
    let(:segments_repository) { SplitIoClient::Cache::Repositories::SegmentsRepository.new(config) }
    let(:sdk_blocker) { described_class.new(splits_repository, segments_repository, config) }

    before :each do
      Redis.new.flushall
    end

    it 'is not ready after initialization' do
      sdk_blocker

      expect(splits_repository.ready?).to be(false)
    end

    it 'is ready when both splits and segments are ready' do
      sdk_blocker.splits_ready!
      sdk_blocker.segments_ready!

      expect(sdk_blocker.ready?).to be true
    end

    it 'throws exception if not ready' do
      allow_any_instance_of(described_class).to receive(:ready?).and_return(false)
      expect { sdk_blocker.block }.to raise_error(SplitIoClient::SDKBlockerTimeoutExpiredException)
    end
  end

  describe 'with Memory Adapter' do
    it_behaves_like 'SDK Blocker', :memory
  end

  describe 'with Redis Adapter' do
    it_behaves_like 'SDK Blocker', :redis
  end
end
