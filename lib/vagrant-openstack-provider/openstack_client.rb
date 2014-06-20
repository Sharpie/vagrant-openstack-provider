require "log4r"
require "restclient"
require "json"

module VagrantPlugins
  module Openstack
    class OpenstackClient
      def initialize
        @logger = Log4r::Logger.new("vagrant_openstack::openstack_client")
        @token = nil
        @project_id = nil
        @endpoints = {}
      end

      def authenticate(env)
        @logger.debug("Authenticating on Keystone")
        config = env[:machine].provider_config
        env[:ui].info(I18n.t('vagrant_openstack.client.authentication', project: config.tenant_name, user: config.username))

        authentication = RestClient.post(
          config.openstack_auth_url,
          {
            auth:
            {
              tenantName: config.tenant_name,
              passwordCredentials:
              {
                username: config.username,
                password: config.password
              }
            }
          }.to_json,
          content_type: :json,
          accept: :json)

        access = JSON.parse(authentication)['access']

        read_endpoint_catalog(env, access['serviceCatalog'])
        override_endpoint_catalog_with_user_config(env)
        print_endpoint_catalog(env)

        response_token = access['token']
        @token = response_token['id']
        @project_id = response_token['tenant']['id']
      end

      def get_all_flavors(_env)
        flavors_json = RestClient.get("#{@endpoints['compute']}/flavors", "X-Auth-Token" => @token, :accept => :json)
        JSON.parse(flavors_json)['flavors'].map { |fl| Item.new(fl['id'], fl['name']) }
      end

      def get_all_images(_env)
        images_json = RestClient.get("#{@endpoints['compute']}/images", "X-Auth-Token" => @token, :accept => :json)
        JSON.parse(images_json)['images'].map { |im| Item.new(im['id'], im['name']) }
      end

      def create_server(_env, name, image_ref, flavor_ref, keypair)
        server = RestClient.post(
          "#{@endpoints['compute']}/servers",
          {
            server:
            {
              name: name,
              imageRef: image_ref,
              flavorRef: flavor_ref,
              key_name: keypair
            }
          }.to_json,
          "X-Auth-Token" => @token,
          :accept => :json,
          :content_type => :json)
        JSON.parse(server)['server']['id']
      end

      def delete_server(_env, server_id)
        RestClient.delete(
          "#{@endpoints['compute']}/servers/#{server_id}",
          "X-Auth-Token" => @token,
          :accept => :json)
      end

      def suspend_server(_env, server_id)
        RestClient.post(
          "#{@endpoints['compute']}/servers/#{server_id}/action", '{ "suspend": null }',
          "X-Auth-Token" => @token,
          :accept => :json,
          :content_type => :json)
      end

      def resume_server(_env, server_id)
        # TODO(julienvey) check status before (if pause->unpause, if suspend->resume...)
        RestClient.post(
          "#{@endpoints['compute']}/servers/#{server_id}/action", '{ "resume": null }',
          "X-Auth-Token" => @token,
          :accept => :json,
          :content_type => :json)
      end

      def stop_server(_env, server_id)
        RestClient.post(
          "#{@endpoints['compute']}/servers/#{server_id}/action", '{ "os-stop": null }',
          "X-Auth-Token" => @token,
          :accept => :json,
          :content_type => :json)
      end

      def start_server(_env, server_id)
        RestClient.post(
          "#{@endpoints['compute']}/servers/#{server_id}/action", '{ "os-start": null }',
          "X-Auth-Token" => @token,
          :accept => :json,
          :content_type => :json)
      end

      def get_server_details(_env, server_id)
        server_details = RestClient.get(
          "#{@endpoints['compute']}/servers/#{server_id}",
          "X-Auth-Token" => @token,
          :accept => :json)
        JSON.parse(server_details)['server']
      end

      def add_floating_ip(env, server_id, floating_ip)
        check_floating_ip(env, floating_ip)
        RestClient.post(
          "#{@endpoints['compute']}/servers/#{server_id}/action",
          {
            addFloatingIp:
            {
              address: floating_ip
            }
          }.to_json,
          "X-Auth-Token" => @token,
          :accept => :json,
          :content_type => :json)
      end

      private

      def read_endpoint_catalog(env, catalog)
        env[:ui].info(I18n.t('vagrant_openstack.client.looking_for_available_endpoints'))

        catalog.each { |service|
          se = service['endpoints']
          if se.size > 1
            env[:ui].warn I18n.t('vagrant_openstack.client.multiple_endpoint', size: se.size, type: service['type'])
            env[:ui].warn "  => #{service['endpoints'][0]['publicURL']}"
          end
          url = se[0]['publicURL'].strip
          @endpoints[service['type']] = url if !url.empty?
        }
      end

      def override_endpoint_catalog_with_user_config(env)
        config = env[:machine].provider_config
        @endpoints['compute'] = config.openstack_compute_url if !config.openstack_compute_url.nil?
      end

      def print_endpoint_catalog(env)
        @endpoints.each do |key, value|
          env[:ui].info(" -- #{key.ljust 15}: #{value}")
        end
      end

      def check_floating_ip(_env, floating_ip)
        ip_details = RestClient.get(
          "#{@endpoints['compute']}/os-floating-ips",
          "X-Auth-Token" => @token,
          :accept => :json)

        JSON.parse(ip_details)['floating_ips'].each { |ip|
          if ip['ip'] == floating_ip
            if !ip['instance_id'].nil?
              raise "Floating IP #{floating_ip} already assigned to another server"
            else
              return
            end
          end
        }
        raise "Floating IP #{floating_ip} not available for this tenant"
      end
    end

    class Item
      attr_accessor :id, :name
      def initialize(id, name)
        @id = id
        @name = name
      end
    end
  end
end
