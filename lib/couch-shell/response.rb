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
      @json_value = nil
      @computed_json_value = false
    end

    # Response body parsed as json, represented as a ruby data structure. nil
    # if body is empty, false if parsing failed.
    def json
      json_value ? json_value.unwrapped! : json_value
    end

    # Like json, but wrapped in a CouchShell::JsonValue.
    def json_value
      unless @computed_json_value
        if JSON_CONTENT_TYPES.include?(content_type) &&
            !body.nil? && !body.empty?
          begin
            @json_value = JsonValue.wrap(JSON.parse(body))
          rescue JSON::ParserError
            @json_value = false
          end
        end
        @computed_json_value = true
      end
      @json_value
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
      if json_value
        if json_value.respond_to?(name)
          json_value.__send__ name
        elsif altname && json_value.respond_to?(altname)
          json_value.__send__ altname
        end
      end
    end

  end

end
