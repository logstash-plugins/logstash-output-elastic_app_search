# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/elastic_workplace_search"
require "logstash/codecs/plain"
require "logstash/event"
require "json"
require "base64"

describe "indexing against running Workplace Search", :integration => true do

  let(:url) { ENV['ENTERPRISE_SEARCH_URL'] }
  let(:auth) { Base64.strict_encode64("#{ENV['ENTERPRISE_SEARCH_USERNAME']}:#{ENV['ENTERPRISE_SEARCH_PASSWORD']}") }
  let(:source) do
    response = Faraday.post(
      "#{url}/ws/org/sources/form_create",
      JSON.dump("service_type" => "custom", "name" => "whatever"),
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "Authorization" => "Basic #{auth}"
    )
    JSON.load(response.body)
  end
  let(:source_id) { source.fetch("id") }

  let(:config) do
    {
      "url" => url,
      "source" => source_id,
      "access_token" => source.fetch("accessToken")
    }
  end

  subject(:workplace_search_output) { LogStash::Outputs::ElasticWorkplaceSearch.new(config) }

  before(:each) { workplace_search_output.register }

  describe "single event" do
    let(:event) { LogStash::Event.new("message" => "an event to index") }

    it "should be indexed" do
      workplace_search_output.multi_receive([event])

      results = Stud.try(20.times, RSpec::Expectations::ExpectationNotMetError) do
        attempt_response = execute_search_call
        expect(attempt_response.status).to eq(200)
        parsed_resp = JSON.parse(attempt_response.body)
        expect(parsed_resp.dig("meta", "page", "total_pages")).to eq(1)
        parsed_resp["results"]
      end
      expect(results.first.fetch("message")).to eq "an event to index"
    end
  end

  describe "multiple events" do
    let(:events) { generate_events(200) } #2 times the slice size used to batch

    it "all should be indexed" do
      workplace_search_output.multi_receive(events)
      results = Stud.try(20.times, RSpec::Expectations::ExpectationNotMetError) do
        attempt_response = execute_search_call
        expect(attempt_response.status).to eq(200)
        parsed_resp = JSON.parse(attempt_response.body)
        expect(parsed_resp.dig("meta", "page", "total_results")).to eq(200)
        parsed_resp["results"]
      end
      expect(results.first.fetch("message")).to start_with("an event to index")
    end
  end

  private
  def execute_search_call
    Faraday.post(
      "#{url}/ws/org/sources/#{source_id}/documents",
      nil,
      "Accept" => "application/json",
      "Authorization" => "Basic #{auth}"
    )
  end

  def generate_events(num_events)
    (1..num_events).map { |i| LogStash::Event.new("message" => "an event to index #{i}")}
  end
end
