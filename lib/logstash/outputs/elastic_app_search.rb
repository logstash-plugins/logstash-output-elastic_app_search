# encoding: utf-8
require "logstash/outputs/base"
require "elastic-app-search"

class LogStash::Outputs::ElasticAppSearch < LogStash::Outputs::Base
  config_name "elastic_app_search"

  config :engine, :validate => :string, :required => true
  config :host, :validate => :string
  config :url, :validate => :string
  config :api_key, :validate => :password, :required => true
  config :timestamp_destination, :validate => :string
  config :document_id, :validate => :string
  config :path, :validate => :string, :default => "/api/as/v1/"

  ENGINE_WITH_SPRINTF_REGEX = /^.*%\{.+\}.*$/

  public
  def register
    if @host.nil? && @url.nil?
      raise ::LogStash::ConfigurationError.new("Please specify either \"url\" (for self-managed) or \"host\" (for SaaS).")
    elsif @host && @url
      raise ::LogStash::ConfigurationError.new("Both \"url\" or \"host\" can't be set simultaneously. Please specify either \"url\" (for self-managed) or \"host\" (for SaaS).")
    elsif @host && path_is_set?  # because path has a default value we need extra work to if the user set it
      raise ::LogStash::ConfigurationError.new("The setting \"path\" is not compatible with \"host\". Use \"path\" only with \"url\".")
    elsif @host
      @client = Elastic::AppSearch::Client.new(:host_identifier => @host, :api_key => @api_key.value)
    elsif @url
      @client = Elastic::AppSearch::Client.new(:api_endpoint => @url + @path, :api_key => @api_key.value)
    end
    check_connection! unless @engine =~ ENGINE_WITH_SPRINTF_REGEX
  rescue => e
    if e.message =~ /401/
      raise ::LogStash::ConfigurationError.new("Failed to connect to App Search. Error: 401. Please check your credentials")
    elsif e.message =~ /404/
      raise ::LogStash::ConfigurationError.new("Failed to connect to App Search. Error: 404. Please check if host '#{@host}' is correct and you've created an engine with name '#{@engine}'")
    else
      raise ::LogStash::ConfigurationError.new("Failed to connect to App Search. #{e.message}")
    end
  end

  public
  def multi_receive(events)
    # because App Search has a limit of 100 documents per bulk
    events.each_slice(100) do |events|
      batch = format_batch(events)
      if @logger.trace?
        @logger.trace("Sending bulk to AppSearch", :size => batch.size, :data => batch.inspect)
      end
      index(batch)
    end
  end

  private
  def format_batch(events)
    docs_for_engine = {}
    events.each do |event|
      doc = event.to_hash
      # we need to remove default fields that start with "@"
      # since Elastic App Search doesn't accept them
      if @timestamp_destination
        doc[@timestamp_destination] = doc.delete("@timestamp")
      else # delete it
        doc.delete("@timestamp")
      end
      if @document_id
        doc["id"] = event.sprintf(@document_id)
      end
      doc.delete("@version")
      resolved_engine = event.sprintf(@engine)
      unless docs_for_engine[resolved_engine]
        if @logger.debug?
          @logger.debug("Creating new engine segment in batch to send", :resolved_engine => resolved_engine)
        end
        docs_for_engine[resolved_engine] = []
      end
      docs_for_engine[resolved_engine] << doc
    end
    docs_for_engine
  end

  def index(batch)
    batch.each do |resolved_engine, documents|
      begin
        if resolved_engine =~ ENGINE_WITH_SPRINTF_REGEX || resolved_engine =~ /^\s*$/
          raise "Cannot resolve engine field name #{@engine} from event"
        end
        response = @client.index_documents(resolved_engine, documents)
        report(documents, response)
      rescue => e
        @logger.error("Failed to execute index operation. Retrying..", :exception => e.class, :reason => e.message,
                      :resolved_engine => resolved_engine)
        sleep(1)
        retry
      end
    end
  end

  def report(documents, response)
    documents.each_with_index do |document, i|
      errors = response[i]["errors"]
      if errors.empty?
        @logger.trace? && @logger.trace("Document was indexed with no errors", :document => document)
      else
        @logger.warn("Document failed to index. Dropping..", :document => document, :errors => errors.to_a)
      end
    end
  end

  def check_connection!
    @client.get_engine(@engine)
  end

  def path_is_set?
    original_params.key?("path")
  end
end
