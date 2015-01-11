
require 'socket'
require './message_helper'

s = TCPSocket.new '98.218.125.214', 8444
s.send msg_version('98.218.125.214', 8444), 0
p s.recv(1024)

p s.recv(1024)
s.send msg_verack, 0
p s.recv(1024)