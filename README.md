## Puppetstein

A standalone tool to automate the building and composition of various versions of puppet-agent components for development and testing.

This is super a work in progress, especially this README.

### Usage

Options:

  --puppet_agent, specify base puppet-agent version (optional)
  -p, --platform, which platform to install on (required)
  -i, --install,  install the composed puppet-agent package on a VM (optional)

  --hack, hack mode: patch installed PA with puppet/hiera (optional)
  -b, --build, build mode: force puppetstein to build a new PA (optional)

  --puppet, fork and SHA of puppet to use separated with a : (optional)
  --facter, fork and SHA of facter to use separated with a : (optional)
  --hiera,  fork and SHA of hiera to use separated with a : (optional)

  :pre_provisioned_host, use a pre-provisioned host. Useful for re-running tests (optional)

  -t, --tests, tests to run against a puppet-agent installation (optional)
  -d, --debug, debug mode, (optional)

### Examples

Install a specific SHA of puppet-agent on a new Debian 8 VM

`puppetstein --puppet_agent=puppetlabs:0c9be720aedfdc1185ad0961c7485b650abb2bd4 --install --platform=centos-7-x86_64`


Install a specific SHA of puppet-agent on a new Centos 7 VM and run arbitrary facter and puppet tests

`puppetstein --puppet_agent=puppetlabs:1.5.3 --install --tests=facter:tests/facts/el.rb,puppet:tests/resource/service/init_on_systemd.rb --platform=centos-7-x86_64`

Install a modified puppet-agent on a new RedHat 7 VM using a specific fork and SHA of puppet and run a puppet test on it

`puppetstein --puppet_agent=puppetlabs:1.5.3 --puppet=whopper:amazing_test_branch --hack --install --tests=puppet:tests/resource/package/yum.rb --platform=redhat-7-x86_64`

Build a new puppet-agent package using a modified facter, install it on a new Debian 8 VM and run an arbitrary Facter test on it

`puppetstein --puppet_agent=puppetlabs:master --facter=ahenroid:fact-1413/master/extfacts_override_fix --build --install --tests=facter:tests/facts/debian.rb --platform=debian-8-x86_64`

Rerun tests on a pre-provisioned host

`puppetstein --pre_provisioned_host=asdbiauwbdua --tests=facter:tests/facts/debian.rb --platform=debian-8-x86_64`
