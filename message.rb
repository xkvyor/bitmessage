# encoding: utf-8

require './message_helper'

class Message
	def initialize(msg, version)
		@valid = false
		@raw_msg = msg.b
		@result = nil
		@version = version
		@valid = true if parse_msg
	end

	private

	def parse_msg
		if @raw_msg.length < 24
			return false 
		end
		@magic, @command, @length, @checksum = @raw_msg[0...24].unpack('Na12NN')
		term = @command.index("\0")
		unless term
			return false
		end
		@command = @command[0...term]
		@payload = @raw_msg[24..-1]
		# puts @command
		return false unless verify_checksum
		if @command == 'version'
			parse_version
			return false unless @result
		elsif @command == 'addr'
			parse_addr
			return false unless @result
		elsif @command == 'inv'
			parse_inv
			return false unless @result
		elsif @command == 'getdata'
			parse_getdata
			return false unless @result
		elsif @command == 'object'
			parse_object
			return false unless @result
		end
		true
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
			@result = nil
		end
	end

	def parse_addr
		@result = {}
		begin
			@result[:count], rm = get_varint(@payload)
			@result[:addr_list] = []
			@result[:count].times do
				ret, rm = get_net_addr(rm, @version)
				@result[:addr_list] << ret if ret
			end
		rescue Exception => e
			@result = nil
		end
	end

	def parse_inv
		@result = {}
		begin
			@result[:count], rm = get_varint(@payload)
			@result[:inventory] = []
			(0...rm.length).step(32) do |i|
				@result[:inventory] << rm[i...i+32]
			end
		rescue Exception => e
			@result = nil
		end
	end

	def parse_getdata
		@result = {}
		begin
			@result[:count], rm = get_varint(@payload)
			@result[:inventory] = []
			(0...rm.length).step(32) do |i|
				@result[:inventory] << rm[i...i+32]
			end
		rescue Exception => e
			@result = nil
		end
	end

	ObjectType = [:getpubkey, :pubkey, :msg, :broadcast]

	def parse_object
		@result = {}
		begin
			nonce, expire, type = @payload.unpack('Q>2N')
			@result[:nonce] = nonce
			@result[:expire] = Time.at(expire)
			@result[:type] = ObjectType[type]
			raise "expire time should in 28 days" if @result[:expire]-Time.now>28*3600*24
			@result[:hash] = Digest::SHA512.digest(Digest::SHA512.digest(@payload))[0...32]
			@result[:object] = @payload[20..-1]
			raise "failed proof of work" unless proof_of_work(@payload)
		rescue Exception => e
			@result = nil
		end
	end

	public
	attr_reader :valid, :raw_msg, :magic, :command,
		:length, :checksum, :payload, :result
end

# msg = "\xE9\xBE\xB4\xD9object\0\0\0\0\0\0\0\0\x01\x8C\xD7&<,\0\0\0\0\x03\xB9_2\0\0\0\0T\xBF2\xEB\0\0\0\x01\x04\x01\vL]\x06!\xD7\x95\xB4l\x88\xB1&,\x117z\x99_h\xA6\xFF\t\xF7\0t\x12p\x98\xC2d\x80e\x94e\x9AKX\xB5\xE7p\x1F]\x95M\xFF\xDC\xB2\xE1\x02\xCA\0 \xEDw\xF3+\x94\x8EV\xD8f\x9D\xC1\xF9\x8De&8\x89\a\x82=.\x01\xFEE\xBF\xA4k\xC0\xFD\x06F\x9D\0 \xAF\x89\x8F,~\x17C\x94YA\x0F\"\v#\eG L\x8BKi1r\xEBt\"i\xBE\xDB\xAD\x84=^>\xCA\xBA\x05\x99\xD4\x91hS\xB5\xDC\\\x90j\xC8\x8A\xE0\xE3k\xEB\xC1\x17\x1A\e\xBFu\xE8\xA6?\xA4*\xD71\x8B\x84\xC7c\xE5W\xECl\xB6}\xBA&\xDA\xDF\xAB\x14!\xE7\xF5:\x02\xA3\x88\xBE\x8B\x10ZHw\x04.u\xD2\x1D%N\xAE\x96\xFBm\x1C\xB1\xFErW\xA6\\*\xB7\0o\x90A\xFBMZBw.\x8B\x8F\x1Dm{f\x97o=i'\xDB\xD3\xFE\xD5p\x9D\x1F-D\xF8}\xD3\x02T\x8C\xBBrTak-4\xC2\a\xE1\xBA\xE5\xFC\x8C\x9B\xB9\xD21\x90k7\x06\xE0\xE3\x1E \n/\xA8]\x95\xD3!\xF4U\x19\xAAGeu\xF1\xC1H\xE3\xD2y~o\xBB\x92\xE2H\xF4K\xEE\x84DUo\xB4\xFA\x9A2\xFB\x95\xE1A\x8F\x99\xF1\x8D\x19[\xBB\xEF\xE2\xD1\x15\xCD5OPI\xC4\xD2\xF2\xFD\xDE\x1D\xD3\x91\r\x12)G\xA1[N\x03m'\xAA#W\xCF\x8A\xC3\xC8\xC3\xAF\xF6wB9\x89fJwJ\xBE\x8D\xE7\x0F\xB4tN\xD4Y\xEC\xD0e\r\x93-\xF8\xAAN"

# m = Message.new msg, 3
# p m.command
# p m.valid
# puts msg.length
# puts m.length
# p m.result
# puts false ?1:0