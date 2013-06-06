#
# Author:: John Keiser (<jkeiser@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'puma'
require 'rubygems'
require 'timeout'
require 'chef_zero/version'
require 'chef_zero/rack_app'

module ChefZero
  class PumaServer
    DEFAULT_OPTIONS = {
      :host => '127.0.0.1',
      :port => 8889,
      :log_level => :info,
      :generate_real_keys => false,
      :data_store => nil
    }.freeze

    def initialize(options = {})
      options = DEFAULT_OPTIONS.merge(options)
      @app = ChefZero::RackApp.new("http://#{options[:host]}:#{options[:port]}", options)
      ChefZero::Log.level = options[:log_level].to_sym
      @server = Puma::Server.new(@app, Puma::Events.new(STDERR, STDOUT))
      @server.add_tcp_listener(options[:host], options[:port])
    end

    attr_reader :server
    attr_reader :app

    def data_store
      app.data_store
    end

    def start(options = {})
      if options[:publish]
        puts ">> Starting Chef Zero (v#{ChefZero::VERSION})..."
        puts ">> Puma (v#{Puma::Const::PUMA_VERSION}) is listening at #{url}"
        puts ">> Press CTRL+C to stop"
      end

      begin
        thread = server.run.join
      rescue Object, Interrupt
        puts "\n>> Stopping Puma..."
        server.stop(true) if running?
      end
    end

    def start_background(wait = 5)
      @thread = Thread.new {
        begin
          start
        rescue
          @server_error = $!
          ChefZero::Log.error("#{$!.message}\n#{$!.backtrace.join("\n")}")
        end
      }

      # Wait x seconds to make sure the server actually started
      Timeout::timeout(wait) {
        sleep(0.01) until running? || @server_error
        raise @server_error if @server_error
      }

      # Give the user the thread, just in case they want it
      @thread
    end

    def running?
      !!server.running
    end

    def stop(wait = 5)
      if @thread
        @thread.join(wait)
      else
        server.stop(true)
      end
    rescue
      ChefZero::Log.error "Server did not stop within #{wait} seconds. Killing..."
      @thread.kill if @thread
    ensure
      @thread = nil
    end
  end
end
