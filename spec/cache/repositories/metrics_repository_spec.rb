# frozen_string_literal: true

require 'spec_helper'

describe SplitIoClient::Cache::Repositories::MetricsRepository do
  RSpec.shared_examples 'Metrics Repository' do |cache_adapter|
    let(:repository) { described_class.new(@default_config) }
    let(:binary_search) { SplitIoClient::BinarySearchLatencyTracker.new }

    before :each do
      Redis.new.flushall
    end

    it 'does not return zero latencies' do
      @default_config.cache_adapter = cache_adapter
      repository.add_latency('foo', 0, binary_search)

      expect(repository.latencies.keys).to eq(%w[foo])
    end
  end

  describe 'with Memory Adapter' do
    it_behaves_like 'Metrics Repository', SplitIoClient::Cache::Adapters::MemoryAdapter.new(
      SplitIoClient::Cache::Adapters::MemoryAdapters::MapAdapter.new
    )
  end

  describe 'with Redis Adapter' do
    it_behaves_like 'Metrics Repository', SplitIoClient::Cache::Adapters::RedisAdapter.new(
      SplitIoClient::SplitConfig.default_redis_url
    )
  end
end
