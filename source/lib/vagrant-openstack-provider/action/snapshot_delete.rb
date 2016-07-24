require 'vagrant-openstack-provider/action/abstract_action'

module VagrantPlugins
  module Openstack
    module Action
      class SnapshotDelete < AbstractAction
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          nova = env[:openstack_client].nova

          env[:ui].info(I18n.t('vagrant.actions.vm.snapshot.deleting',
                               name: env[:snapshot_name]))

          nova.delete_snapshot(env, env[:machine].id, env[:snapshot_name])

          env[:ui].info(I18n.t('vagrant.actions.vm.snapshot.deleted',
                               name: env[:snapshot_name]))
          @app.call env
        end
      end
    end
  end
end
