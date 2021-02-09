#!/bin/bash
serviceNames=( $(terraform output -json endpoints | jq -r '.[] | .name') )
instanceIps=( $(terraform output -json instance_ips | jq -r '.[]') )
instanceNames=( $(terraform output -json instance_names | jq -r '.[]') )

for index in "${!instanceIps[@]}"; do
  instanceIp=${instanceIps[index]}
  instanceName=${instanceNames[index]}
  echo "   >>> $instanceName"
  for service in "${serviceNames[@]}"; do
    host_to_resolve=$(terraform output -json endpoints | jq -r '.[] | select(.name=="'${service}'") | .hostname')
    echo "     >>> $service ($host_to_resolve)"
    ssh -q -t -i generated_key_rsa -o "StrictHostKeyChecking=no" root@$instanceIp << EOF
    yum install -y bind-utils >/dev/null
    dig +noall +answer $host_to_resolve | sed 's/^/       /'
    # nslookup $host_to_resolve
EOF
  done
done