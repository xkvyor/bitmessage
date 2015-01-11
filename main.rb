# encoding: utf-8

require 'socket'
require 'digest'

require './config'
require './message'
require './message_helper'
require './logger'
require './nodesdb'
require './peer'

nodes = NodesDB.instance

BMConfig::BootNodes.each do |host, port|
	nodes.new_node host, port
end

max_peer = 3
run = true

trap('SIGINT') do
	run = false
end

while run do
	nodes.known_nodes do |host, port|
		nodes.new_peer host, port if nodes.peer_count < max_peer
	end
	puts "-"*16+" [#{Time.now.to_s}] "+"-"*16
	nodes.each_peer do |peer|
		puts "Peer #{peer.id} #{peer.host}:#{peer.port}"
	end
	sleep 3
	nodes.update
end

puts 'writing inventory to disk ...'
Inventory.instance.update