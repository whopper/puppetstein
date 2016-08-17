require_relative '../../../util/install_utils.rb'

extend Puppetstein::InstallUtils

test_name "Install puppetserver from builds.puppetlabs.lan or nightlies"

step "Install puppetserver..." do
  MASTER_PACKAGES = {
    :redhat => [
      'puppetserver',
    ],
    :debian => [
      'puppetserver',
    ],
  }

  repo_configs_dir = 'repo-configs'
  install_repos_on(master, 'puppetserver', 'nightly', repo_configs_dir)
  install_repos_on(master, 'puppet-agent', ENV['PA_SHA'], repo_configs_dir)
  install_packages_on(master, MASTER_PACKAGES)
end

