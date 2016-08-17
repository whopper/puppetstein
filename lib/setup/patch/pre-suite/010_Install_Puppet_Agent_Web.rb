require_relative '../../../util/install_utils.rb'

test_name "Install puppet_agent from builds.puppetlabs.lan"

step "Install puppet-agent..." do
  opts = {
    :puppet_collection    => 'PC1',
    :puppet_agent_sha     => ENV['PA_SHA'],
    :puppet_agent_version => ENV['PA_SUITE'] || ENV['PA_SHA']
  }
  puts opts.inspect
  agents.each do |agent|
    next if agent == master # Avoid SERVER-528
    install_puppet_agent_dev_repo_on(agent, opts)
  end
end
