# encoding: utf-8

require 'socket'
require 'digest'

require './config'
require './message'
require './message_helper'
require './logger'
require './peer'

peers = []

BMConfig::BootNodes.each do |host, port|
	peers << (Peer.new host, port)
end

loop do 
	p (peers.map { |e| e.status })
	sleep 3
end