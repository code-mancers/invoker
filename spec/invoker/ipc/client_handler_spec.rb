require "spec_helper"

describe Invoker::IPC::ClientHandler do
  let(:client_socket) { StringIO.new }
  let(:client) { Invoker::IPC::ClientHandler.new(client_socket) }

  describe "add command" do
    it "should run if read from socket" do
      begin
        file = File.open("invoker.ini", "w")
        config_data =<<-EOD
[foo]
command = bar
        EOD
        file.write(config_data)
        file.close
        Invoker.load_invoker_config(file, 3000)

        message_object = MM::Add.new(process_name: 'foo')
        invoker_commander.expects(:on_next_tick).with { |message_object| message_object.process_name == 'foo' }
        client_socket.string = message_object.encoded_message

        client.read_and_execute
      ensure
        File.delete(file)
      end
    end
  end

  describe "remove command" do
    it "with specific signal" do
      begin
        file = File.open("invoker.ini", "w")
        config_data =<<-EOD
[foo]
command = bar
        EOD
        file.write(config_data)
        file.close
        Invoker.load_invoker_config(file, 3000)

        message_object = MM::Remove.new(process_name: 'foo', signal: 'INT')
        invoker_commander.expects(:on_next_tick)
        client_socket.string = message_object.encoded_message

        client.read_and_execute
      ensure
        File.delete(file)
      end
    end

    it "with default signal" do
      begin
        file = File.open("invoker.ini", "w")
        config_data =<<-EOD
[foo]
command = bar
        EOD
        file.write(config_data)
        file.close
        Invoker.load_invoker_config(file, 3000)

        message_object = MM::Remove.new(process_name: 'foo')
        invoker_commander.expects(:on_next_tick)
        client_socket.string = message_object.encoded_message

        client.read_and_execute
      ensure
        File.delete(file)
      end
    end
  end

  describe "add_http command" do
    let(:message_object) { MM::AddHttp.new(process_name: 'foo', port: 9000)}
    it "adds the process name and port to dns cache" do
      invoker_dns_cache.expects(:add).with('foo', 9000, nil)
      client_socket.string = message_object.encoded_message

     client.read_and_execute
    end
  end

  describe "add_http command with optional ip" do
    let(:message_object) { MM::AddHttp.new(process_name: 'foo', port: 9000, ip: '192.168.0.1')}
    it "adds the process name, port and host ip to dns cache" do
      invoker_dns_cache.expects(:add).with('foo', 9000, '192.168.0.1')
      client_socket.string = message_object.encoded_message

     client.read_and_execute
    end
  end
end
