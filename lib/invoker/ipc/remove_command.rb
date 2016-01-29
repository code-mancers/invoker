module Invoker
  module IPC
    class RemoveCommand < BaseCommand
      def run_command(remove_message)
        process_or_group_name = remove_message.process_name
        processes = Invoker.config.processes_by_group_or_name(process_or_group_name)

        unless processes.size == 1
          processes.each do |process_info|
            unix_socket = Invoker::IPC::UnixClient.new
            unix_socket.send_command('remove', process_name: process_info.label, signal: remove_message.signal)
          end

          return true
        end

        Invoker.commander.on_next_tick(remove_message) do |remove_message|
          stop_process(remove_message.process_name, stop_signal: remove_message.signal)
        end

        true
      end
    end
  end
end
