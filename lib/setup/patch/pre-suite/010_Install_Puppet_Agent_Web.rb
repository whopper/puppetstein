require_relative '../../../util/install_utils.rb'

test_name "Install puppet_agent from existing package"

step "Install puppet-agent..." do
  opts = {
    :puppet_collection    => 'PC1',
    :puppet_agent_sha     => ENV['PA_SHA'] == 'nightly' ? 'latest' : ENV['PA_SHA'],
    :puppet_agent_version => ENV['PA_SUITE'] || ENV['PA_SHA'],
    :dev_builds_url => ENV['PA_SHA'] == 'nightly' ? 'http://nightlies.puppetlabs.com' : 'http://builds.puppetlabs.lan'
  }
  puts opts.inspect
  agents.each do |agent|
    next if agent == master # Avoid SERVER-528
    install_puppet_agent_dev_repo_on(agent, opts)
  end
end
