# encoding: utf-8

require 'socket'

require './config'
require './logger'
require './message'
require './message_helper'
require './nodesdb'
require './inventory'
require './util'
require './broadcaster'

class Peer
	@@id = 0

	def initialize(host, port)
		@logger = Logger.instance
		@host = host
		@port = port
		@sock = nil
		@status = :invalid
		@timeout = 20
		@retry = 2
		@buf = ''
		@id = @@id
		@@id += 1
		@buflen = 4096
		@peer_info = "Peer #{@id}: "
		@pversion = nil
		@stream = [1]
		@msgq = MessageQueue.new

		@thr = Thread.new do
			run
		end
	end

	attr_reader :status, :host, :port, :id

	private
	def run
		connect
		return if @status == :invalid
		send_version
		return if @status == :invalid
		loop do
			begin
				ready = IO.select([@sock], [], [], 2)
				if ready
					loop do
						rmsg = @sock.recv(@buflen)
						@buf += rmsg
						break if rmsg.length < @buflen
					end
				end
				process
				check_message_queue
				sleep 1
			rescue Exception => e
				begin
					@sock.close
				rescue Exception => e
				end
				@status = :invalid
				@logger.error @peer_info+e.to_s
				@logger.debug @peer_info+e.backtrace.inspect
				break unless @retry > 0
				@retry -= 1
				@logger.info @peer_info+"try to reconnect (#{@retry})"
				connect
				break if @status == :invalid
				send_version
				break if @status == :invalid
			end
		end
	end

	def connect
		begin
			@status = :connecting
			if ip_version(host) == 6
				@sock = Socket.new Socket::AF_INET6, Socket::SOCK_STREAM, 0
			else
				@sock = Socket.new Socket::AF_INET, Socket::SOCK_STREAM, 0
			end
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
			Broadcaster.instance.register @msgq
		rescue Exception => e
			@logger.error @peer_info+e.to_s
			@status = :invalid
		end
	end

	def close
		@sock.close
		@status = :closed
		Broadcaster.instance.unregister @msgq
		Thread.stop
	end

	def fetch_msg
		return nil if @buf.length < 24
		magic = [BMConfig::Magic].pack('N')
		first = @buf.index(magic)
		return nil unless first
		@logger.warn @peer_info+"#{first} bytes discard" if first > 0
		@buf = @buf[first..-1]
		magic, command, length, checksum = @buf[0...24].unpack('Na12NN')
		mlen = length + 24
		return nil if @buf.length < mlen
		msg = @buf[0...mlen]
		@buf = @buf[mlen..-1]
		msg
	end

	def process
		raw_msg = fetch_msg
		while raw_msg
			msg = Message.new raw_msg, @pversion
			if msg.valid
				if msg.command == 'verack'
					@logger.info @peer_info+"recieve verack, raise timeout to 10 min"
					@timeout = 600
					Inventory.instance.all_hash.each do |inv|
						@msgq.push([:inv, @stream, inv])
					end
				elsif msg.command == 'version'
					if msg.result == nil or msg.result[:version] < BMConfig::Protocol_version
						close
					end
					@logger.info @peer_info+"remote version is #{msg.result[:version]}"
					@pversion = msg.result[:version]
					@stream = msg.result[:stream]
					# @logger.info @peer_info+"remote user agent is #{msg.result[:user_agent].inspect}"
					send_verack
				elsif msg.command == 'addr'
					if msg.result and msg.result[:addr_list]
						@logger.info @peer_info+"found #{msg.result[:addr_list].length} new nodes"
						msg.result[:addr_list].each do |addr|
							NodesDB.instance.new_node(addr[:host], addr[:port])
						end
					end
				elsif msg.command == 'inv'
					if msg.result and msg.result[:inventory]
						@logger.info @peer_info+"get #{msg.result[:count]} invs"
						msg.result[:inventory].each do |hash|
							unless Inventory.instance.known?(hash)
								@msgq.push([:getdata, @stream, hash])
							end
						end
					end
				elsif msg.command == 'getdata'
					if msg.result and msg.result[:inventory]
						@logger.info @peer_info+"want #{msg.result[:count]} invs"
						msg.result[:inventory].each do |hash|
							if Inventory.instance.known?(hash)
								@msgq.push([:object, @stream, hash])
							end
						end
					end
				elsif msg.command == 'object'
					if msg.result
						data = Inventory.instance.get(msg.result[:hash])
						if data and data != msg.payload
							@logger.warn @peer_info+"same hash diff data [#{hex_str(msg.result[:hash])}]"
						else
							@logger.info @peer_info+"get a inv [#{hex_str(msg.result[:hash])}]"
							Inventory.instance.set(msg.result[:hash], msg.payload)
							Broadcaster.instance.put([:inv, @stream, msg.result[:hash]])
						end
					end
				else
					@logger.info @peer_info+"recieve unknown [#{msg.command}] message"
					open('unknown', 'a') do |f|
						f.puts raw_msg.inspect
					end
				end
			else
				@logger.info @peer_info+"failed parse message: #{raw_msg.inspect[0...128]}"
				open('failed', 'a') do |f|
					f.puts raw_msg.inspect
				end
			end
			raw_msg = fetch_msg
		end
	end

	def send_version
		msg = msg_version(@host, @port)
		begin
			@sock.send msg, 0
		rescue Exception => e
			@logger.error @peer_info+"send version message failed"
			close
		end
	end

	def send_verack
		msg = msg_verack
		begin
			@sock.send msg, 0
		rescue Exception => e
			@logger.error @peer_info+"send verack message failed"
			close
		end
	end

	def send_getdata(inventory)
		begin
			loop do
				if inventory.length > 50000
					msg = msg_getdata inventory[0...50000]
					inventory = inventory[50000..-1]
					@sock.send msg, 0
				else
					msg = msg_getdata inventory
					@sock.send msg, 0
					break
				end
			end
			@logger.info @peer_info+"send getdata for #{inventory.length} invs"
		rescue Exception => e
			@logger.error @peer_info+"send getdata message failed"
			close
		end
	end

	def send_inv(inventory)
		begin
			loop do
				if inventory.length > 50000
					msg = msg_inv inventory[0...50000]
					inventory = inventory[50000..-1]
					@sock.send msg, 0
				else
					msg = msg_inv inventory
					@sock.send msg, 0
					break
				end
			end
			@logger.info @peer_info+"send #{inventory.length} invs"
		rescue Exception => e
			@logger.error @peer_info+"send inv message failed"
			close
		end
	end

	def send_object(hash)
		data = Inventory.get(hash)
		return unless data
		msg = msg_object data
		begin
			@sock.send msg, 0
			@logger.info @peer_info+"send object"
		rescue Exception => e
			@logger.error @peer_info+"send object message failed"
			close
		end
	end

	def check_message_queue
		return unless @pversion
		inventory = []
		getdata = []
		msg = @msgq.pop
		start = Time.now
		while msg
			if msg[0] == :inv
				inventory << msg[2]
			elsif msg[0] == :getdata
				getdata << msg[2]
			elsif msg[0] == :object
				send_object msg[2]
			end
			break if Time.now - start > 2
			msg = @msgq.pop
		end

		send_getdata getdata if getdata.length > 0
		send_inv inventory if inventory.length > 0
	end
end