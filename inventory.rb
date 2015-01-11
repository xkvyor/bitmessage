# encoding: utf-8

require './config'
require 'fileutils'
require 'singleton'
require './util'

class Inventory
	include Singleton

	CacheSize = 65536

	def initialize
		@dir = BMConfig::InventoryDir
		unless Dir.exist? @dir
			FileUtils.mkdir_p @dir
		end
		@mutex = Mutex.new
		@mem = {}
		@hash_ondisk = {}
		Dir.foreach(@dir) do |file|
			next if file == '.' or file == '..'
			@hash_ondisk[file] = true
		end
	end

	def get(hash)
		@mutex.synchronize do
			return @mem[hash] if @mem[hash]
			str = hex_str hash
			if File.exist? "#{@dir}/#{str}"
				data = nil
				open("#{@dir}/#{str}}", 'rb') do |f|
					data = f.read
				end
				return data
			end
		end
		nil
	end

	def set(hash, data)
		return if get(hash)
		@mutex.synchronize do
			@mem[hash] = data
			sync_disk if @mem.length >= CacheSize
		end
	end

	def known?(hash)
		@mutex.synchronize do
			return true if @mem[hash]
			return @hash_ondisk[hash]
		end
	end

	def update
		@mutex.synchronize do
			sync_disk
			Dir.foreach(@dir) do |file|
				next if file == '.' or file == '..'
				if out_of_date? file
					FileUtils.rm_f file
				end
			end
			refresh_disk_hash
		end
	end

	def all_hash
		@mutex.synchronize do
			return @hash_ondisk.keys.concat(@mem.keys)
		end
	end

	private

	def sync_disk
		@mem.each do |hash, data|
			open("#{@dir}/#{hex_str(hash)}", 'wb') do |f|
				f.write data
			end
		end
		@mem = {}
		refresh_disk_hash
	end

	def out_of_date?(filename)
		begin
			ts = 0
			open(filename, 'rb') do |f|
				data = f.read(16)
				ts = data[8...16].unpack('Q>')
			end
			return true if Time.at(ts)-Time.now>0
		rescue Exception => e
		end
		false
	end

	def refresh_disk_hash
		@hash_ondisk = {}
		Dir.foreach(@dir) do |file|
			next if file == '.' or file == '..'
			bin = bin_str file
			@hash_ondisk[bin] = true
		end
	end
end

# inv = Inventory.instance
# p inv.all_hash.length

