# encoding: utf-8

require 'socket'

require './config'
require './logger'
require './message'
require './message_helper'

class Peer
	@@id = 0

	def initialize(host, port)
		@logger = Logger.new BMConfig::Log_file
		@host = host
		@port = port
		@sock = nil
		@status = :invalid
		@timeout = 20
		@buf = ''
		@id = @@id
		@@id += 1

		@thr = Thread.new do
			run
		end
	end

	attr_reader :status

	private
	def run
		connect
		return if @status == :invalid
		send_version
		return if @status == :invalid
		loop do
			begin
				rmsg = @sock.read
				@buf += rmsg
				process
				sleep 2
			rescue Exception => e
				@status = :invalid
				@logger.error "Peer #{@id}: #{e.to_s}"
				break
			end
		end
	end

	def connect
		begin
			@sock = Socket.new Socket::AF_INET, Socket::SOCK_STREAM, 0
			sockaddr = Socket.sockaddr_in(@port, @host)
			begin
				@sock.connect_nonblock(sockaddr)
			rescue IO::WaitWritable
				IO.select(nil, [@sock], nil, @timeout)
				begin
					@sock.connect_nonblock(sockaddr)
				rescue Errno::EISCONN
				end
			end
			@status = :connected
		rescue Exception => e
			@logger.error "Peer #{@id}: #{e.to_s}"
			@status = :invalid
		end
	end

	def close
		@sock.close
		@status = :closed
		Thread.stop
	end

	def fetch_msg
		magic = [BMConfig::Magic].pack('N')
		first = @buf.index(magic)
		return nil unless first
		last = @buf.index(magic, first+1)
		if last
			msg = @buf[first...last]
			@buf = @buf[last..-1]
			return msg
		else
			msg = @buf[first..-1]
			@buf = ''
			return msg
		end
	end

	def process
		raw_msg = fetch_msg
		while raw_msg
			msg = Message.new raw_msg
			if msg.valid
				if msg.command == 'verack'
					@logger.info "Peer #{@id}: recieve verack, raise timeout to 10 min"
					@timeout = 600
				elsif msg.command == 'version'
					if msg.result == nil or msg.result[:version] < BMConfig::Protocol_version
						close
					end
					@logger.info "Peer #{@id}: remote version is #{msg.result[:version]}"
					@logger.info "Peer #{@id}: remote user agent is #{msg.result[:user_agent].inspect}"
					send_verack
				else
					@logger.info "Peer #{@id}: recieve [#{msg.command}] message"
				end
			else
				@logger.info "Peer #{@id}: failed parse message: #{raw_msg.inspect}"
			end
			raw_msg = fetch_msg
		end
	end

	def send_version
		msg = msg_version(@host, @port)
		begin
			@sock.send msg, 0
		rescue Exception => e
			@logger.error "Peer #{@id}: send version message failed"
			@status = :invalid
		end
	end

	def send_verack
		msg = msg_verack
		begin
			@sock.send msg, 0
		rescue Exception => e
			@logger.error "Peer #{@id}: send verack message failed"
			@status = :invalid
		end
	end
end