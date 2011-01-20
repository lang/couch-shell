# -*- encoding: utf-8 -*-

require "json"
require "couch-shell/json_value"

module CouchShell

  class Response

    JSON_CONTENT_TYPES = [
      "application/json", "text/plain"
    ].freeze

    # +response+ is a HTTP::Message from httpclient library, or a Net::HTTP
    # response
    def initialize(response)
      @res = response
      @json = nil
      @computed_json = false
    end

    # Response body parsed as json. nil if body is empty, false if
    # parsing failed.
    def json
      unless @computed_json
        if JSON_CONTENT_TYPES.include?(content_type) &&
            !body.nil? && !body.empty?
          begin
            @json = JsonValue.wrap(JSON.parse(body))
          rescue JSON::ParserError
            @json = false
          end
        end
        @computed_json = true
      end
      @json
    end

    def code
      @res.respond_to?(:status) ? @res.status.to_s : @res.code
    end

    def message
      @res.respond_to?(:message) ? @res.message : @res.reason
    end

    def ok?
      code.start_with?("2")
    end

    def body
      @res.respond_to?(:content) ? @res.content : @res.body
    end

    def content_type
      @res.respond_to?(:content_type) ?
        @res.content_type :
        @res.contenttype.sub(/;[^;]*\z/, '')
    end

    def attr(name, altname = nil)
      name = name.to_sym
      altname = altname ? altname.to_sym : nil
      if json
        if json.respond_to?(name)
          json.__send__ name
        elsif altname && json.respond_to?(altname)
          json.__send__ altname
        end
      end
    end

  end

end
