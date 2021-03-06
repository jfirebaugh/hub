# based on <github.com/jnicklas/capybara/blob/ab62b27/lib/capybara/server.rb>
require 'net/http'

module Hub
  class LocalServer
    class Identify < Struct.new(:app)
      def call(env)
        if env["PATH_INFO"] == "/__identify__"
          [200, {}, [app.object_id.to_s]]
        else
          app.call(env)
        end
      end
    end

    def self.ports
      @ports ||= {}
    end

    def self.run_handler(app, port, &block)
      begin
        require 'rack/handler/thin'
        Thin::Logging.silent = true
        Rack::Handler::Thin.run(app, :Port => port, &block)
      rescue LoadError
        require 'rack/handler/webrick'
        Rack::Handler::WEBrick.run(app, :Port => port, :AccessLog => [], :Logger => WEBrick::Log::new(nil, 0), &block)
      end
    end

    def self.start_sinatra(&block)
      require 'sinatra/base'
      klass = Class.new(Sinatra::Base)
      klass.set :environment, :test
      klass.disable :protection
      klass.class_eval(&block)

      new(klass.new).start
    end

    attr_reader :app, :host, :port
    attr_accessor :server

    def initialize(app, host = '127.0.0.1')
      @app = app
      @host = host
      @server = nil
      @server_thread = nil
    end

    def responsive?
      return false if @server_thread && @server_thread.join(0)

      res = Net::HTTP.start(host, port) { |http| http.get('/__identify__') }

      res.is_a?(Net::HTTPSuccess) and res.body == app.object_id.to_s
    rescue Errno::ECONNREFUSED, Errno::EBADF
      return false
    end

    def start
      @port = self.class.ports[app.object_id]

      if not @port or not responsive?
        @port = find_available_port
        self.class.ports[app.object_id] = @port

        @server_thread = Thread.new do
          self.class.run_handler(Identify.new(app), @port) { |server|
            self.server = server
          }
        end

        Timeout.timeout(60) { @server_thread.join(0.1) until responsive? }
      end
    rescue TimeoutError
      raise "Rack application timed out during boot"
    else
      self
    end

    def stop
      server.respond_to?(:stop!) ? server.stop! : server.stop
      @server_thread.join
    end

  private

    def find_available_port
      server = TCPServer.new('127.0.0.1', 0)
      server.addr[1]
    ensure
      server.close if server
    end
  end
end
