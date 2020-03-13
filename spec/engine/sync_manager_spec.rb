# frozen_string_literal: true

require 'spec_helper'
require 'http_server_mock'

describe SplitIoClient::Engine::SyncManager do
  subject { SplitIoClient::Engine::SyncManager }

  let(:splits) { File.read(File.join(SplitIoClient.root, 'spec/test_data/integrations/splits.json')) }
  let(:segment1) { File.read(File.join(SplitIoClient.root, 'spec/test_data/integrations/segment1.json')) }
  let(:segment2) { File.read(File.join(SplitIoClient.root, 'spec/test_data/integrations/segment2.json')) }
  let(:segment3) { File.read(File.join(SplitIoClient.root, 'spec/test_data/integrations/segment3.json')) }
  let(:body_response) do
    File.read(File.join(SplitIoClient.root, 'spec/test_data/integrations/auth_body_response.json'))
  end

  let(:api_key) { 'api-key-test' }
  let(:log) { StringIO.new }
  let(:config) { SplitIoClient::SplitConfig.new(logger: Logger.new(log)) }
  let(:splits_repository) { SplitIoClient::Cache::Repositories::SplitsRepository.new(config) }
  let(:segments_repository) { SplitIoClient::Cache::Repositories::SegmentsRepository.new(config) }
  let(:impressions_repository) { SplitIoClient::Cache::Repositories::ImpressionsRepository.new(config) }
  let(:metrics_repository) { SplitIoClient::Cache::Repositories::MetricsRepository.new(config) }
  let(:events_repository) { SplitIoClient::Cache::Repositories::EventsRepository.new(config, api_key) }
  let(:sdk_blocker) { SDKBlocker.new(splits_repository, segments_repository, config) }

  before do
    mock_split_changes_with_since(splits, '-1')
    mock_split_changes_with_since(splits, '1506703262916')
    mock_segment_changes('segment1', segment1, '-1')
    mock_segment_changes('segment1', segment1, '1470947453877')
    mock_segment_changes('segment2', segment2, '-1')
    mock_segment_changes('segment2', segment2, '1470947453878')
    mock_segment_changes('segment3', segment3, '-1')
    mock_segment_changes('segment3', segment3, '1470947453879')
    stub_request(:get, config.auth_service_url).to_return(status: 200, body: body_response)
  end

  it 'start sync manager with success sse connection.' do
    mock_server do |server|
      server.setup_response('/') do |_, res|
        send_content(res, 'content', keep_open: false)
      end

      config.sse_host_url = server.base_uri
      repositories = {}
      repositories[:splits] = splits_repository
      repositories[:segments] = segments_repository
      repositories[:impressions] = impressions_repository
      repositories[:metrics] = metrics_repository
      repositories[:events] = events_repository

      sync_manager = subject.new(repositories, api_key, config, sdk_blocker)
      sync_manager.start

      sleep(2)
      expect(a_request(:get, 'https://sdk.split.io/api/splitChanges?since=-1')).to have_been_made.once
      expect(a_request(:get, 'https://sdk.split.io/api/splitChanges?since=1506703262916')).to have_been_made.once
      expect(config.threads.size).to eq(9)
    end
  end

  it 'start sync manager with wrong sse host url and non connect to server, must start polling.' do
    mock_server do |server|
      server.setup_response('/') do |_, res|
        send_content(res, 'content', keep_open: false)
      end

      config.sse_host_url = 'https://fake-sse.io'
      config.connection_timeout = 1

      repositories = {}
      repositories[:splits] = splits_repository
      repositories[:segments] = segments_repository
      repositories[:impressions] = impressions_repository
      repositories[:metrics] = metrics_repository
      repositories[:events] = events_repository

      sync_manager = subject.new(repositories, api_key, config, sdk_blocker)
      sync_manager.start

      sleep(2)
      expect(a_request(:get, 'https://sdk.split.io/api/splitChanges?since=-1')).to have_been_made.once
      expect(a_request(:get, 'https://sdk.split.io/api/splitChanges?since=1506703262916')).to have_been_made.once
      expect(config.threads.size).to eq(6)
    end
  end
end

private

def mock_split_changes_with_since(splits_json, since)
  stub_request(:get, "https://sdk.split.io/api/splitChanges?since=#{since}")
    .to_return(status: 200, body: splits_json)
end

def mock_segment_changes(segment_name, segment_json, since)
  stub_request(:get, "https://sdk.split.io/api/segmentChanges/#{segment_name}?since=#{since}")
    .to_return(status: 200, body: segment_json)
end

def send_content(res, content, keep_open:)
  res.content_type = 'text/event-stream'
  res.status = 200
  res.chunked = true
  rd, wr = IO.pipe
  wr.write(content)
  res.body = rd
  wr.close unless keep_open
  wr
end
