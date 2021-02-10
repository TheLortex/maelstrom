# Shared functions for all nodes.

require 'json'

class Node
  attr_accessor :node_id, :node_ids

  def initialize
    @node_id = nil
    @node_ids = nil
    @next_msg_id = 0
    @handlers = {}
    @callbacks = {}
    @lock = Mutex.new

    @in_buffer = ""

    # Register an initial handler for the init message
    on "init" do |msg|
      body = msg[:body]
      @node_id = body[:node_id]
      @node_ids = body[:node_ids]
      STDERR.puts "Node initialized"
      reply! msg, {type: "init_ok"}
    end
  end

  # Register a new message type handler
  def on(type, &handler)
    if @handlers[type]
      raise "Already have a handler for #{type}!"
    end

    @handlers[type] = handler
  end

  # Send a body to the given node id. Fills in src with our own node_id.
  def send!(dest, body)
    msg = {dest: dest,
           src: @node_id,
           body: body}
    @lock.synchronize do
      STDERR.puts "Sent #{msg.inspect}"
      JSON.dump msg, STDOUT
      STDOUT << "\n"
      STDOUT.flush
    end
  end

  # Reply to a request with a response body
  def reply!(req, body)
    body = body.merge in_reply_to: req[:body][:msg_id]
    send! req[:src], body
  end

  # Send an async RPC request
  def rpc!(dest, body, &handler)
    @lock.synchronize do
      msg_id = @next_msg_id += 1
      @callbacks[msg_id] = handler
      body[:msg_id] = msg_id
      send! dest, body
    end
  end

  # Loops, processing messages.
  def main!
    while line = STDIN.gets
      msg = JSON.parse line, symbolize_names: true
      @logger << "Received #{msg.inspect}"

      handler = nil
      if handler = @callbacks[msg[:body][:in_reply_to]]
        @callbacks.delete msg[:body][:in_reply_to]
      elsif handler = @handlers[msg[:body][:type]]
      else
        raise "No callback or handler for #{msg.inspect}"
      end
      handler.call msg
    end
  end
end