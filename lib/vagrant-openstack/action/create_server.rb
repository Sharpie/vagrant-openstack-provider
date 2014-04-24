require "fog"
require "log4r"
require 'socket'

require 'vagrant/util/retryable'

module VagrantPlugins
  module Openstack
    module Action
      # This creates the Openstack server.
      class CreateServer
        include Vagrant::Util::Retryable

        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_openstack::action::create_server")
        end

        def call(env)
          # Get the configs
          config = env[:machine].provider_config

          # Find the flavor
          env[:ui].info(I18n.t("vagrant_openstack.finding_flavor"))
          env[:ui].debug(env[:openstack_compute].flavors.all)
          flavor = find_matching(env[:openstack_compute].flavors.all, config.flavor)
          raise Errors::NoMatchingFlavor if !flavor

          # Find the image
          env[:ui].info(I18n.t("vagrant_openstack.finding_image"))
          image = find_matching(env[:openstack_compute].images.all, config.image)
          raise Errors::NoMatchingImage if !image

          # Figure out the name for the server
          server_name = config.server_name || env[:machine].name

          # Output the settings we're going to use to the user
          env[:ui].info(I18n.t("vagrant_openstack.launching_server"))
          env[:ui].info(" -- Flavor       : #{flavor.name}")
          env[:ui].info(" -- Image        : #{image.name}")
          env[:ui].info(" -- Disk Config  : #{config.disk_config}") if config.disk_config
          env[:ui].info(" -- Network      : #{config.network}") if config.network
          env[:ui].info(" -- Tenant       : #{config.tenant_name}")
          env[:ui].info(" -- Name         : #{server_name}")

          # Build the options for launching...
          options = {
            :flavor_ref         => flavor.id,
            :image_ref          => image.id,
            :name               => server_name,
            :metadata           => config.metadata,
            :key_name           => config.keypair_name,
            :availability_zone  => config.availability_zone
          }

          # Find a network if provided
          if config.network
            network = find_matching(env[:openstack_network].networks, config.network)
            options[:nics] = [{"net_id" => network.id}] if network
          end

          options[:disk_config] = config.disk_config if config.disk_config

          # Create the server
          server = env[:openstack_compute].servers.create(options)

          # Store the ID right away so we can track it
          env[:machine].id = server.id

          # Wait for the server to finish building
          env[:ui].info(I18n.t("vagrant_openstack.waiting_for_build"))
          retryable(:on => Fog::Errors::TimeoutError, :tries => 200) do # TODO retryable(:on => Timeout::Error, :tries => 200) do
            # If we're interrupted don't worry about waiting
            next if env[:interrupted]

            # Set the progress
            #env[:ui].clear_line
            #env[:ui].report_progress(server.progress, 100, false)

            # Wait for the server to be ready
            begin
              server.wait_for(25) { ready? }
              if config.floating_ip
                env[:ui].info("Using floating IP #{config.floating_ip}")
                floater = env[:openstack_compute].addresses.find { |thisone| thisone.ip.eql? config.floating_ip }
                floater.server = server
              end
            rescue RuntimeError => e
              # If we don't have an error about a state transition, then
              # we just move on.
              raise if e.message !~ /should have transitioned/
              raise Errors::CreateBadState, :state => server.state
            end
          end

          if !env[:interrupted]
            # Clear the line one more time so the progress is removed
            env[:ui].clear_line

            # Wait for RackConnect to complete
            if ( config.rackconnect )
              env[:ui].info(I18n.t("vagrant_openstack.waiting_for_rackconnect"))
              while true
                status = server.metadata.all["rackconnect_automation_status"]
                if ( !status.nil? )
                  env[:ui].info( status )
                end
                break if env[:interrupted]
                break if (status.to_s =~ /deployed/i)
                sleep 10
              end
            end

            # Wait for SSH to become available
            host = env[:machine].provider_config.floating_ip
            ssh_timeout = env[:machine].provider_config.ssh_timeout
            if !port_open?(env, host, 22, ssh_timeout)
              env[:ui].error(I18n.t("vagrant_openstack.timeout"))
              raise Errors::SshUnavailable,
                    :host    => host,
                    :timeout => ssh_timeout
            end

            env[:ui].info(I18n.t("vagrant_openstack.ready"))
          end

          @app.call(env)
        end

        protected

        def port_open?(env, ip, port, timeout)
          start_time = Time.now
          current_time = start_time
          while (current_time - start_time) <= timeout
            begin
              env[:ui].info(I18n.t("vagrant_openstack.waiting_for_ssh"))
              TCPSocket.new(ip, port)
              return true
            rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
              sleep 1
            end
            current_time = Time.now
          end
          return false
        end

        # This method finds a matching _thing_ in a collection of
        # _things_. This works matching if the ID or NAME equals to
        # `name`. Or, if `name` is a regexp, a partial match is chosen
        # as well.
        def find_matching(collection, name)
          collection.each do |single|
            return single if single.id == name
            return single if single.name == name
            return single if name.is_a?(Regexp) && name =~ single.name
          end

          nil
        end
      end
    end
  end
end
