module Invoker
  module IPC
    class AddCommand < BaseCommand
      def run_command(add_message)
        process_or_group_name = add_message.process_name
        processes = Invoker.config.processes_by_group_or_name(process_or_group_name)

        unless processes.size == 1
          processes.each do |process_info|
            unix_socket = Invoker::IPC::UnixClient.new
            unix_socket.send_command('add', process_name: process_info.label)
          end

          return true
        end

        Invoker.commander.on_next_tick(add_message) do |add_message|
          start_process_by_name(add_message.process_name)
        end

        true
      end
    end
  end
end
