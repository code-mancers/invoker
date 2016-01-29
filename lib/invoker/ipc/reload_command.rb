module Invoker
  module IPC
    class ReloadCommand < BaseCommand
      def run_command(reload_message)
        process_or_group_name = reload_message.process_name
        processes = Invoker.config.processes_by_group_or_name(process_or_group_name)

        unless processes.size == 1
          processes.each do |process_info|
            unix_socket = Invoker::IPC::UnixClient.new
            unix_socket.send_command('reload', process_name: process_info.label, signal: reload_message.signal)
          end

          return true
        end

        Invoker.commander.on_next_tick(reload_message) do |reload_message|
          restart_process(reload_message.process_name, stop_signal: reload_message.signal)
        end

        true
      end
    end
  end
end
