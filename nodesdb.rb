# encoding: utf-8

require './config'
require './peer'
require 'singleton'

class NodeRecord
	def initialize(host, port)
		@host = host
		@port = port
		@peer = nil
		@found = Time.now
	end

	attr_reader :host, :port, :peer, :found
	attr_writer :peer
end

class NodesDB
	include Singleton

	def initialize
		@known = {}
		@connected = {}
		@mutex = Mutex.new
	end

	def find_peer(host, port)
		if @connected[[host, port]]
			return @connected[[host, port]].peer
		else
			return nil
		end
	end

	def new_node(host, port)
		@mutex.synchronize do
			unless @known[[host, port]] or @connected[[host, port]]
				@known[[host, port]] = NodeRecord.new(host, port)
			end
		end
	end

	def new_peer(host, port)
		@mutex.synchronize do
			key = [host, port]
			@known.delete key
			@connected[key] = NodeRecord.new host, port
			@connected[key].peer = Peer.new host, port
		end
	end

	def known_nodes
		@known.each do |serv, record|
			yield serv[0], serv[1]
		end
	end

	def peer_count
		@connected.length
	end

	def each_peer
		@connected.each do |serv, record|
			yield record.peer if record.peer
		end
	end

	def update
		@mutex.synchronize do
			now = Time.now
			@known.each do |serv, record|
				if now - record.found > BMConfig::RecordLife
					@known.delete serv
				end
			end
			@connected.each do |serv, record|
				if record.peer.status == :invalid or record.peer.status == :closed
					@connected.delete serv
				elsif now - record.found > BMConfig::RecordLife
					record.peer.close
					@connected.delete serv
				end
			end
		end
	end
end

# nodes = NodesDB.instance
# nodes.new_node('127.0.0.1', 80)
# nodes.new_node('127.0.0.1', 80)
# nodes.new_node('127.0.0.2', 123)
# nodes.known_nodes do |host, port|
# 	puts "#{host}:#{port}"
# end
# p nodes.find_peer('127.0.0.1', 80)
# nodes.new_peer('127.0.0.1', 80)
# r = nodes.find_peer('127.0.0.1', 80)
# p r
# nodes.update
# r = nodes.find_peer('127.0.0.1', 80)
# p r
