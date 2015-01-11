# encoding: utf-8

require './config'
require 'singleton'

class MessageQueue
	def initialize
		@q = []
		@mutex = Mutex.new
	end

	def push(msg)
		@mutex.synchronize { @q << msg }
	end

	def pop
		@mutex.synchronize { @q.shift }
	end
end

class Broadcaster
	include Singleton

	def initialize
		@queues = {}
		@mutex = Mutex.new
	end

	def register(q)
		@mutex.synchronize do
			if @queues[q]
				@queues.delete q
			end
			@queues[q] = true
		end
	end

	def unregister(q)
		@mutex.synchronize do
			if @queues[q]
				@queues.delete q
			end
		end
	end

	def put(msg)
		@mutex.synchronize do
			@queues.each do |q, e|
				q.push msg
			end
		end
	end
end
