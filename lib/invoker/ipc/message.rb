module Invoker
  module IPC
    module Message
      module Serialization
        def self.included(base)
          base.extend ClassMethods
        end

        def as_json
          attributes.merge(type: message_type)
        end

        def to_json
          JSON.generate(as_json)
        end

        def message_attributes
          self.class.message_attributes
        end

        def encoded_message
          json_data = to_json
          json_size = json_data.length.to_s
          length_str = json_size.rjust(Invoker::IPC::INITIAL_PACKET_SIZE, '0')
          length_str + json_data
        end

        def eql?(other)
          other.class == self.class &&
            compare_attributes(other)
        end

        def attributes
          message_attribute_keys = message_attributes || []
          message_attribute_keys.reduce({}) do |mem, obj|
            value = send(obj)
            if value.is_a?(Array)
              mem[obj] = serialize_array(value)
            elsif value.is_a?(Hash)
              mem[obj] = serialize_hash(value)
            else
              mem[obj] = value.respond_to?(:as_json) ? value.as_json : encode_as_utf(value)
            end
            mem
          end
        end

        private

        def compare_attributes(other)
          message_attributes.all? do |attribute_name|
            send(attribute_name).eql?(other.send(attribute_name))
          end
        end

        def encode_as_utf(value)
          return value unless value.is_a?(String)
          value.encode("utf-8", invalid: :replace, undef: :replace, replace: '_')
        end

        def serialize_array(attribute_array)
          attribute_array.map do |x|
            x.respond_to?(:as_json) ? x.as_json : encode_as_utf(x)
          end
        end

        def serialize_hash(attribute_hash)
          attribute_hash.inject({}) do |temp_mem, (temp_key, temp_value)|
            if temp_value.respond_to?(:as_json)
              temp_mem[temp_key] = temp_value.as_json
            else
              temp_mem[temp_key] = encode_as_utf(temp_value)
            end
          end
        end

        module ClassMethods
          def message_attributes(*incoming_attributes)
            if incoming_attributes.empty? && defined?(@message_attributes)
              @message_attributes
            else
              @message_attributes ||= []
              new_attributes = incoming_attributes.flatten
              @message_attributes += new_attributes
              attr_accessor *new_attributes
            end
          end
        end
      end

      class Base
        def initialize(options)
          options.each do |key, value|
            if self.respond_to?("#{key}=")
              send("#{key}=", value)
            end
          end
        end

        def message_type
          Invoker::IPC.underscore(self.class.name).split("/").last
        end

        def command_handler_klass
          Invoker::IPC.const_get("#{IPC.camelize(message_type)}Command")
        end
      end

      class Add < Base
        include Serialization
        message_attributes :process_name
      end

      class Tail < Base
        include Serialization
        message_attributes :process_names
      end

      class AddHttp < Base
        include Serialization
        message_attributes :process_name, :port
      end

      class Reload < Base
        include Serialization
        message_attributes :process_name, :signal

        def remove_message
          Remove.new(process_name: process_name, signal: signal)
        end
      end

      class List < Base
        include Serialization
      end

      class Process < Base
        include Serialization
        message_attributes :process_name, :shell_command, :dir, :pid
      end

      class Remove < Base
        include Serialization
        message_attributes :process_name, :signal
      end

      class DnsCheck < Base
        include Serialization
        message_attributes :host, :path
      end

      class DnsCheckResponse < Base
        include Serialization
        message_attributes :port
      end

      class Ping < Base
        include Serialization
      end

      class Pong < Base
        include Serialization
        message_attributes :status
      end
    end
  end
end

require "invoker/ipc/message/list_response"
require "invoker/ipc/message/tail_response"
