#!/bin/bash
serviceNames=( $(terraform output -json endpoints | jq -r '.[] | .name') )
instanceIps=( $(terraform output -json instance_ips | jq -r '.[]') )
instanceNames=( $(terraform output -json instance_names | jq -r '.[]') )

echo "| Source | Destination | Resolved IPs |"
echo "| ------ | ----------- | ------------ |"
for index in "${!instanceIps[@]}"; do
  instanceIp=${instanceIps[index]}
  instanceName=${instanceNames[index]}
  for service in "${serviceNames[@]}"; do
    host_to_resolve=$(terraform output -json endpoints | jq -r '.[] | select(.name=="'${service}'") | .hostname')
    echo -n "| $instanceName | $service ($host_to_resolve) | "
    ips=$(ssh -q -t -i generated_key_rsa -o "StrictHostKeyChecking=no" root@$instanceIp << EOF
    yum install -y bind-utils >/dev/null
    dig +short $host_to_resolve | grep '^[.0-9]*$' | paste -s -d, -
    # nslookup $host_to_resolve
EOF
)
  echo " $ips |"
  done
done