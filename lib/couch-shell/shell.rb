# -*- encoding: utf-8 -*-

require "uri"
require "highline"

module CouchShell

  class Shell

    def initialize(stdin, stdout, stderr)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @server_url = nil
      @pathstack = []
      @highline = HighLine.new(@stdin, @stdout)
    end

    def server=(url)
      if url
        @server_url = URI.parse(url.sub(%r{/\z}, ''))
        msg "Set server to #{@server_url.scheme}://" +
          "#{@server_url.host}:#{@server_url.port}/#{@server_url.path}"
        request("GET", "/")
      else
        @server_url = nil
        msg "Set server to none."
      end
    end

    def cd(path, get = false)
      old_pathstack = @pathstack.dup
      case path
      when ".."
        if @pathstack.empty?
          errmsg "Already at server root, can't go up."
        else
          @pathstack.pop
        end
      when %r{\A/}
        @pathstack = path[1..-1].split("/")
      else
        @pathstack.push path.split("/")
      end
      if get
        if request("GET", "/") != "200"
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

    def print_response(res)
        response_info "#{res.code} #{res.message}"
        @stdout.puts res.body if res.body
    end

    def request(method, path, data = nil)
      unless @server_url
        errmsg "Server not set - can't perform request."
        return
      end
      fpath = full_path(path)
      msg "GET #{fpath} ", false
      net_module =
        case @server_url.scheme
        when "http"
          require "net/http"
          Net::HTTP
        when "https"
          require "net/https"
          Net::HTTPS
        else
          errmsg "Protocol #{@server_url.scheme} not supported, use http or https."
          return
        end
      rescode = nil
      net_module.start(@server_url.host, @server_url.port) do |http|
        req = net_module::Get.new(fpath)
        res = http.request(req)
        rescode = res.code
        print_response res
      end
      rescode
    end

    def full_path(path)
      stack = @pathstack.dup
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

    def prompt
      input = read
      case input
      when nil
        return true
      when ""
        # do nothing
      when "exit", "quit", "q"
        return true
      when %r{\A/}
        request("GET", input)
      when %r{\Aget\s+(.*)\z}
        request("GET", $1)
      when %r{\Adb\s+(.*)\z}
        self.database = $1
      when %r{\Acd\s*\z}
        @pathstack.clear
      when %r{\Acd\s+(.*)\z}
        cd $1
      when %r{\Acdg\s+(.*)\z}
        cd $1, true
      else
        errmsg "unkown command"
      end
      false
    end

    def repl
      loop {
        break if prompt
      }
      msg "bye"
    end

  end

end
