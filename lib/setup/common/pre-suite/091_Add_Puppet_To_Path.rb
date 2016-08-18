test_name "Add puppet to the path"

[agent, master].each do |host|
  on(host, "ln -s /opt/puppetlabs/bin/facter /usr/bin && ln -s /opt/puppetlabs/bin/puppet /usr/bin") # TODO: this will only work in linux.. fix this
end
