require 'vagrant-openstack-provider'

Vagrant.configure("2") do |config|

  config.vm.box = "dummy-openstack"
  config.vm.box_url = "https://github.com/ggiamarchi/vagrant-openstack/raw/master/source/dummy.box"

  config.ssh.private_key_path = "/home/vagrant/.ssh/id_rsa"
  config.ssh.shell = "sh"

  config.vm.provider :openstack do |os|

    os.server_name = "vagrant-os-plugin-test"
    os.username = ENV['OS_USERNAME']
    os.floating_ip_pool = ENV['OS_FLOATING_IP_POOL']
    os.password = ENV['OS_PASSWORD']
    os.flavor = ENV['OS_FLAVOR']
    os.image = ENV['OS_IMAGE']
    os.openstack_auth_url = ENV['OS_AUTH_URL']
    os.tenant_name = ENV['OS_TENANT_NAME']
    os.ssh_username = "stack"
    os.public_key_path = "/home/vagrant/.ssh/id_rsa.pub"
  end
end
