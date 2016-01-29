require "spec_helper"

require "tempfile"

describe "Invoker::Config" do
  describe "with invalid directory" do
    it "should raise error during startup" do
      begin
        file = Tempfile.new(["invalid_config", ".ini"])

        config_data =<<-EOD
[try_sleep]
directory = /Users/gnufied/foo
command = ruby try_sleep.rb
      EOD
        file.write(config_data)
        file.close
        expect {
          Invoker::Parsers::Config.new(file.path, 9000)
        }.to raise_error(Invoker::Errors::InvalidConfig)
      ensure
        file.unlink()
      end
    end
  end

  describe "with relative directory path" do
    it "should expand path in commands" do
      begin
        file = Tempfile.new(["config", ".ini"])

        config_data =<<-EOD
[pwd_home]
directory = ~
command = pwd

[pwd_parent]
directory = ../
command = pwd
      EOD
        file.write(config_data)
        file.close

        config = Invoker::Parsers::Config.new(file.path, 9000)
        command1 = config.processes.first

        expect(command1.dir).to match(File.expand_path('~'))

        command2 = config.processes[1]

        expect(command2.dir).to match(File.expand_path('..'))
      ensure
        file.unlink()
      end
    end
  end

  describe "for ports" do
    it "should replace port in commands" do
      begin
        file = Tempfile.new(["invalid_config", ".ini"])

        config_data =<<-EOD
[try_sleep]
directory = /tmp
command = ruby try_sleep.rb -p $PORT

[ls]
directory = /tmp
command = ls -p $PORT

[noport]
directory = /tmp
command = ls
      EOD
        file.write(config_data)
        file.close

        config = Invoker::Parsers::Config.new(file.path, 9000)
        command1 = config.processes.first

        expect(command1.port).to eq(9000)
        expect(command1.cmd).to match(/9000/)

        command2 = config.processes[1]

        expect(command2.port).to eq(9001)
        expect(command2.cmd).to match(/9001/)

        command2 = config.processes[2]

        expect(command2.port).to be_nil
      ensure
        file.unlink()
      end
    end

    it "should use port from separate option" do
      begin
        file = Tempfile.new(["invalid_config", ".ini"])
        config_data =<<-EOD
[try_sleep]
directory = /tmp
command = ruby try_sleep.rb -p $PORT

[ls]
directory = /tmp
port = 3000
command = pwd

[noport]
directory = /tmp
command = ls
      EOD
        file.write(config_data)
        file.close

        config = Invoker::Parsers::Config.new(file.path, 9000)
        command1 = config.processes.first

        expect(command1.port).to eq(9000)
        expect(command1.cmd).to match(/9000/)

        command2 = config.processes[1]

        expect(command2.port).to eq(3000)

        command2 = config.processes[2]

        expect(command2.port).to be_nil
      ensure
        file.unlink()
      end
    end
  end

  describe "loading power config" do
    before do
      @file = Tempfile.new(["config", ".ini"])
    end

    it "does not load config if platform is darwin but there is no power config file" do
      Invoker::Power::Config.expects(:load_config).never
      Invoker::Parsers::Config.new(@file.path, 9000)
    end

    it "loads config if platform is darwin and power config file exists" do
      File.open(Invoker::Power::Config.config_file, "w") { |fl| fl.puts "sample" }
      Invoker::Power::Config.expects(:load_config).once
      Invoker::Parsers::Config.new(@file.path, 9000)
    end
  end

  describe "Procfile" do
    it "should load Procfiles and create config object" do
      begin
        File.open("/tmp/Procfile", "w") {|fl|
          fl.write <<-EOD
web: bundle exec rails s -p $PORT
          EOD
        }
        config = Invoker::Parsers::Config.new("/tmp/Procfile", 9000)
        command1 = config.processes.first

        expect(command1.port).to eq(9000)
        expect(command1.cmd).to match(/bundle exec rails/)
      ensure
        File.delete("/tmp/Procfile")
      end
    end
  end

  describe "Copy of DNS information" do
    it "should allow copy of DNS information" do
      begin
        File.open("/tmp/Procfile", "w") {|fl|
          fl.write <<-EOD
web: bundle exec rails s -p $PORT
          EOD
        }
        Invoker.load_invoker_config("/tmp/Procfile", 9000)
        dns_cache = Invoker::DNSCache.new(Invoker.config)

        expect(dns_cache.dns_data).to_not be_empty
        expect(dns_cache.dns_data['web']).to_not be_empty
        expect(dns_cache.dns_data['web']['port']).to eql 9000
      ensure
        File.delete("/tmp/Procfile")
      end
    end
  end

  describe 'stop signal option' do
    it 'allows specifying a custom stop signal for each process' do
      begin
        file = Tempfile.new(["config", ".ini"])
        config_data =<<-EOD
