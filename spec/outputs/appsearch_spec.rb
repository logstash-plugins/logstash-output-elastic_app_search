# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/elastic_app_search"
require "logstash/codecs/plain"
require "logstash/event"

describe LogStash::Outputs::ElasticAppSearch do
  let(:sample_event) { LogStash::Event.new }
  let(:host) { "test-host" }
  let(:api_key) { "my_key" }
  let(:engine) { "test-engine" }
  subject { described_class.new(config) }

  describe "#register" do
    before(:each) do
      allow(subject).to receive(:check_connection!)
    end
    context "when host is configured" do
      let(:config) { { "host" => host, "api_key" => api_key, "engine" => engine } }
      it "does not raise an error" do
        expect { subject.register }.to_not raise_error
      end
    end
    context "when host and path is configured" do
      let(:config) { { "host" => host, "api_key" => api_key, "engine" => engine, "path" => "/v1" } }
      it "raises an error" do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end
    context "when host and url is configured" do
      let(:config) { { "host" => host, "api_key" => api_key, "engine" => engine, "url" => "http://localhost:9300" } }
      it "raises an error" do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end
    context "when neither host nor url is configured" do
      let(:config) { { "api_key" => api_key, "engine" => engine } }
      it "raises an error" do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end
    context "when engine is in sprintf format" do
      let(:config) { { "host" => host, "api_key" => api_key, "engine" => "%{type}" } }
      it "connection is not checked" do
        expect { subject.register }.to_not raise_error
        expect(subject).not_to receive(:check_connection!)
      end
    end
  end
end
