$: << File.dirname(__FILE__) unless $:.include?(File.expand_path(File.dirname(__FILE__)))

require "fileutils"
require "formatador"

require "ostruct"
require "uuid"
require "json"
require "colorize"
require "etc"

require "invoker/version"
require "invoker/logger"
require "invoker/daemon"
require "invoker/cli"
require "invoker/dns_cache"
require "invoker/ipc"
require "invoker/power/config"
require "invoker/power/port_finder"
require "invoker/power/setup"
require "invoker/power/setup/linux_setup"
require "invoker/power/setup/osx_setup"
require "invoker/power/powerup"
require "invoker/errors"
require "invoker/parsers/procfile"
require "invoker/parsers/config"
require "invoker/commander"
require "invoker/process_manager"
require "invoker/command_worker"
require "invoker/reactor"
require "invoker/event/manager"
require "invoker/process_printer"

module Invoker
  class << self
    attr_accessor :config, :tail_watchers, :commander
    attr_accessor :dns_cache, :daemonize, :nocolors, :certificate, :private_key

    alias_method :daemonize?, :daemonize
    alias_method :nocolors?, :nocolors

    def darwin?
      ruby_platform.downcase.include?("darwin")
    end

    def linux?
      ruby_platform.downcase.include?("linux")
    end

    def ruby_platform
      RUBY_PLATFORM
    end

    def load_invoker_config(file, port)
      @config = Invoker::Parsers::Config.new(file, port)
      @dns_cache = Invoker::DNSCache.new(@invoker_config)
      @tail_watchers = Invoker::CLI::TailWatcher.new
      @commander = Invoker::Commander.new
    end

    def close_socket(socket)
      socket.close
    rescue StandardError => error
      Invoker::Logger.puts "Error removing socket #{error}"
    end

    def daemon
      @daemon ||= Invoker::Daemon.new
    end

    def can_run_balancer?(throw_warning = true)
      return true if File.exist?(Invoker::Power::Config.config_file)

      if throw_warning
        Invoker::Logger.puts("Invoker has detected setup has not been run. Domain feature will not work without running setup command.".colorize(:red))
      end
      false
    end

    def setup_config_location
      config_dir = Invoker::Power::Config.config_dir
      return config_dir if Dir.exist?(config_dir)

      if File.exist?(config_dir)
        old_config = File.read(config_dir)
        FileUtils.rm_f(config_dir)
      end

      FileUtils.mkdir(config_dir)

      migrate_old_config(old_config, config_dir) if old_config
      config_dir
    end

    def run_without_bundler
      if defined?(Bundler)
        Bundler.with_unbundled_env do
          yield
        end
      else
        yield
      end
    end

    def notify_user(message)
      if Invoker.darwin?
        run_without_bundler { check_and_notify_with_terminal_notifier(message) }
      elsif Invoker.linux?
        notify_with_libnotify(message)
      end
    end

    def check_and_notify_with_terminal_notifier(message)
      command_path = `which terminal-notifier`
      if command_path && !command_path.empty?
        system("terminal-notifier -message '#{message}' -title Invoker")
      end
    end

    def notify_with_libnotify(message)
      begin
        require "libnotify"
        Libnotify.show(body: message, summary: "Invoker", timeout: 2.5)
      rescue LoadError; end
    end

    def migrate_old_config(old_config, config_location)
      new_config = File.join(config_location, 'config')
      File.open(new_config, 'w') do |file|
        file.write(old_config)
      end
    end

    # On some platforms `Dir.home` or `ENV['HOME']` does not return home directory of user.
    # this is especially true, after effective and real user id of process
    # has been changed.
    #
    # @return [String] home directory of the user
    def home
      if File.writable?(Dir.home)
        Dir.home
      else
        Etc.getpwuid(Process.uid).dir
      end
    end

    def default_tld
      'test'
    end
  end
end
