require "spec_helper"

describe Invoker::ProcessManager do
  let(:process_manager) { Invoker::ProcessManager.new }

  describe "#start_process_by_name" do
    it "should find command by label and start it, if found" do
      invoker_config.stubs(:processes).returns([OpenStruct.new(:label => "resque", :cmd => "foo", :dir => "bar")])
      invoker_config.expects(:process).returns(OpenStruct.new(:label => "resque", :cmd => "foo", :dir => "bar"))
      process_manager.expects(:start_process).returns(true)

      process_manager.start_process_by_name("resque")
    end

    it "should not start already running process" do
      process_manager.workers.expects(:[]).returns(OpenStruct.new(:pid => "bogus"))
      expect(process_manager.start_process_by_name("resque")).to be_falsey
    end
  end

  describe "#stop_process" do
    context "when a worker is found" do
      before do
        process_manager.workers.expects(:[]).returns(OpenStruct.new(:pid => "bogus"))
      end

      context "if a stop signal is specified" do
        it "should use that signal to kill the worker" do
          process_name, stop_signal = 'bogus', 'HUP'

          process_manager.expects(:process_kill).with(process_name, stop_signal).returns(true)
          expect(process_manager.stop_process(process_name, stop_signal: stop_signal)).to be_truthy
        end
      end

      describe "if no stop signal is specified" do
        it "should use INT signal" do
          process_name = 'bogus'

          Invoker.config = mock
          Invoker.config.expects(:process).returns(OpenStruct.new(label: process_name))
          process_manager.expects(:process_kill).with(process_name, 'INT').returns(true)
          expect(process_manager.stop_process(process_name, stop_signal: nil)).to be_truthy
        end

        context 'if stop signal is specified in the config file' do
          it 'uses that signal to stop the process' do
            process_name = 'bogus'

            Invoker.config = mock
            Invoker.config.expects(:process).returns(OpenStruct.new(label: process_name, stop_signal: 'TERM'))
            process_manager.expects(:process_kill).with(process_name, 'TERM').returns(true)
            expect(process_manager.stop_process(process_name)).to be_truthy
          end
        end
      end
    end

    describe "when no worker is found" do
      before do
        process_manager.workers.expects(:[]).returns(nil)
      end

      it "should not kill anything" do
        process_manager.expects(:process_kill).never
        process_manager.stop_process('bogus')
      end
    end
  end

  describe "#load_env" do
    it "should load .env file from the specified directory" do
      dir = "/tmp"
      begin
        env_file = File.new("#{dir}/.env", "w")
        env_data =<<-EOD
FOO=foo
BAR=bar
        EOD
        env_file.write(env_data)
        env_file.close
        env_options = process_manager.load_env(dir)
        expect(env_options).to include("FOO" => "foo", "BAR" => "bar")
      ensure
        File.delete(env_file.path)
      end
    end

    it "should default to current directory if no directory is specified" do
      dir = ENV["HOME"]
      ENV.stubs(:[]).with("PWD").returns(dir)
      begin
        env_file = File.new("#{dir}/.env", "w")
        env_data =<<-EOD
FOO=bar
BAR=foo
        EOD
        env_file.write(env_data)
        env_file.close
        env_options = process_manager.load_env
        expect(env_options).to include("FOO" => "bar", "BAR" => "foo")
      ensure
        File.delete(env_file.path)
      end
    end

    it "should return empty hash if there is no .env file" do
      dir = "/tmp"
      expect(process_manager.load_env(dir)).to eq({})
    end
  end
end
