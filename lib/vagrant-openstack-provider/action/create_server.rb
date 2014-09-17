require 'log4r'
require 'socket'
require 'timeout'
require 'sshkey'

require 'vagrant/util/retryable'

module VagrantPlugins
  module Openstack
    module Action
      class CreateServer
        include Vagrant::Util::Retryable

        def initialize(app, _env)
          @app = app
          @logger = Log4r::Logger.new('vagrant_openstack::action::create_server')
        end

        def call(env)
          @logger.info 'Start create server action'

          config = env[:machine].provider_config

          fail Errors::MissingBootOption if config.image.nil? && config.volume_boot.nil?
          fail Errors::ConflictBootOption unless config.image.nil? || config.volume_boot.nil?

          nova = env[:openstack_client].nova

          options = {
            flavor: resolve_flavor(env),
            image: resolve_image(env),
            volume_boot: resolve_volume_boot(env),
            networks: resolve_networks(env),
            volumes: resolve_volumes(env),
            keypair_name: resolve_keypair(env),
            availability_zone: env[:machine].provider_config.availability_zone
          }

          server_id = create_server(env, options)

          # Store the ID right away so we can track it
          env[:machine].id = server_id

          waiting_for_server_to_be_build(env, server_id)

          floating_ip = resolve_floating_ip(env)
          if floating_ip && !floating_ip.empty?
            @logger.info "Using floating IP #{floating_ip}"
            env[:ui].info(I18n.t('vagrant_openstack.using_floating_ip', floating_ip: floating_ip))
            nova.add_floating_ip(env, server_id, floating_ip)
          end

          attach_volumes(env, server_id, options[:volumes]) unless options[:volumes].empty?

          unless env[:interrupted]
            # Clear the line one more time so the progress is removed
            env[:ui].clear_line

            # Wait for SSH to become available
            ssh_timeout = env[:machine].provider_config.ssh_timeout
            unless port_open?(env, floating_ip, 22, ssh_timeout)
              env[:ui].error(I18n.t('vagrant_openstack.timeout'))
              fail Errors::SshUnavailable, host: floating_ip, timeout: ssh_timeout
            end

            @logger.info 'The server is ready'
            env[:ui].info(I18n.t('vagrant_openstack.ready'))
          end

          @app.call(env)
        end

        private

        # 1. if floating_ip is set, use it
        # 2. if floating_ip_pool is set
        #    GET v2/{{tenant_id}}/os-floating-ips
        #    If any IP with the same pool is available, use it
        #    Else Allocate a new IP from the pool
        #       Manage error case
        # 3. GET v2/{{tenant_id}}/os-floating-ips
        #    If any IP is available, use it
        #    Else fail
        def resolve_floating_ip(env)
          config = env[:machine].provider_config
          nova = env[:openstack_client].nova
          return config.floating_ip if config.floating_ip
          floating_ips = nova.get_all_floating_ips(env)
          if config.floating_ip_pool
            floating_ips.each do |single|
              return single.ip if single.pool == config.floating_ip_pool && single.instance_id.nil?
            end unless config.floating_ip_pool_always_allocate
            return nova.allocate_floating_ip(env, config.floating_ip_pool).ip
          else
            floating_ips.each do |ip|
              return ip.ip if ip.instance_id.nil?
            end
          end
          fail Errors::UnableToResolveFloatingIP
        end

        def resolve_keypair(env)
          config = env[:machine].provider_config
          nova = env[:openstack_client].nova
          return config.keypair_name if config.keypair_name
          return nova.import_keypair_from_file(env, config.public_key_path) if config.public_key_path
          generate_keypair(env)
        end

        def generate_keypair(env)
          key = SSHKey.generate
          nova = env[:openstack_client].nova
          generated_keyname = nova.import_keypair(env, key.ssh_public_key)
          File.write("#{env[:machine].data_dir}/#{generated_keyname}", key.private_key)
          generated_keyname
        end

        def resolve_flavor(env)
          @logger.info 'Resolving flavor'
          config = env[:machine].provider_config
          nova = env[:openstack_client].nova
          env[:ui].info(I18n.t('vagrant_openstack.finding_flavor'))
          flavors = nova.get_all_flavors(env)
          @logger.info "Finding flavor matching name '#{config.flavor}'"
          flavor = find_matching(flavors, config.flavor)
          fail Errors::NoMatchingFlavor unless flavor
          flavor
        end

        def resolve_image(env)
          @logger.info 'Resolving image'
          config = env[:machine].provider_config
          return nil if config.image.nil?
          nova = env[:openstack_client].nova
          env[:ui].info(I18n.t('vagrant_openstack.finding_image'))
          images = nova.get_all_images(env)
          @logger.info "Finding image matching name '#{config.image}'"
          image = find_matching(images, config.image)
          fail Errors::NoMatchingImage unless image
          image
        end

        def resolve_networks(env)
          @logger.info 'Resolving network(s)'
          config = env[:machine].provider_config
          return [] if config.networks.nil? || config.networks.empty?
          env[:ui].info(I18n.t('vagrant_openstack.finding_networks'))

          private_networks = env[:openstack_client].neutron.get_private_networks(env)
          private_network_ids = private_networks.map { |n| n.id }

          networks = []
          config.networks.each do |network|
            if private_network_ids.include?(network)
              networks << network
              next
            end
            net_id = nil
            private_networks.each do |n| # Bad algorithm complexity, but here we don't care...
              next unless n.name.eql? network
              fail "Multiple networks with name '#{n.id}'" unless net_id.nil?
              net_id = n.id
            end
            fail "No matching network with name '#{network}'" if net_id.nil?
            networks << net_id
          end
          networks
        end

        def resolve_volume_boot(env)
          @logger.info 'Resolving image'
          config = env[:machine].provider_config
          return nil if config.volume_boot.nil?

          volume_list = env[:openstack_client].cinder.get_all_volumes(env)
          volume_ids = volume_list.map { |v| v.id }

          @logger.debug(volume_list)

          volume = resolve_volume(config.volume_boot, volume_list, volume_ids)
          device = volume[:device].nil? ? 'vda' : volume[:device]

          { id: volume[:id], device: device }
        end

        def resolve_volumes(env)
          @logger.info 'Resolving volume(s)'
          config = env[:machine].provider_config
          return [] if config.volumes.nil? || config.volumes.empty?
          env[:ui].info(I18n.t('vagrant_openstack.finding_volumes'))

          volume_list = env[:openstack_client].cinder.get_all_volumes(env)
          volume_ids = volume_list.map { |v| v.id }

          @logger.debug(volume_list)

          volumes = []
          config.volumes.each do |volume|
            volumes << resolve_volume(volume, volume_list, volume_ids)
          end
          @logger.debug("Resolved volumes : #{volumes.to_json}")
          volumes
        end

        def resolve_volume(volume, volume_list, volume_ids)
          return resolve_volume_from_string(volume, volume_list) if volume.is_a? String
          return resolve_volume_from_hash(volume, volume_list, volume_ids) if volume.is_a? Hash
          fail Errors::InvalidVolumeObject, volume: volume
        end

        def resolve_volume_from_string(volume, volume_list)
          found_volume = find_matching(volume_list, volume)
          fail Errors::UnresolvedVolume, volume: volume if found_volume.nil?
          { id: found_volume.id, device: nil }
        end

        def resolve_volume_from_hash(volume, volume_list, volume_ids)
          device = nil
          device = volume[:device] if volume.key?(:device)
          if volume.key?(:id)
            fail Errors::ConflictVolumeNameId, volume: volume if volume.key?(:name)
            volume_id = volume[:id]
            fail Errors::UnresolvedVolumeId, id: volume_id unless volume_ids.include? volume_id
          elsif volume.key?(:name)
            volume_list.each do |v|
              next unless v.name.eql? volume[:name]
              fail Errors::MultipleVolumeName, name: volume[:name] unless volume_id.nil?
              volume_id = v.id
            end
            fail Errors::UnresolvedVolumeName, name: volume[:name] unless volume_ids.include? volume_id
          else
            fail Errors::ConflictVolumeNameId, volume: volume
          end
          { id: volume_id, device: device }
        end

        def create_server(env, options)
          config = env[:machine].provider_config
          nova = env[:openstack_client].nova
          server_name = config.server_name || env[:machine].name

          env[:ui].info(I18n.t('vagrant_openstack.launching_server'))
          env[:ui].info(" -- Tenant          : #{config.tenant_name}")
          env[:ui].info(" -- Name            : #{server_name}")
          env[:ui].info(" -- Flavor          : #{options[:flavor].name}")
          env[:ui].info(" -- FlavorRef       : #{options[:flavor].id}")
          unless options[:image].nil?
            env[:ui].info(" -- Image           : #{options[:image].name}")
            env[:ui].info(" -- ImageRef        : #{options[:image].id}")
          end
          env[:ui].info(" -- Boot volume     : #{options[:volume_boot][:id]} (#{options[:volume_boot][:device]})") unless options[:volume_boot].nil?
          env[:ui].info(" -- KeyPair         : #{options[:keypair_name]}")

          unless options[:networks].empty?
            if options[:networks].size == 1
              env[:ui].info(" -- Network         : #{options[:networks][0]}")
            else
              env[:ui].info(" -- Networks        : #{options[:networks]}")
            end
          end

          unless options[:volumes].empty?
            options[:volumes].each do |volume|
              device = volume[:device]
              device = :auto if device.nil?
              env[:ui].info(" -- Volume attached : #{volume[:id]} => #{device}")
            end
          end

          log = "Lauching server '#{server_name}' in project '#{config.tenant_name}' "
          log << "with flavor '#{options[:flavor].name}' (#{options[:flavor].id}), "
          unless options[:image].nil?
            log << "image '#{options[:image].name}' (#{options[:image].id}) "
          end
          log << "and keypair '#{options[:keypair_name]}'"

          @logger.info(log)

          image_ref = options[:image].id unless options[:image].nil?

          create_opts = {
            name: server_name,
            image_ref: image_ref,
            volume_boot: options[:volume_boot],
            flavor_ref: options[:flavor].id,
            keypair: options[:keypair_name],
            availability_zone: options[:availability_zone],
            networks: options[:networks]
          }

          nova.create_server(env, create_opts)
        end

        def waiting_for_server_to_be_build(env, server_id)
          @logger.info 'Waiting for the server to be built...'
          env[:ui].info(I18n.t('vagrant_openstack.waiting_for_build'))
          nova = env[:openstack_client].nova
          timeout(200) do
            while nova.get_server_details(env, server_id)['status'] != 'ACTIVE'
              sleep 3
              @logger.debug('Waiting for server to be ACTIVE')
            end
          end
        end

        def attach_volumes(env, server_id, volumes)
          @logger.info("Attaching volumes #{volumes} to server #{server_id}")
          nova = env[:openstack_client].nova
          volumes.each do |volume|
            @logger.debug("Attaching volumes #{volume}")
            nova.attach_volume(env, server_id, volume[:id], volume[:device])
          end
        end

        def port_open?(env, ip, port, timeout)
          start_time = Time.now
          current_time = start_time
          nb_retry = 0
          while (current_time - start_time) <= timeout
            begin
              @logger.debug "Checking if SSH port is open... Attempt number #{nb_retry}"
              if nb_retry % 5 == 0
                @logger.info 'Waiting for SSH to become available...'
                env[:ui].info(I18n.t('vagrant_openstack.waiting_for_ssh'))
              end
              TCPSocket.new(ip, port)
              return true
            rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT
              @logger.debug 'SSH port is not open... new retry in in 1 second'
              nb_retry += 1
              sleep 1
            end
            current_time = Time.now
          end
          false
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
          @logger.error "Element '#{name}' not found in collection #{collection}"
          nil
        end
      end
    end
  end
end
