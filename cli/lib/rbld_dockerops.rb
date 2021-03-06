require 'docker_registry2'
require_relative 'rbld_log'
require_relative 'rbld_utils'
require 'highline'

module Rebuild
  module Registry
  module Docker
    extend Rebuild::Utils::Errors

    rebuild_errors \
      RegistryOperationError: nil,
      RegistryNotAuthenticatedError: nil

    class EnvironmentImage
      def initialize(api_module = ::Docker)
        @api_module = api_module
      end

      def publish(img, target_url)
        try_with_login { try_publish( img, target_url ) }
      end

      def deploy(source_url)
        try_with_login do
          try_deploy( source_url ) { |img| yield img }
        end
      end

      private

      def try_with_login
        begin
          yield
        rescue RegistryNotAuthenticatedError
          do_login
          yield
        end
      end

      def get_password
        HighLine.new($stdin, $stderr).ask('') { |q| q.echo = '*' }
      end

      def get_credential(name, is_secret = false)
        print "#{name}: "
        predefined = ENV["RBLD_CREDENTIAL_#{name.upcase}"]
        unless predefined.to_s.empty?
          puts "<environment>"
          predefined
        else
          is_secret ? get_password : STDIN.gets.chomp
        end
      end

      def get_secret_credential(name)
        get_credential( name, true )
      end

      def do_login
        puts
        puts "Login required"
        puts
        user = get_credential('Username')
        email = get_credential('Email')
        pwd = get_secret_credential('Password')
        @api_module.creds = { 'username' => user,
                              'password' => pwd,
                              'email' => email }
      end

      def try_publish(img, target_url)
        api_obj = img.api_obj
        api_obj.tag( repo: target_url.repo, tag: target_url.tag )

        begin
          rbld_log.info( "Pushing #{target_url.full}" )
          @last_error = nil
          api_obj.push(nil, :repo_tag => target_url.full) do |log|
            process_log( log )
          end
          raise_last_error
        ensure
          api_obj.remove( :name => target_url.full )
        end
      end

      def try_deploy(source_url)
        begin
          rbld_log.info( "Pulling #{source_url.full}" )
          @last_error = nil
          img = @api_module::Image.create(:fromImage => source_url.full) do |log|
            process_log( log )
          end
          raise_last_error
          yield img
        ensure
          img.remove( :name => source_url.full ) if img
        end
      end

      def process_log(log_item)
        json = Rebuild::Utils::SafeJSONParser.new( log_item )
        trace_progress( json['progress'] )
        save_last_error( json['errorDetail'] )
      end

      def trace_progress(line)
        rbld_print.inplace_trace( line ) if line
      end

      def save_last_error(line)
        @last_error = line['message'] if line
      end

      def raise_last_error
        case @last_error
          when nil
            # No error
          when /authentication required/, /unauthorized/, /denied/
            raise RegistryNotAuthenticatedError, @last_error
          else
            raise RegistryOperationError, @last_error
        end

      end

    end
  end
  end
end
