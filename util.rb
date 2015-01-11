# encoding: utf-8

def ip_version(ip)
	if ip.index('.')
		return 4
	elsif ip.index(':')
		return 6
	else
		return nil
	end
end

def hex_str(bstr)
	segs = bstr.bytes.map { |e| e.to_s(16) }
	ret = ''
	segs.each do |seg|
		while seg.length < 2
			seg = '0' + seg
		end
		ret += seg
	end
	ret
end

def bin_str(hstr)
	bytes = []
	hstr.scan(/\w\w/) do |seg|
		bytes << seg.to_i(16)
	end
	bytes.pack('C*')
end