[postgres]
command = postgres -D /usr/local/var/postgres
stop_signal = TERM

[redis]
command = redis-server /usr/local/etc/redis.conf
EOD
        file.write(config_data)
        file.close

        config = Invoker::Parsers::Config.new(file.path, 9000)
        config.process('postgres').stop_signal.should == 'TERM'
      ensure
        file.unlink()
      end
    end
  end

  describe "#autorunnable_processes" do
    it "returns a list of processes that can be autorun" do
      begin
        file = Tempfile.new(["config", ".ini"])
        config_data =<<-EOD
[postgres]
command = postgres -D /usr/local/var/postgres

[redis]
command = redis-server /usr/local/etc/redis.conf
disable_autorun = true

[memcached]
command = /usr/local/opt/memcached/bin/memcached
disable_autorun = false

[panda-api]
command = bundle exec rails s
disable_autorun = true

[panda-auth]
command = bundle exec rails s -p $PORT
EOD
        file.write(config_data)
        file.close

        config = Invoker::Parsers::Config.new(file.path, 9000)
        expect(config.autorunnable_processes.map(&:label)).to eq(['postgres', 'memcached', 'panda-auth'])
      ensure
        file.unlink()
      end
    end
  end

  describe "global config file" do
    it "should use global config file if available" do
      begin
        filename = "#{Invoker::Power::Config.config_dir}/foo.ini"
        file = File.open(filename, "w")
        config_data =<<-EOD
[try_sleep]
directory = /tmp
command = ruby try_sleep.rb
        EOD
        file.write(config_data)
        file.close
        config = Invoker::Parsers::Config.new("foo", 9000)
        expect(config.filename).to eql(filename)
      ensure
        File.unlink(filename)
      end
    end
  end

  describe "config file autodetection" do
    context "no config file given" do

      def create_invoker_ini
        file = File.open("invoker.ini", "w")
        config_data =<<-EOD
[some_process]
command = some_command
        EOD
        file.write(config_data)
        file.close

        file
      end

      def create_procfile
        file = File.open("Procfile", "w")
        config_data =<<-EOD
some_other_process: some_other_command
        EOD
        file.write(config_data)
        file.close

        file
      end

      context "directory has invoker.ini" do
        it "autodetects invoker.ini" do
          begin
            file = create_invoker_ini

            config = Invoker::Parsers::Config.new(nil, 9000)
            expect(config.process("some_process").cmd).to eq("some_command")
          ensure
            File.delete(file)
          end
        end
      end

      context "directory has Procfile" do
        it "autodetects Procfile" do
          begin
            file = create_procfile

            config = Invoker::Parsers::Config.new(nil, 9000)
            expect(config.process("some_other_process").cmd).to eq("some_other_command")
          ensure
            File.delete(file)
          end
        end
      end

      context "directory has both invoker.ini and Procfile" do
        it "prioritizes invoker.ini" do
          begin
            invoker_ini = create_invoker_ini
            procfile = create_procfile

            config = Invoker::Parsers::Config.new(nil, 9000)
            expect(config.process("some_process").cmd).to eq("some_command")
          ensure
            File.delete(invoker_ini)
            File.delete(procfile)
          end
        end
      end

      context "directory doesn't have invoker.ini or Procfile" do
        it "aborts" do
          expect { Invoker::Parsers::Config.new(nil, 9000) }.to raise_error(SystemExit)
        end
      end
    end
  end

  describe "#processes_by_group_or_name" do
    before(:each) do
      @config_file = Tempfile.new(["config", ".ini"])
      config_data =<<-EOD
[postgres]
command = postgres -D /usr/local/var/postgres
group = db

[redis]
command = redis-server /usr/local/etc/redis.conf
group = db

[memcached]
command = /usr/local/opt/memcached/bin/memcached
group = db

[panda-api]
command = bundle exec rails s

[panda-auth]
command = bundle exec rails s -p $PORT
EOD
      @config_file.write(config_data)
      @config_file.close
    end

    after(:each) do
      @config_file.unlink
    end

    context 'given group name' do
      it 'returns a list of processes that belong to that group' do
        config = Invoker::Parsers::Config.new(@config_file.path, 9000)
        pconfigs = config.processes_by_group_or_name('db')
        expect(pconfigs.map(&:label)).to eq(['postgres', 'redis', 'memcached'])
      end
    end

    context 'given process name' do
      it 'returns the process wrapped in an array' do
        config = Invoker::Parsers::Config.new(@config_file.path, 9000)
        pconfigs = config.processes_by_group_or_name('panda-api')
        expect(pconfigs.map(&:label)).to eq(['panda-api'])
      end
    end
  end
end
