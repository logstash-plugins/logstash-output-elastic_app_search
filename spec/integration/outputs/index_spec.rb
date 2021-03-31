# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/elastic_app_search"
require "logstash/codecs/plain"
require "logstash/event"
require "json"

describe "indexing against running AppSearch", :integration => true do

  let(:engine_name) do
    (0...10).map { ('a'..'z').to_a[rand(26)] }.join
  end

  let(:config) do
    {
      "api_key" => ENV['APPSEARCH_PRIVATE_KEY'],
      "engine" => engine_name,
      "url" => "http://appsearch:3002"
    }
  end

  subject(:app_search_output) { LogStash::Outputs::ElasticAppSearch.new(config) }

  before(:each) do
    create_engine(engine_name, "http://appsearch:3002", ENV['APPSEARCH_PRIVATE_KEY'])
  end

  private
  def create_engine(engine_name, host, api_key)
    url = host + "/api/as/v1/engines"
    resp = Faraday.post(url, "{\"name\": \"#{engine_name}\"}",
      "Content-Type" => "application/json",
      "Authorization" => "Bearer " + api_key)
    expect(resp.status).to eq(200)
  end

  describe "search and private keys are configured" do
    let(:api_key_settings) do
      {
        :private => ENV['APPSEARCH_PRIVATE_KEY'],
        :search => ENV['APPSEARCH_SEARCH_KEY']
      }
    end

    it "setup apikeys" do
      expect(api_key_settings[:private]).to start_with("private-")
      expect(api_key_settings[:search]).to start_with("search-")
    end
  end

  describe "register" do
    let(:config) do
      {
        "api_key" => ENV['APPSEARCH_PRIVATE_KEY'],
        "engine" => "%{engine_name_field}",
        "url" => "http://appsearch:3002"
      }
    end

    context "when engine is defined in sprintf format" do
      it "does not raise an error" do
        expect { subject.register }.to_not raise_error
      end
    end
  end

  describe "indexing" do

    before do
      app_search_output.register
    end

    describe "single event" do
      let(:event) { LogStash::Event.new("message" => "an event to index") }

      it "should be indexed" do
        app_search_output.multi_receive([event])

        results = Stud.try(20.times, RSpec::Expectations::ExpectationNotMetError) do
          attempt_response = execute_search_call(engine_name)
          expect(attempt_response.status).to eq(200)
          parsed_resp = JSON.parse(attempt_response.body)
          expect(parsed_resp.dig("meta", "page", "total_pages")).to eq(1)
          parsed_resp["results"]
        end
        expect(results.first.dig("message", "raw")).to eq "an event to index"
      end

      context "using sprintf-ed engine" do
        let(:config) do
          {
            "api_key" => ENV['APPSEARCH_PRIVATE_KEY'],
            "engine" => "%{engine_name_field}",
            "url" => "http://appsearch:3002"
          }
        end

        let(:event) { LogStash::Event.new("message" => "an event to index", "engine_name_field" => engine_name) }

        it "should be indexed" do
          app_search_output.multi_receive([event])

          results = Stud.try(20.times, RSpec::Expectations::ExpectationNotMetError) do
            attempt_response = execute_search_call(engine_name)
            expect(attempt_response.status).to eq(200)
            parsed_resp = JSON.parse(attempt_response.body)
            expect(parsed_resp.dig("meta", "page", "total_pages")).to eq(1)
            parsed_resp["results"]
          end
          expect(results.first.dig("message", "raw")).to eq "an event to index"
        end
      end
    end

    private
    def execute_search_call(engine_name)
      url = config["url"] + "/api/as/v1/engines/#{engine_name}/search"
      resp = Faraday.post(url, '{"query": "event"}',
            "Content-Type" => "application/json",
            "Authorization" => "Bearer " + config["api_key"])
    end

    describe "multiple events" do
      context "single static engine" do
        let(:events) { generate_events(200) } #2 times the slice size used to batch

        it "all should be indexed" do
          app_search_output.multi_receive(events)

          expect_indexed(engine_name, 200)
        end
      end

      context "multiple sprintf engines" do
        let(:config) do
          {
            "api_key" => ENV['APPSEARCH_PRIVATE_KEY'],
            "engine" => "%{engine_name_field}",
            "url" => "http://appsearch:3002"
          }
        end

        it "all should be indexed" do
         create_engine('testengin1', "http://appsearch:3002", ENV['APPSEARCH_PRIVATE_KEY'])
         create_engine('testengin2', "http://appsearch:3002", ENV['APPSEARCH_PRIVATE_KEY'])
         events = generate_events(100, 'testengin1')
         events += generate_events(100, 'testengin2')
         events.shuffle!

         app_search_output.multi_receive(events)

         expect_indexed('testengin1', 100)
         expect_indexed('testengin2', 100)
        end
      end
    end

    private
    def expect_indexed(engine_name, expected_docs_count)
      results = Stud.try(20.times, RSpec::Expectations::ExpectationNotMetError) do
        attempt_response = execute_search_call(engine_name)
        expect(attempt_response.status).to eq(200)
        parsed_resp = JSON.parse(attempt_response.body)
        expect(parsed_resp.dig("meta", "page", "total_results")).to eq(expected_docs_count)
        parsed_resp["results"]
      end
      expect(results.first.dig("message", "raw")).to start_with("an event to index")
    end

    def generate_events(num_events, engine_name = nil)
      (1..num_events).map do |i|
        if engine_name
          LogStash::Event.new("message" => "an event to index #{i}", "engine_name_field" => engine_name)
        else
          LogStash::Event.new("message" => "an event to index #{i}")
        end
      end
    end
  end
end