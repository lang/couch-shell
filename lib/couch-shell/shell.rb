# -*- encoding: utf-8 -*-

require "tempfile"
require "uri"
require "net/http"
require "httpclient"
require "highline"
require "couch-shell/version"
require "couch-shell/response"
require "couch-shell/ring_buffer"
require "couch-shell/eval_context"

module CouchShell

  # Starting a shell:
  #
  #   require "couch-shell/shell"
  #
  #   shell = CouchShell::Shell.new(STDIN, STDOUT, STDERR)
  #   # returns at end of STDIN or on a quit command
  #   shell.read_execute_loop
  #
  class Shell

    class Quit < Exception
    end

    class ShellUserError < Exception
    end

    class UndefinedVariable < ShellUserError

      attr_reader :varname

      def initialize(varname)
        @varname = varname
      end

    end

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
      @viewtext = nil
      @stdout.puts "couch-shell #{VERSION}"
      @username = nil
      @password = nil
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
      when %r{\A/\z}
        @pathstack = []
      when %r{\A/}
        @pathstack = []
        cd path[1..-1], false
      when %r{/}
        path.split("/").each { |elem| cd elem, false }
      else
        @pathstack << path
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


    def print_response(res, label = "", show_body = true)
      @stdout.print @highline.color("#{res.code} #{res.message}", :cyan)
      msg " #{label}"
      if show_body
        if res.json
          @stdout.puts res.json.format
        elsif res.body
          @stdout.puts res.body
        end
      elsif res.body
        msg "body has #{res.body.bytesize} bytes"
      end
    end

    def request(method, path, body = nil, show_body = true)
      unless @server_url
        errmsg "Server not set - can't perform request."
        return
      end
      fpath = URI.encode(full_path(path))
      msg "#{method} #{fpath} ", false
      if @server_url.scheme != "http"
        errmsg "Protocol #{@server_url.scheme} not supported, use http."
        return
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
      res.code
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
        #body = [{'Content-Type' => file_to_upload.content_type!,
        #         :content => file}]
        body = {'upload' => file}
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

    def continue?(msg)
      prompt_msg(msg, false)
      unless @stdin.gets.chomp.empty?
        raise ShellUserError, "cancelled"
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

    # When the user enters something, it is passed to this method for
    # execution. You may call if programmatically to simulate user input.
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
      rescue Exception => e
        errmsg e.message
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
        command, argstr = input.split(/\s+/, 2)
        command_message = :"command_#{command.downcase}"
        if self.respond_to?(command_message)
          send command_message, argstr
        else
          errmsg "unknown command `#{command}'"
        end
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
              res << shell_eval(expr).to_s
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
          if json && (uuids = json.couch_shell_ruby_value!["uuids"]) &&
              uuids.kind_of?(Array) && uuids.size > 0
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
      when "viewtext"
        @viewtext or
          raise ShellUserError, "viewtext not set"
      else
        raise UndefinedVariable.new(var)
      end
    end

    def request_command_with_body(method, argstr)
      if argstr =~ JSON_DOC_START_RX
        url, bodyarg = nil, argstr
      else
        url, bodyarg= argstr.split(/\s+/, 2)
      end
      if bodyarg && bodyarg.start_with?("@")
        filename, content_type = bodyarg[1..-1].split(/\s+/, 2)
        body = FileToUpload.new(filename, content_type)
      else
        body = bodyarg
      end
      real_url = interpolate(url)
      request method, real_url, body
      real_url
    end

    def editor_bin!
      ENV["EDITOR"] or
        raise ShellUserError, "EDITOR environment variable not set"
    end

    def command_get(argstr)
      request "GET", interpolate(argstr)
    end

    def command_put(argstr)
      request_command_with_body("PUT", argstr)
    end

    def command_cput(argstr)
      url = request_command_with_body("PUT", argstr)
      cd url if @responses.current(&:ok?)
    end

    def command_post(argstr)
      request_command_with_body("POST", argstr)
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
      raise Quit
    end

    def command_quit(argstr)
      raise Quit
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

    def command_expand(argstr)
      @stdout.puts expand(interpolate(argstr))
    end

    def command_sh(argstr)
      unless argstr
        errmsg "argument required"
        return
      end
      unless system(argstr)
        errmsg "command exited with status #{$?.exitstatus}"
      end
    end

    def command_editview(argstr)
      if @pathstack.size != 1
        raise ShellUserError, "current directory must be database"
      end
      design_name, view_name = argstr.split(/\s+/, 2)
      if design_name.nil? || view_name.nil?
        raise ShellUserError, "design and view name required"
      end
      request "GET", "_design/#{design_name}", nil, false
      return unless @responses.current(&:ok?)
      design = @responses.current.json
      view = nil
      if design.respond_to?(:views) &&
          design.views.respond_to?(view_name.to_sym)
        view = design.views.__send__(view_name.to_sym)
      end
      mapval = view && view.respond_to?(:map) && view.map
      reduceval = view && view.respond_to?(:reduce) && view.reduce
      t = Tempfile.new(["view", ".js"])
      t.puts("map")
      if mapval
        t.puts mapval
      else
        t.puts "function(doc) {\n  emit(doc._id, doc);\n}"
      end
      if reduceval || view.nil?
        t.puts
        t.puts("reduce")
        if reduceval
          t.puts reduceval
        else
          t.puts "function(keys, values, rereduce) {\n\n}"
        end
      end
      t.close
      continue?(
        "Press ENTER to edit #{view ? 'existing' : 'new'} view, " +
        "CTRL+C to cancel ")
      unless system(editor_bin!, t.path)
        raise ShellUserError, "editing command failed with exit status #{$?.exitstatus}"
      end
      text = t.open.read
      @viewtext = text
      t.close
      mapf = nil
      reducef = nil
      inmap = false
      inreduce = false
      i = 0
      text.each_line { |line|
        i += 1
        case line
        when /^map\s*(.*)$/
          unless $1.empty?
            msg "recover view text with `print viewtext'"
            raise ShellUserError, "invalid map line at line #{i}"
          end
          unless mapf.nil?
            msg "recover view text with `print viewtext'"
            raise ShellUserError, "duplicate map line at line #{i}"
          end
          inreduce = false
          inmap = true
          mapf = ""
        when /^reduce\s*(.*)$/
          unless $1.empty?
            msg "recover view text with `print viewtext'"
            raise ShellUserError, "invalid reduce line at line #{i}"
          end
          unless reducef.nil?
            msg "recover view text with `print viewtext'"
            raise ShellUserError, "duplicate reduce line at line #{i}"
          end
          inmap = false
          inreduce = true
          reducef = ""
        else
          if inmap
            mapf << line
          elsif inreduce
            reducef << line
          elsif line =~ /^\s*$/
            # ignore
          else
            msg "recover view text with `print viewtext'"
            raise ShellUserError, "unexpected content at line #{i}"
          end
        end
      }
      mapf.strip! if mapf
      reducef.strip! if reducef
      mapf = nil if mapf && mapf.empty?
      reducef = nil if reducef && reducef.empty?
      prompt_msg "View parsed, following actions would be taken:"
      if mapf && mapval.nil?
        prompt_msg " Add map function."
      elsif mapf.nil? && mapval
        prompt_msg " Remove map function."
      elsif mapf && mapval && mapf != mapval
        prompt_msg " Update map function."
      end
      if reducef && reduceval.nil?
        prompt_msg " Add reduce function."
      elsif reducef.nil? && reduceval
        prompt_msg " Remove reduce function."
      elsif reducef && reduceval && reducef != reduceval
        prompt_msg " Update reduce function."
      end
      continue? "Press ENTER to submit, CTRL+C to cancel "
      if !design.respond_to?(:views)
        design.set_attr!("views", {})
      end
      if view.nil?
        design.views.set_attr!(view_name, {})
        view = design.views.__send__(view_name.to_sym)
      end
      if mapf.nil?
        view.delete_attr!("map")
      else
        view.set_attr!("map", mapf)
      end
      if reducef.nil?
        view.delete_attr!("reduce")
      else
        view.set_attr!("reduce", reducef)
      end
      request "PUT", "_design/#{design_name}", design.to_s
      unless @responses.current(&:ok?)
        msg "recover view text with `print viewtext'"
      end
    ensure
      if t
        t.close
        t.unlink
      end
    end

    def command_view(argstr)
      if @pathstack.size != 1
        raise ShellUserError, "current directory must be database"
      end
      design_name, view_name = argstr.split("/", 2)
      if design_name.nil? || view_name.nil?
        raise ShellUserError, "argument in the form DESIGN/VIEW required"
      end
      request "GET", "_design/#{design_name}/_view/#{view_name}"
    end

    def command_member(argstr)
      id, rev = nil, nil
      json = @responses.current(&:json)
      unless json && (id = json.attr_or_nil!("_id")) &&
          (rev = json.attr_or_nil!("_rev")) &&
          (@pathstack.size > 0) &&
          (@pathstack.last == id.to_s)
        raise ShellUserError,
          "`cg' the desired document first, e.g.: `cg /my_db/my_doc_id'"
      end
      # TODO: read json string as attribute name if argstr starts with double
      # quote
      attr_name, new_valstr = argstr.split(/\s+/, 2)
      unless attr_name && new_valstr
        raise ShellUserError,
          "attribute name and new value argument required"
      end
      if new_valstr == "remove"
        json.delete_attr!(attr_name)
      else
        new_val = JsonValue.parse(new_valstr)
        json.set_attr!(attr_name, new_val)
      end
      request "PUT", "?rev=#{rev}", json.to_s
    end

    def command_user(argstr)
      prompt_msg("Password:", false)
      @password = @highline.ask(" ") { |q| q.echo = "*" }
      # we save the username only after the password was entered
      # to allow cancellation during password input
      @username = argstr
    end

  end

end
