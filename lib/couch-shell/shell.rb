# -*- encoding: utf-8 -*-

require "tempfile"
require "uri"
require "net/http"
require "socket"
require "httpclient"
require "highline"
require "couch-shell/exceptions"
require "couch-shell/version"
require "couch-shell/response"
require "couch-shell/ring_buffer"
require "couch-shell/eval_context"
require "couch-shell/plugin"

module CouchShell

  JSON_DOC_START_RX = /\A[ \t\n\r]*[\(\{]/

  class FileToUpload

    attr_reader :filename, :content_type

    def initialize(filename, content_type = nil)
      @filename = filename
      @content_type = content_type
    end

    def content_type!
      # TODO: use mime-types and/or file to guess mime type
      content_type || "application/octet-stream"
    end

  end

  # Starting a shell:
  #
  #   require "couch-shell/shell"
  #
  #   shell = CouchShell::Shell.new(STDIN, STDOUT, STDERR)
  #   # returns at end of STDIN or on a quit command
  #   shell.read_execute_loop
  #
  class Shell

    class PluginLoadError < ShellUserError

      def initialize(plugin_name, reason)
        @plugin_name = plugin_name
        @reason = reason
      end

      def message
        "Failed to load plugin #@plugin_name: #@reason"
      end

    end

    # A CouchShell::RingBuffer holding CouchShell::Response instances.
    attr_reader :responses
    attr_reader :server_url
    attr_reader :stdout
    attr_reader :stdin
    attr_reader :pathstack
    attr_accessor :username
    attr_accessor :password

    def initialize(stdin, stdout, stderr)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @server_url = nil
      @pathstack = []
      @highline = HighLine.new(@stdin, @stdout)
      @responses = RingBuffer.new(10)
      @eval_context = EvalContext.new(self)
      @username = nil
      @password = nil
      @plugins = {}
      @commands = {}
      @variables = {}
      @variable_prefixes = []
      @stdout.puts "couch-shell #{VERSION}"
    end

    def plugin(plugin_name)
      # load and instantiate
      feature = "couch-shell-plugin/#{plugin_name}"
      begin
        require feature
      rescue LoadError
        raise PluginLoadError, "feature #{feature} not found"
      end
      pi = PluginInfo[plugin_name]
      raise PluginLoadError, "plugin class not found" unless pi
      plugin = pi.plugin_class.new(self)

      # integrate plugin variables
      ## enable qualified reference via @PLUGIN.VAR syntax
      @eval_context._instance_variable_set(
        :"@#{plugin_name}", plugin.variables_object)
      ## enable unqualified reference
      pi.variables.each { |vi|
        if vi.name
          existing = @variables[vi.name]
          if existing
            warn "When loading plugin #{plugin_name}: " +
              "Variable #{vi.name} already defined by plugin " +
              "#{existing.plugin.plugin_name}\n" +
              "You can access it explicitely via @#{plugin_name}.#{vi.name}"
          else
            @variables[vi.name] = vi
          end
        end
        if vi.prefix
          existing = @variable_prefixes.find { |e| e.prefix == vi.prefix }
          if existing
            warn "When loading plugin #{plugin_name}: " +
              "Variable prefix #{vi.prefix} already defined by plugin " +
              "#{existing.plugin.plugin_name}\n" +
              "You can access it explicitely via @#{plugin_name}.#{vi.prefix}*"
          else
            @variable_prefixes << vi
          end
        end
      }

      # integrate plugin commands
      pi.commands.each_value { |ci|
        existing = @commands[ci.name]
        if existing
          warn "When loading plugin #{plugin_name}: " +
            "Command #{ci.name} already defined by plugin " +
            "#{existing.plugin.plugin_name}\n" +
            "You can access it explicitely via @#{plugin_name}.#{ci.name}"
        else
          @commands[ci.name] = ci
        end
      }

      @plugins[plugin_name] = plugin
      plugin.plugin_initialization
    end

    def normalize_server_url(url)
      return nil if url.nil?
      # remove trailing slash
      url = url.sub(%r{/\z}, '')
      # prepend http:// if scheme is omitted
      if url =~ /\A\p{Alpha}(?:\p{Alpha}|\p{Digit}|\+|\-|\.)*:\/\//
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

      if path
        @pathstack = [] if path.start_with?("/")
        path.split('/').each { |elem|
          case elem
          when ""
            # do nothing
          when "."
            # do nothing
          when ".."
            if @pathstack.empty?
              @pathstack = old_pathstack
              raise ShellUserError, "Already at server root, can't go up"
            end
            @pathstack.pop
          else
            @pathstack << elem
          end
        }
      else
        @pathstack = []
      end

      old_dbname = old_pathstack[0]
      new_dbname = @pathstack[0]
      getdb = false
      if new_dbname && (new_dbname != old_dbname)
        getdb = get && @pathstack.size == 1
        res = request("GET", "/#{new_dbname}", nil, getdb)
        unless res.ok? && (json = res.json_value) &&
            json.object? && json["db_name"] &&
            json["db_name"].unwrapped! == new_dbname
          @pathstack = old_pathstack
          raise ShellUserError, "not a database: #{new_dbname}"
        end
      end
      if get && !getdb
        if request("GET", nil).code != "200"
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

    def warn(str)
      @stderr.print @highline.color("warning: ", :red)
      @stderr.puts @highline.color(str, :blue)
    end

    def print_response(res, label = "", show_body = true)
      @stdout.print @highline.color("#{res.code} #{res.message}", :cyan)
      msg " #{label}"
      if show_body
        if res.json
          @stdout.puts res.json_value.to_s(true)
        elsif res.body
          @stdout.puts res.body
        end
      elsif res.body
        msg "body has #{res.body.bytesize} bytes"
      end
    end

    # Returns CouchShell::Response or raises an exception.
    def request(method, path, body = nil, show_body = true)
      unless @server_url
        raise ShellUserError, "Server not set - can't perform request."
      end
      fpath = URI.encode(full_path(path))
      msg "#{method} #{fpath} ", false
      if @server_url.scheme != "http"
        raise ShellUserError,
          "Protocol #{@server_url.scheme} not supported, use http."
      end
      # HTTPClient and CouchDB don't work together with simple put/post
      # requests to due some Keep-alive mismatch.
      #
      # Net:HTTP doesn't support file upload streaming.
      if body.kind_of?(FileToUpload) || method == "GET"
        res = http_client_request(method, URI.encode(expand(path)), body)
      else
        res = net_http_request(method, fpath, body)
      end
      @responses << res
      rescode = res.code
      vars = ["r#{@responses.index}"]
      vars << ["j#{@responses.index}"] if res.json
      print_response res, "  vars: #{vars.join(', ')}", show_body
      res
    end

    def net_http_request(method, fpath, body)
      res = nil
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
        if @username && @password
          req.basic_auth @username, @password
        end
        if body
          req.body = body
          if req.content_type.nil? && req.body =~ JSON_DOC_START_RX
            req.content_type = "application/json"
          end
        end
        res = Response.new(http.request(req))
      end
      res
    end

    def http_client_request(method, absolute_url, body)
      file = nil
      headers = {}
      if body.kind_of?(FileToUpload)
        file_to_upload = body
        file = File.open(file_to_upload.filename, "rb")
        body = [{'Content-Type' => file_to_upload.content_type!,
                 'Content-Transfer-Encoding' => 'binary',
                 :content => file}]
        #body = {'upload' => file}
      elsif body && body =~ JSON_DOC_START_RX
        headers['Content-Type'] = "application/json"
      end
      hclient = HTTPClient.new
      if @username && @password
        hclient.set_auth lookup_var("server"), @username, @password
      end
      res = hclient.request(method, absolute_url, body, headers)
      Response.new(res)
    ensure
      file.close if file
    end

    def expand(url)
      u = @server_url
      "#{u.scheme}://#{u.host}:#{u.port}#{full_path url}"
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

    def prompt_msg(msg, newline = true)
      @stdout.print @highline.color(msg, :yellow)
      if newline
        @stdout.puts
      else
        @stdout.flush
      end
    end

    # Displays the standard couch-shell prompt and waits for the user to
    # enter a command. Returns the user input as a string (which may be
    # empty), or nil if the input stream is closed.
    def read
      lead = @pathstack.empty? ? ">>" : @pathstack.join("/") + " >>"
      begin
        @highline.ask(@highline.color(lead, :yellow) + " ") { |q|
          q.readline = true
        }
      rescue Interrupt
        @stdout.puts
        errmsg "interrupted"
        return ""
      rescue NoMethodError
        # this is BAD, but highline 1.6.1 reacts to CTRL+D with a NoMethodError
        return nil
      end
    end

    # When the user enters something, it is passed to this method for
    # execution. You may call it programmatically to simulate user input.
    #
    # If input is nil, it is interpreted as "end of input", raising a
    # CouchShell::Shell::Quit exception. This exception is also raised by other
    # commands (e.g. "exit" and "quit"). All other exceptions are caught and
    # displayed on stderr.
    def execute(input)
      begin
        execute!(input)
      rescue Quit => e
        raise e
      rescue Interrupt
        @stdout.puts
        errmsg "interrupted"
      rescue UndefinedVariable => e
        errmsg "Variable `" + e.varname + "' is not defined."
      rescue ShellUserError => e
        errmsg e.message
      rescue Errno::ETIMEDOUT => e
        errmsg "timeout: #{e.message}"
      rescue SocketError, Errno::ENOENT => e
        @stdout.puts
        errmsg "#{e.class}: #{e.message}"
      rescue Exception => e
        #p e.class.instance_methods - Object.instance_methods
        errmsg "#{e.class}: #{e.message}"
        errmsg e.backtrace[0..5].join("\n")
      end
    end

    # Basic execute without error handling. Raises various exceptions.
    def execute!(input)
      case input
      when nil
        raise Quit
      when ""
        # do nothing
      else
        execute_command! *input.split(/\s+/, 2)
      end
    end

    def execute_command!(commandref, argstr = nil)
      if commandref.start_with?("@")
        # qualified command
        if commandref =~ /\A@([^\.]+)\.([^\.]+)\z/
          plugin_name = $1
          command_name = $2
          plugin = @plugins[plugin_name]
          raise NoSuchPluginRegistered.new(plugin_name) unless plugin
          ci = plugin.plugin_info.commands[command_name]
          raise NoSuchCommandInPlugin.new(plugin_name, command_name) unless ci
          plugin.send ci.execute_message, argstr
        else
          raise ShellUserError, "invalid command syntax"
        end
      else
        # unqualified command
        ci = @commands[commandref]
        raise NoSuchCommand.new(commandref) unless ci
        @plugins[ci.plugin.plugin_name].send ci.execute_message, argstr
      end
    end

    # Start regular shell operation, i.e. reading commands from stdin and
    # executing them. Returns when the user issues a quit command.
    def read_execute_loop
      loop {
        execute(read)
      }
    rescue Quit
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
              res << eval_expr(expr).to_s
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

    # Evaluate the given expression.
    def eval_expr(expr)
      @eval_context.instance_eval(expr)
    end

    # Lookup unqualified variable name.
    def lookup_var(var)
      vi = @variables[var]
      if vi
        plugin = @plugins[vi.plugin.plugin_name]
        plugin.send vi.lookup_message
      else
        vi = @variable_prefixes.find { |v|
          var.start_with?(v.prefix) && var.length > v.prefix.length
        }
        raise UndefinedVariable.new(var) unless vi
        plugin = @plugins[vi.plugin.plugin_name]
        plugin.send vi.lookup_message, var[vi.prefix.length]
      end
    rescue Plugin::VarNotSet => e
      e.var = vi
      raise e
    end

    def editor_bin!
      ENV["EDITOR"] or
        raise ShellUserError, "EDITOR environment variable not set"
    end

    def read_secret
      @highline.ask(" ") { |q| q.echo = "*" }
    end

  end

end
