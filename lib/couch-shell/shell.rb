# -*- encoding: utf-8 -*-

require "uri"
require "net/http"
require "json"
require "highline"

module CouchShell

  class Shell

    class BreakReplLoop < Exception
    end

    class ShellUserError < Exception
    end

    class UndefinedVariable < ShellUserError

      attr_reader :varname

      def initialize(varname)
        @varname = varname
      end

    end

    PREDEFINED_VARS = ["uuid", "id", "rev", "idr", "content-type"].freeze
    JSON_CONTENT_TYPES = ["application/json", "text/plain"].freeze

    def initialize(stdin, stdout, stderr)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @server_url = nil
      @pathstack = []
      @highline = HighLine.new(@stdin, @stdout)
      @last_response = nil
      @last_response_json = nil
    end

    def server=(url)
      if url
        @server_url = URI.parse(url.sub(%r{/\z}, ''))
        msg "Set server to #{@server_url.scheme}://" +
          "#{@server_url.host}:#{@server_url.port}/#{@server_url.path}"
        request("GET", nil)
      else
        @server_url = nil
        msg "Set server to none."
      end
    end

    def cd(path, get = false)
      old_pathstack = @pathstack.dup
      case path
      when nil
        @pathstack = []
      when ".."
        if @pathstack.empty?
          errmsg "Already at server root, can't go up."
        else
          @pathstack.pop
        end
      when %r{\A/}
        @pathstack = path[1..-1].split("/")
      else
        @pathstack.concat path.split("/")
      end
      if get
        if request("GET", nil) != "200"
          @pathstack = old_pathstack
        end
      end
    end

    def msg(str, newline = true)
      @stdout.print @highline.color(str, :blue)
      if newline
        @stdout.puts
      else
        @stdout.flush
      end
    end

    def errmsg(str)
      @stderr.puts @highline.color(str, :red)
    end

    def response_info(str)
      @stdout.puts @highline.color(str, :cyan)
    end

    def print_last_response
      res = @last_response
      response_info "#{res.code} #{res.message}"
      if res.body
        if JSON_CONTENT_TYPES.include?(res.content_type)
          @stdout.puts JSON.pretty_generate(last_response_json)
        else
          @stdout.puts res.body if res.body
        end
      end
    end

    def response_json(res)
      if !res || res.body.nil? || res.body.empty?
        return nil
      end
      JSON.parse res.body
    rescue ParseError
      false
    end

    def last_response_json
      if @last_response_json
        return @last_response_json
      end
      if @last_response
        @last_response_json = response_json(@last_response)
      end
    end

    def last_response_ok?
      @last_response && @last_response.code == "200"
    end

    def last_response_attr(name, altname = nil)
      json = last_response_json
      if json && json.kind_of?(Hash) &&
          (json.has_key?(name) || json.has_key?(altname))
        json.has_key?(name) ? json[name] : json[altname]
      end
    end

    def request(method, path, body = nil)
      unless @server_url
        errmsg "Server not set - can't perform request."
        return
      end
      fpath = full_path(path)
      msg "#{method} #{fpath} ", false
      if @server_url.scheme != "http"
        errmsg "Protocol #{@server_url.scheme} not supported, use http."
        return
      end
      rescode = nil
      Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        req = (case method
               when "GET"
                 Net::HTTP::Get
               when "PUT"
                 Net::HTTP::Put
               when "DELETE"
                 Net::HTTP::Delete
               else
                 raise "unsupported http method: `#{method}'"
               end).new(fpath)
        req.body = body if body
        res = http.request(req)
        @last_response = res
        @last_response_json = nil
        rescode = res.code
        print_last_response
      end
      rescode
    end

    def full_path(path)
      stack = []
      if path !~ %r{\A/}
        stack = @pathstack.dup
      end
      if @server_url.path && !@server_url.path.empty?
        stack.unshift @server_url.path
      end
      if path && !path.empty? && path != "/"
        stack.push path
      end
      fpath = stack.join("/")
      if fpath !~ %r{\A/}
        "/" + fpath
      else
        fpath
      end
    end

    def read
      lead = @pathstack.empty? ? ">>" : @pathstack.join("/") + " >>"
      begin
        @highline.ask(@highline.color(lead, :yellow) + " ") { |q|
          q.readline = true
        }
      rescue NoMethodError
        # this is BAD, but highline 1.6.1 reacts to CTRL+D with a NoMethodError
        return nil
      end
    end

    def rep
      input = read
      case input
      when nil
        raise BreakReplLoop
      when ""
        # do nothing
      else
        command, argstr = input.split(/\s+/, 2)
        command_message = :"command_#{command.downcase}"
        if self.respond_to?(command_message)
          send command_message, argstr
        else
          errmsg "unknown command `#{command}'"
        end
      end
    end

    def repl
      loop {
        begin
          rep
        rescue Interrupt
          @stdout.puts
          errmsg "interrupted"
        rescue UndefinedVariable => e
          errmsg "Variable `" + e.varname + "' is not defined."
        rescue ShellUserError => e
          errmsg e.message
        end
      }
    rescue BreakReplLoop
      msg "bye"
    end

    def interpolate(str)
      return nil if str.nil?
      String.new.force_encoding(str.encoding).tap { |res|
        escape = false
        dollar = false
        var = nil
        str.each_char { |c|
          if escape
            res << c
            escape = false
            next
          elsif c == '\\'
            escape = true
          elsif c == '$'
            dollar = true
            next
          elsif c == '('
            if dollar
              var = ""
            else
              res << c
            end
          elsif c == ')'
            if var
              res << var_interpolation_val(var)
              var = nil
            else
              res << c
            end
          elsif dollar
            res << "$"
          elsif var
            var << c
          else
            res << c
          end
          dollar = false
        }
      }
    end

    def var_interpolation_val(var)
      case var
      when "uuid"
        command_uuids nil
        if last_response_ok?
          json = last_response_json
          if json && (uuids = json["uuids"]) && uuids.kind_of?(Array) && uuids.size > 0
            uuids[0]
          else
            raise ShellUserError,
              "interpolation failed due to unkown json structure"
          end
        else
          raise ShellUserError, "interpolation failed"
        end
      when "id"
        last_response_attr("id", "_id") or
          raise ShellUserError, "variable `id' not set"
      when "rev"
        last_response_attr("rev", "_rev") or
          raise ShellUserError, "variable `rev' not set"
      when "idr"
        "#{var_interpolation_val 'id'}?rev=#{var_interpolation_val 'rev'}"
      when "content-type"
        @last_response && @last_response.content_type
      else
        raise UndefinedVariable.new(var)
      end
    end

    def command_get(argstr)
      request "GET", interpolate(argstr)
    end

    def command_put(argstr)
      url, body = argstr.split(/\s+/, 2)
      request "PUT", interpolate(url), body
    end

    def command_delete(argstr)
      request "DELETE", interpolate(argstr)
    end

    def command_cd(argstr)
      cd interpolate(argstr), false
    end

    def command_cg(argstr)
      cd interpolate(argstr), true
    end

    def command_exit(argstr)
      raise BreakReplLoop
    end

    def command_quit(argstr)
      raise BreakReplLoop
    end

    def command_uuids(argstr)
      count = argstr ? argstr.to_i : 1
      request "GET", "/_uuids?count=#{count}"
    end

    def command_echo(argstr)
      if argstr
        @stdout.puts interpolate(argstr)
      end
    end

    def command_print(argstr)
      unless argstr
        errmsg "variable name required"
        return
      end
      @stdout.puts var_interpolation_val(argstr)
    end

  end

end
