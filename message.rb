# encoding: utf-8

require './message_helper'

class Message
	def initialize(msg)
		@valid = false
		@raw_msg = msg
		@result = nil
		@valid = true if parse_msg(msg)
	end

	def parse_msg(msg)
		return false if msg.length < 24
		@magic, @command, @length, @checksum = msg[0...24].unpack('Na12NN')
		term = @command.index("\0")
		return false unless term
		@command = @command[0...term]
		@payload = msg[24..-1]
		if @command == 'version'
			parse_version
		end
		verify_checksum
	end

	def verify_checksum
		d = Digest::SHA512.digest(@payload)[0...4]
		d.unpack('N')[0] == @checksum
	end

	def parse_version
		@result = {}
		begin
			version, services, timestamp, addr_recv, addr_from, nonce, extra = @payload.unpack('NQ>2a26a26Q>a*')
			@result[:version] = version
			@result[:services] = services
			@result[:timestamp] = timestamp
			@result[:addr_recv] = addr_recv
			@result[:addr_from] = addr_from
			@result[:nonce] = nonce
			@result[:user_agent], extra = get_varstr(extra)
			@result[:stream], extra = get_varint_list(extra)
		rescue Exception => e
			puts e
			@result = nil
		end
	end

	attr_reader :valid, :raw_msg, :magic, :command,
		:length, :checksum, :payload, :result
end