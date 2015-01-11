# encoding: utf-8

require 'digest'

require './config'

def get_varint(msg)
	v = msg.bytes[0]
	n = msg.length
	if v < 0xfd
		return v, msg[1..-1]
	elsif v == 0xfd and n >= 3
		return msg[1..2].unpack('n')[0], msg[3..-1]
	elsif v == 0xfe and n >= 5
		return msg[1..4].unpack('N')[0], msg[5..-1]
	elsif v == 0xff and n >= 9
		return msg[1..8].unpack('Q>')[0], msg[9..-1]
	else
		return nil
	end
end

def get_varstr(msg)
	v, r = get_varint(msg)
	return nil if v == nil
	[r[0...v], r[v..-1]]
end

def get_varint_list(msg)
	v, r = get_varint(msg)
	return nil if v == nil
	ret = []
	v.times do
		n, r = get_varint(r)
		return nil if n == nil
		ret << n
	end
	[ret, r]
end

def get_net_addr(msg, version=1)
	if version == 1
		return get_net_addr_v1(msg)
	elsif version == 2
		return get_net_addr_v2(msg)
	elsif version == 3
		# puts "Protocol v3: not implement, use v2 to parse"
		return get_net_addr_v2(msg)
	else
		return nil
	end
end

def get_net_addr_v1(msg)
	len = 34
	return nil if msg.length < len
	ts, stream, services, ip, port = msg.unpack('NNQ>a16n')
	host = decode_ip ip
	return nil unless host
	ret = {}
	ret[:time] = ts
	ret[:stream] = stream
	ret[:services] = services
	ret[:host] = host
	ret[:port] = port
	return ret, msg[len..-1]
end

def get_net_addr_v2(msg)
	len = 38
	return nil if msg.length < len
	ts, stream, services, ip, port = msg.unpack('Q>NQ>a16n')
	host = decode_ip ip
	return nil unless host
	ret = {}
	ret[:time] = ts
	ret[:stream] = stream
	ret[:services] = services
	ret[:host] = host
	ret[:port] = port
	return ret, msg[len..-1]
end

def get_net_addr_without_stream(msg)
	len = 26
	return nil if msg.length < len
	services, ip, port = msg.unpack('Q>a16n')
	host = decode_ip ip
	return nil unless host
	ret = {}
	ret[:services] = services
	ret[:host] = host
	ret[:port] = port
	return ret, msg[len..-1]
end

def decode_ip(ip)
	begin
		prefix = "\0\0\0\0\0\0\0\0\0\0\xFF\xFF".b
		if ip.index(prefix) == 0
			return (ip[12..15].unpack('C*').map { |e| e.to_s }).join('.')
		else
			str = ''
			ip.bytes.each do |byte|
				high = byte >> 4
				low = (byte & 0x0f)
				str += high.to_s(16) + low.to_s(16)
			end
			return str.scan(/\w{4}/).join(':')
		end
	rescue Exception => e
		return nil
	end
end

def make_varint(num)
	if num < 0
		return nil
	elsif num < 0xfd
		return [num].pack('C')
	elsif num <= 0xffff
		return "\xfd".b + [num].pack('n')
	elsif num <= 0xffffffff
		return "\xfe".b + [num].pack('N')
	elsif num <= 0xffffffffffffffff
		return "\xff".b + [num].pack('Q>')
	else
		return nil
	end
end

def make_varstr(str)
	make_varint(str.length) + str
end

def make_varint_list(arr)
	ret = make_varint(arr.length)
	arr.each do |i|
		ret += make_varint(i)
	end
	ret
end

def make_addr_ipv4(stream, host, port, version)
	ts = ''
	if version == 1
		ts = [Time.now.to_i].pack('N')
	elsif version == 2 or version == 3
		ts = [Time.now.to_i].pack('Q>')
	else
		return nil
	end
	ss = [stream].pack('N')
	ts + ss + make_addr_ipv4_without_stream(host, port)
end

def make_addr_ipv6(stream, host, port, version)
	ts = ''
	if version == 1
		ts = [Time.now.to_i].pack('N')
	elsif version == 2 or version == 3
		ts = [Time.now.to_i].pack('Q>')
	else
		return nil
	end
	ss = [stream].pack('N')
	ts + ss + make_addr_ipv6_without_stream(host, port)
end

def make_addr_ipv4_without_stream(host, port)
	services = [1].pack('Q>')
	ip = "\x00"*10 + [65535].pack('n') + (host.split('.').map { |i| i.to_i }).pack('C4')
	port = [port].pack('n')
	services + ip + port
end

def make_addr_ipv6_without_stream(host, port)
	services = [1].pack('Q>')
	ip = (host.split(':').map { |e| e.to_i(16) }).pack('n8')
	port = [port].pack('n')
	services + ip + port
end

def msg_version(host, port)
	msg = ''
	msg += [BMConfig::Protocol_version, 1, Time.now.to_i].pack('NQ>2')
	msg += make_addr_ipv4_without_stream(host, port)
	msg += make_addr_ipv4_without_stream('0.0.0.0', 0)
	msg += [Random.rand(2**64)].pack('Q>')
	msg += make_varstr(BMConfig::User_agent)
	msg += make_varint_list([1])

	hdr = [BMConfig::Magic].pack('N') + "version" + "\x00"*5 + [msg.length].pack('N') + Digest::SHA512.digest(msg)[0...4]

	msg = hdr + msg
	msg
end

def msg_verack
	msg = ''
	hdr = [BMConfig::Magic].pack('N') + "verack" + "\x00"*6 + [msg.length].pack('N') + Digest::SHA512.digest(msg)[0...4]
	hdr
end

def msg_getdata(inventory)
	count = inventory.length
	msg = make_varint(count).b
	inventory.each do |inv|
		msg += inv.b
	end
	hdr = [BMConfig::Magic].pack('N') + "getdata" + "\x00"*5 + [msg.length].pack('N') + Digest::SHA512.digest(msg)[0...4]
	msg = hdr + msg
	msg
end

def msg_inv(inventory)
	count = inventory.length
	msg = make_varint(count).b
	inventory.each do |inv|
		msg += inv.b
	end
	hdr = [BMConfig::Magic].pack('N') + "inv" + "\x00"*9 + [msg.length].pack('N') + Digest::SHA512.digest(msg)[0...4]
	msg = hdr + msg
	msg
end

def msg_object(data)
	msg = data.b
	hdr = [BMConfig::Magic].pack('N') + "object" + "\x00"*6 + [msg.length].pack('N') + Digest::SHA512.digest(msg)[0...4]
	msg = hdr + msg
	msg
end

def proof_of_work(data)
	trials = BMConfig::NonceTrialsPerByte
	extra = BMConfig::PayloadLengthExtraBytes

	# nonce = data[0...8].unpack('Q>')[0]
	expire = data[8...16].unpack('Q>')[0]
	ttl = expire - Time.now.to_i
	ttl = 300 if ttl < 300

	plen = data.length + extra
	target = 2 ** 64 / (trials * (plen + ttl * plen / (2 ** 16)))

	inithash = Digest::SHA512.digest(data[8..-1])
	hash = data[0...8] + inithash
	hash = Digest::SHA512.digest(hash)
	hash = Digest::SHA512.digest(hash)

	result = hash[0...8].unpack('Q>')[0]
	result <= target
end
