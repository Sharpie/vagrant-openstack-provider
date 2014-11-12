require 'log4r'
require 'socket'
require 'timeout'
require 'sshkey'
require 'yaml'

require 'vagrant-openstack-provider/config_resolver'
require 'vagrant-openstack-provider/utils'
require 'vagrant-openstack-provider/action/abstract_action'
require 'vagrant/util/retryable'

module VagrantPlugins
  module Openstack
    module Action
      class CreateStack < AbstractAction
        def initialize(app, _env)
          @app = app
          @logger = Log4r::Logger.new('vagrant_openstack::action::create_stack')
        end

        def execute(env)
          @logger.info 'Start create stacks action'

          config = env[:machine].provider_config

          heat = env[:openstack_client].heat

          config.stacks.each do |stack|
            env[:ui].info(I18n.t('vagrant_openstack.create_stack'))
            env[:ui].info(" -- Stack Name : #{stack[:name]}")
            env[:ui].info(" -- Template   : #{stack[:template]}")

            create_opts = {
              name: stack[:name],
              template: YAML.load_file(stack[:template])
            }

            stack_id = heat.create_stack(env, create_opts)

            waiting_for_stack_to_be_created(env, stack[:name], stack_id)
          end

          @app.call(env)
        end

        private

        def waiting_for_stack_to_be_created(env, stack_name, stack_id, retry_interval = 3, timeout = 200)
          @logger.info "Waiting for the stack with id #{stack_id} to be built..."
          env[:ui].info(I18n.t('vagrant_openstack.waiting_for_stack'))
          timeout(timeout, Errors::Timeout) do
            stack_status = 'CREATE_IN_PROGRESS'
            until stack_status == 'CREATE_COMPLETE'
              @logger.debug('Waiting for stack to be CREATED')
              stack_status = env[:openstack_client].heat.get_stack_details(env, stack_name, stack_id)['stack_status']
              fail Errors::StackStatusError, stack: stack_id if stack_status == 'CREATE_FAILED'
              sleep retry_interval
            end
          end
        end
      end
    end
  end
end
