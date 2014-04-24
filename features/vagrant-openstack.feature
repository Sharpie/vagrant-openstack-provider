@announce
@vagrant-openstack
Feature: vagrant-openstack fog tests
  As a Fog developer
  I want to smoke (or "fog") test vagrant-openstack.
  So I am confident my upstream changes did not create downstream problems.

  Background:
    Given I have Openstack credentials available
    And I have a "fog_mock.rb" file

  Scenario: Create a single server (region)
    Given a file named "Vagrantfile" with:
    """
    # Testing options
    require File.expand_path '../fog_mock', __FILE__

    Vagrant.configure("2") do |config|
      # dev/test method of loading plugin, normally would be 'vagrant plugin install vagrant-openstack'
      Vagrant.require_plugin "vagrant-openstack"

      config.vm.box = "dummy"
      config.ssh.username = "vagrant" if Fog.mock?
      config.ssh.private_key_path = "~/.ssh/id_rsa" unless Fog.mock?

      config.vm.provider :openstack do |rs|
        rs.server_name = 'vagrant-single-server'
        rs.username = ENV['RAX_USERNAME']
        rs.api_key  = ENV['RAX_API_KEY']
        rs.openstack_region = ENV['RAX_REGION'].downcase.to_sym
        rs.flavor   = /1 GB Performance/
        rs.image    = /Ubuntu/
        rs.public_key_path = "~/.ssh/id_rsa.pub" unless Fog.mock?
      end
    end
    """
    When I successfully run `bundle exec vagrant up --provider openstack`
    # I want to capture the ID like I do in tests for other tools, but Vagrant doesn't print it!
    # And I get the server from "Instance ID:"
    Then the server "vagrant-single-server" should be active

Scenario: Create a single server (openstack_compute_url)
    Given a file named "Vagrantfile" with:
    """
    # Testing options
    require File.expand_path '../fog_mock', __FILE__

    Vagrant.configure("2") do |config|
      # dev/test method of loading plugin, normally would be 'vagrant plugin install vagrant-openstack'
      Vagrant.require_plugin "vagrant-openstack"

      config.vm.box = "dummy"
      config.ssh.username = "vagrant" if Fog.mock?
      config.ssh.private_key_path = "~/.ssh/id_rsa" unless Fog.mock?

      config.vm.provider :openstack do |rs|
        rs.server_name = 'vagrant-single-server'
        rs.username = ENV['RAX_USERNAME']
        rs.api_key  = ENV['RAX_API_KEY']
        rs.openstack_compute_url = "https://#{ENV['RAX_REGION'].downcase}.servers.api.openstackcloud.com/v2"
        rs.flavor   = /1 GB Performance/
        rs.image    = /Ubuntu/
        rs.public_key_path = "~/.ssh/id_rsa.pub" unless Fog.mock?
      end
    end
    """
    When I successfully run `bundle exec vagrant up --provider openstack`
    # I want to capture the ID like I do in tests for other tools, but Vagrant doesn't print it!
    # And I get the server from "Instance ID:"
    Then the server "vagrant-single-server" should be active
