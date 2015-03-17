require 'iniparse'

module Invoker
  module Parsers
    class Config
      PORT_REGEX = /\$PORT/
      attr_accessor :processes, :power_config

      def initialize(filename, port)
        @filename = filename
        @port = port
        @processes = load_config
        if Invoker.can_run_balancer?
          @power_config = Invoker::Power::Config.load_config()
        end
      end

      def http_port
        power_config && power_config.http_port
      end

      def dns_port
        power_config && power_config.dns_port
      end

      def https_port
        power_config && power_config.https_port
      end

      def autorunnable_processes
        processes.reject(&:disable_autorun)
      end

      def process(label)
        processes.detect { |pconfig| pconfig.label == label }
      end

      private

      def load_config
        if is_global?
          @filename = to_global_file
        end

        if is_ini?
          process_ini
        elsif is_procfile?
          process_procfile
        else
          Invoker::Logger.puts("\n Invalid config file. Invoker requires an ini or a Procfile.".color(:red))
          abort
        end
      end

      def process_ini
        ini_content = File.read(@filename)
        document = IniParse.parse(ini_content)
        document.map do |section|
          check_directory(section["directory"])
          process_command_from_section(section)
        end
      end

      def process_procfile
        procfile = Invoker::Parsers::Procfile.new(@filename)
        procfile.entries.map do |name, command|
          section = { "label" => name, "command" => command }
          process_command_from_section(section)
        end
      end

      def process_command_from_section(section)
        if supports_subdomain?(section)
          port = pick_port(section)
          if port
            command = replace_port_in_command(section['command'], port)
            section['port'], section['command'] = port, command
          end
        end

        make_pconfig(section)
      end

      def pick_port(section)
        if section['command'] =~ PORT_REGEX
          @port += 1
        elsif section['port']
          section['port']
        else
          nil
        end
      end

      def make_pconfig(section)
        pconfig = {
          label: section["label"] || section.key,
          dir: expand_directory(section["directory"]),
          cmd: section["command"]
        }
        pconfig['port'] = section['port'] if section['port']
        pconfig['disable_autorun'] = section['disable_autorun'] if section['disable_autorun']

        OpenStruct.new(pconfig)
      end

      def supports_subdomain?(section)
        (section['command'] =~ PORT_REGEX) || section['port']
      end

      def check_directory(app_dir)
        if app_dir && !app_dir.empty? && !File.directory?(expand_directory(app_dir))
          raise Invoker::Errors::InvalidConfig.new("Invalid directory #{app_dir}")
        end
      end

      def expand_directory(app_dir)
        File.expand_path(app_dir) if app_dir
      end

      def replace_port_in_command(command, port)
        if command =~ PORT_REGEX
          command.gsub(PORT_REGEX, port.to_s)
        else
          command
        end
      end

      def is_ini?
        File.extname(@filename) == '.ini'
      end

      def is_procfile?
        @filename =~ /Procfile/
      end

      def to_global_file
        File.join(Invoker::Power::Config.config_dir, "#{@filename}.ini")
      end

      def is_global?
        @filename =~ /^\w+$/ && File.exists?(to_global_file)
      end
    end
  end
end
