require 'vagrant-openstack-provider/spec_helper'

describe VagrantPlugins::Openstack::CinderClient do

  let(:env) do
    Hash.new
  end

  let(:session) do
    VagrantPlugins::Openstack.session
  end

  before :each do
    session.token = '123456'
    session.project_id = 'a1b2c3'
    session.endpoints = { volume: 'http://cinder' }
    @cinder_client = VagrantPlugins::Openstack::CinderClient.instance
  end

  describe 'get_all_volumes' do
    context 'on api v1' do
      it 'returns volumes with details' do

        stub_request(:get, 'http://cinder/volumes/detail')
        .with(
            headers:
                {
                  'Accept' => 'application/json',
                  'X-Auth-Token' => '123456'
                })
        .to_return(
            status: 200,
            body: '
                {
                  "volumes": [
                    {
                      "id": "987",
                      "display_name": "vol-01",
                      "size": "2",
                      "status": "available",
                      "bootable": "true",
                      "instance_id": null,
                      "device": "/dev/vdb"
                    },
                    {
                      "id": "654",
                      "display_name": "vol-02",
                      "size": "4",
                      "status": "in-use",
                      "bootable": "false",
                      "instance_id": "inst-01",
                      "device": "/dev/vdc"
                    }
                  ]
                }
              ')

        volumes = @cinder_client.get_all_volumes(env)

        expect(volumes).to eq [Volume.new('987', 'vol-01', '2', 'available', 'true', nil, '/dev/vdb'),
                               Volume.new('654', 'vol-02', '4', 'in-use', 'false', 'inst-01', '/dev/vdc')]
      end
    end

    context 'on api v2' do
      it 'returns volumes with details' do

        stub_request(:get, 'http://cinder/volumes/detail')
        .with(
            headers:
                {
                  'Accept' => 'application/json',
                  'X-Auth-Token' => '123456'
                })
        .to_return(
            status: 200,
            body: '
                {
                  "volumes": [
                    {
                      "id": "987",
                      "name": "vol-01",
                      "size": "2",
                      "status": "available",
                      "bootable": "true",
                      "instance_id": null,
                      "device": "/dev/vdb"
                    },
                    {
                      "id": "654",
                      "name": "vol-02",
                      "size": "4",
                      "status": "in-use",
                      "bootable": "false",
                      "instance_id": "inst-01",
                      "device": "/dev/vdc"
                    }
                  ]
                }
              ')

        volumes = @cinder_client.get_all_volumes(env)

        expect(volumes).to eq [Volume.new('987', 'vol-01', '2', 'available', 'true', nil, '/dev/vdb'),
                               Volume.new('654', 'vol-02', '4', 'in-use', 'false', 'inst-01', '/dev/vdc')]
      end
    end
  end
end
