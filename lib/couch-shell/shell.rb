# -*- encoding: utf-8 -*-

require "uri"
require "net/http"
require "highline"
require "couch-shell/response"
require "couch-shell/ring_buffer"
require "couch-shell/eval_context"

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

    PREDEFINED_VARS = [
      "uuid", "id", "rev", "idr",
      "content-type", "server"
    ].freeze

    JSON_DOC_START_RX = /\A[ \t\n\r]*[\(\{]/

    def initialize(stdin, stdout, stderr)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @server_url = nil
      @pathstack = []
      @highline = HighLine.new(@stdin, @stdout)
      @responses = RingBuffer.new(10)
      @eval_context = EvalContext.new(self)
    end

    def normalize_server_url(url)
      return nil if url.nil?
      # remove trailing slash
      url = url.sub(%r{/\z}, '')
      # prepend http:// if scheme is omitted
      if url =~ /\A\p{Alpha}(?:\p{Alpha}|\p{Digit}|\+|\-|\.)*:/
        url
      else
        "http://#{url}"
      end
    end

    def server=(url)
      if url
        @server_url = URI.parse(normalize_server_url(url))
        msg "Set server to #{lookup_var 'server'}"
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


    def print_response(res, label = "")
      @stdout.print @highline.color("#{res.code} #{res.message}", :cyan)
      msg " #{label}"
      if res.json
        @stdout.puts res.json.format
      elsif res.body
        @stdout.puts res.body
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
               when "POST"
                 Net::HTTP::Post
               when "DELETE"
                 Net::HTTP::Delete
               else
                 raise "unsupported http method: `#{method}'"
               end).new(fpath)
        if body
          req.body = body
          if req.content_type.nil? && req.body =~ JSON_DOC_START_RX
            req.content_type = "application/json"
          end
        end
        res = Response.new(http.request(req))
        @responses << res
        rescode = res.code
        vars = ["r#{@responses.index}"]
        vars << ["j#{@responses.index}"] if res.json
        print_response res, "  vars: #{vars.join(', ')}"
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
        expr = nil
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
              expr = ""
            else
              res << c
            end
          elsif c == ')'
            if expr
              res << shell_eval(expr)
              expr = nil
            else
              res << c
            end
          elsif dollar
            res << "$"
          elsif expr
            expr << c
          else
            res << c
          end
          dollar = false
        }
      }
    end

    def shell_eval(expr)
      @eval_context.instance_eval(expr)
    end

    def lookup_var(var)
      case var
      when "uuid"
        command_uuids nil
        if @responses.current(&:ok?)
          json = @responses.current.json
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
        @responses.current { |r| r.attr "id", "_id" } or
          raise ShellUserError, "variable `id' not set"
      when "rev"
        @responses.current { |r| r.attr "rev", "_rev" } or
          raise ShellUserError, "variable `rev' not set"
      when "idr"
        "#{lookup_var 'id'}?rev=#{lookup_var 'rev'}"
      when "content-type"
        @responses.current(&:content_type)
      when "server"
        if @server_url
          u = @server_url
          "#{u.scheme}://#{u.host}:#{u.port}#{u.path}"
        else
          raise ShellUserError, "variable `server' not set"
        end
      when /\Ar(\d)\z/
        i = $1.to_i
        if @responses.readable_index?(i)
          @responses[i]
        else
          raise ShellUserError, "no response index #{i}"
        end
      when /\Aj(\d)\z/
        i = $1.to_i
        if @responses.readable_index?(i)
          if @responses[i].json
            @responses[i].json
          else
            raise ShellUserError, "no json in response #{i}"
          end
        else
          raise ShellUserError, "no response index #{i}"
        end
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

    def command_post(argstr)
      if argstr =~ JSON_DOC_START_RX
        url, body = nil, argstr
      else
        url, body = argstr.split(/\s+/, 2)
      end
      request "POST", interpolate(url), body
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
        errmsg "expression required"
        return
      end
      @stdout.puts shell_eval(argstr)
    end

    def command_format(argstr)
      unless argstr
        errmsg "expression required"
        return
      end
      val = shell_eval(argstr)
      if val.respond_to?(:couch_shell_format_string)
        @stdout.puts val.couch_shell_format_string
      else
        @stdout.puts val
      end
    end

    def command_server(argstr)
      self.server = argstr
    end

  end

end
