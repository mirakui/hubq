require "socket"
require "logger"

module Hubq
  DEFAULT_HOST = "localhost"
  DEFAULT_PORT = 5000

  module Loggable
    def logger=(l)
      @logger = l
    end

    def logger
      @logger ||= begin
        l = Logger.new(STDOUT)
        l.level = Logger::INFO
        l
      end
    end

    def debug(str="")
      puts "#{caller(1).first}: #{str}"
    end
  end

  class Server
    include Loggable

    def initialize(opts={})
      @sockets = []
      @opts = opts
      @opts[:host] ||= DEFAULT_HOST
      @opts[:port] ||= DEFAULT_PORT
      self.logger = @opts[:logger]
      start
    end

    def start
      logger.info "Listening #{@opts[:host]}:#{@opts[:port]}"
      @server_socket = TCPServer.open(@opts[:host], @opts[:port])
      @sockets << @server_socket

      @fiber = Fiber.new do
        flag = true
        while (flag) do
          readable, writable = IO.select(@sockets)

          readable.each do |socket|
            if socket == @server_socket
              socket = @server_socket.accept_nonblock
              @sockets << socket
            else
              case (socket.gets || "").chomp
              when "POP"
                r = Fiber.yield
                if r.nil?
                  logger.info "#{socket} Resouce finished!"
                  close_socket(@server_socket)
                  flag = false
                else
                  begin
                    logger.debug "#{socket} sent: #{r.inspect}"
                    socket.puts r
                  rescue
                    logger.info "#{socket}:#{$!}"
                    close_socket(socket)
                    flag = false
                  end
                end
              end
            end 
          end
        end
      end
      @fiber.resume
    end

    def <<(data)
      @fiber.resume data
    end

    def close
      self << nil
    end

    def close_socket(socket)
      socket.close
      @sockets.delete socket
      logger.info "#{socket} closed"
    end
  end

  class Client
    def initialize(opts={}, &receiver)
      @receiver = receiver
      @opts = opts
      @opts[:host] ||= DEFAULT_HOST
      @opts[:port] ||= DEFAULT_PORT
      start
    end

    def start
      s = TCPSocket.open(@opts[:host], @opts[:port])
      while true
        s.puts "POP"
        if s.gets
          @receiver.call $_.chomp
        else
          break
        end
      end
    end
  end
end

