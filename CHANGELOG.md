# 0.1.6 (January 8, 2014)

BUG FIXES:

  - Downgraded fog to 1.18 in order to be more compatible with vagrant-aws
  
# 0.1.5 (January 8, 2014)

IMPROVEMENTS:

  - Fix Vagrant 1.4 compatibility and support multiple SSH keys [GH-58]
  - Add uploaded keypair support [GH-53]
  - Add ssh_run support, for vagrant ssh -c [GH-57]
  - Requires fog 1.19 [GH-65]

BUG FIXES:

  - Remove networks warning as vagrant-openstack now supports networks [GH-64]

# 0.1.4 (October 15, 2013)

IMPROVEMENTS:

  - Adds endpoint validation (openstack_compute_url, openstack_auth_url) [GH-39]
  
FEATURES:
  - Adds ability to configure networks [GH-37]

# 0.1.3 (September 6, 2013)

IMPROVEMENTS:

  - Adds ability to specify authentication endpoint; Support for UK Cloud! [GH-32]
  - Adds ability to specify disk configuration (disk_conf) [GH-33]

# 0.1.2 (August 22, 2013)

FEATURES:

- Add provision support [GH-16]
  
IMPROVEMENTS:
  
  - Adds option to allow provisioning after RackConnect scripts complete. [GH-18]
  - Remove Fog deprecation warnings [GH-11]
  - Bypass rsync's StrictHostKeyCheck [GH-5]
  - Make chown'ing of synced folder perms recursive (for ssh user) [GH-24]
  - Use /cygdrive when rsyncing on Windows [GH-17]
  
  
# 0.1.1 (March 18, 2013)

* Up fog dependency for Vagrant 1.1.1

# 0.1.0 (March 14, 2013)

* Initial release.
