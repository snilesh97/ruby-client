# frozen_string_literal: true

require 'spec_helper'
require 'http_server_mock'

describe SplitIoClient::Engine::PushManager do
  subject { SplitIoClient::Engine::PushManager }

  let(:body_response) do
    File.read(File.join(SplitIoClient.root, 'spec/test_data/integrations/auth_body_response.json'))
  end

  let(:api_key) { 'api-key-test' }
  let(:log) { StringIO.new }
  let(:config) { SplitIoClient::SplitConfig.new(logger: Logger.new(log)) }
  let(:splits_repository) { SplitIoClient::Cache::Repositories::SplitsRepository.new(config) }
  let(:metrics_repository) { SplitIoClient::Cache::Repositories::MetricsRepository.new(config) }
  let(:segments_repository) { SplitIoClient::Cache::Repositories::SegmentsRepository.new(config) }
  let(:sdk_blocker) { SplitIoClient::Cache::Stores::SDKBlocker.new(splits_repository, segments_repository, config) }
  let(:metrics) { SplitIoClient::Metrics.new(100, metrics_repository) }
  let(:split_fetcher) do
    SplitIoClient::Cache::Fetchers::SplitFetcher.new(splits_repository, api_key, metrics, config, sdk_blocker)
  end
  let(:segment_fetcher) do
    SplitIoClient::Cache::Fetchers::SegmentFetcher.new(segments_repository, api_key, metrics, config, sdk_blocker)
  end
  let(:splits_worker) { SplitIoClient::SSE::Workers::SplitsWorker.new(split_fetcher, config, splits_repository) }
  let(:segments_worker) { SplitIoClient::SSE::Workers::SegmentsWorker.new(segment_fetcher, config, segments_repository) }
  let(:notification_manager_keeper) { SplitIoClient::SSE::NotificationManagerKeeper.new(config) }
  let(:repositories) { { splits: splits_repository, segments: segments_repository, metrics: metrics_repository } }
  let(:impression_counter) { SplitIoClient::Engine::Common::ImpressionCounter.new }
  let(:params) { { split_fetcher: split_fetcher, segment_fetcher: segment_fetcher, imp_counter: impression_counter } }
  let(:synchronizer) { SplitIoClient::Engine::Synchronizer.new(repositories, api_key, config, sdk_blocker, params) }

  context 'start_sse' do
    it 'must connect to server' do
      mock_server do |server|
        server.setup_response('/') do |_, res|
          send_mock_content(res, 'content')
        end

        stub_request(:get, config.auth_service_url).to_return(status: 200, body: body_response)
        config.streaming_service_url = server.base_uri

        connected_event = false
        disconnect_event = false
        sse_handler = SplitIoClient::SSE::SSEHandler.new(
          config,
          synchronizer,
          splits_repository,
          segments_repository,
          notification_manager_keeper
        ) do |handler|
          handler.on_connected { connected_event = true }
          handler.on_disconnect { disconnect_event = true }
        end

        push_manager = subject.new(config, sse_handler, api_key)
        push_manager.start_sse

        expect(a_request(:get, config.auth_service_url)).to have_been_made.times(1)

        sleep(1.5)

        expect(sse_handler.connected?).to eq(true)
        expect(connected_event).to eq(true)
        expect(disconnect_event).to eq(false)
      end
    end

    it 'must not connect to server. Auth server return 500' do
      stub_request(:get, config.auth_service_url).to_return(status: 500)

      connected_event = false
      disconnect_event = false
      sse_handler = SplitIoClient::SSE::SSEHandler.new(
        config,
        synchronizer,
        splits_repository,
        segments_repository,
        notification_manager_keeper
      ) do |handler|
        handler.on_connected { connected_event = true }
        handler.on_disconnect { disconnect_event = true }
      end

      push_manager = subject.new(config, sse_handler, api_key)
      push_manager.start_sse

      expect(a_request(:get, config.auth_service_url)).to have_been_made.times(1)

      sleep(1.5)

      expect(sse_handler.connected?).to eq(false)
      expect(connected_event).to eq(false)
      expect(disconnect_event).to eq(true)
    end

    it 'must not connect to server. Auth server return 401' do
      stub_request(:get, config.auth_service_url).to_return(status: 401)

      connected_event = false
      disconnect_event = false
      sse_handler = SplitIoClient::SSE::SSEHandler.new(
        config,
        synchronizer,
        splits_repository,
        segments_repository,
        notification_manager_keeper
      ) do |handler|
        handler.on_connected { connected_event = true }
        handler.on_disconnect { disconnect_event = true }
      end

      push_manager = subject.new(config, sse_handler, api_key)
      push_manager.start_sse

      expect(a_request(:get, config.auth_service_url)).to have_been_made.times(1)

      sleep(1.5)

      expect(sse_handler.connected?).to eq(false)
      expect(connected_event).to eq(false)
      expect(disconnect_event).to eq(true)
    end
  end

  context 'stop_sse' do
    it 'must disconnect from the server' do
      mock_server do |server|
        server.setup_response('/') do |_, res|
          send_mock_content(res, 'content')
        end

        stub_request(:get, config.auth_service_url).to_return(status: 200, body: body_response)
        config.streaming_service_url = server.base_uri

        connected_event = false
        disconnect_event = false
        sse_handler = SplitIoClient::SSE::SSEHandler.new(
          config,
          synchronizer,
          splits_repository,
          segments_repository,
          notification_manager_keeper
        ) do |handler|
          handler.on_connected { connected_event = true }
          handler.on_disconnect { disconnect_event = true }
        end

        push_manager = subject.new(config, sse_handler, api_key)
        push_manager.start_sse

        expect(a_request(:get, config.auth_service_url)).to have_been_made.times(1)

        sleep(1.5)

        expect(sse_handler.connected?).to eq(true)
        expect(connected_event).to eq(true)
        expect(disconnect_event).to eq(false)

        push_manager.stop_sse
        expect(sse_handler.connected?).to eq(false)
        expect(disconnect_event).to eq(true)
      end
    end
  end
end

def send_mock_content(res, content)
  res.content_type = 'text/event-stream'
  res.status = 200
  res.chunked = true
  rd, wr = IO.pipe
  wr.write(content)
  res.body = rd
  wr.close
  wr
end
