#!/bin/bash

helpFunction()
{
   echo ""
   echo "Usage: $0 -i private_key"
   echo -e "\t-i Localizacao da chave privada"
   exit 1
}

while getopts "i:" opt
do
   case "$opt" in
      i ) PVT_KEY_PATH="$OPTARG" ;;
      ? ) helpFunction ;;
   esac
done

if [ -z "$PVT_KEY_PATH" ]
then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

echo "$PVT_KEY_PATH"

cd ~/aws-jenkins-tf-ans-k8s/terraform
terraform init
terraform fmt
terraform apply -auto-approve

echo  "Aguardando a criação das maquinas ..."

ID_M1=$(terraform output k8s_master | grep 'k8s-master 1 ' | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_M1_DNS=$(terraform output k8s_master | grep 'k8s-master 1 ' | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')

ID_M2=$(terraform output k8s_master | grep 'k8s-master 2 ' | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_M2_DNS=$(terraform output k8s_master | grep 'k8s-master 2 ' | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')

ID_M3=$(terraform output k8s_master | grep 'k8s-master 3 ' | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_M3_DNS=$(terraform output k8s_master | grep 'k8s-master 3 ' | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')


ID_HAPROXY=$(terraform output haproxy | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_HAPROXY_DNS=$(terraform output haproxy | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')


ID_W1=$(terraform output k8s_worker | grep 'k8s-worker 1 ' | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_W1_DNS=$(terraform output k8s_worker | grep 'k8s-worker 1 ' | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')

ID_W2=$(terraform output k8s_worker | grep 'k8s-worker 2 ' | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_W2_DNS=$(terraform output k8s_worker | grep 'k8s-worker 2 ' | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')

ID_W3=$(terraform output k8s_worker | grep 'k8s-worker 3 ' | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_W3_DNS=$(terraform output k8s_worker | grep 'k8s-worker 3 ' | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')

ID_MYSQL=$(terraform output mysql | grep -oP 'private=(.*?)\"' | sed 's/private=//' | sed 's/\"//' | sed 's/ //')

ID_DEV=$(terraform output k8s_dev | grep -oP 'private=(.*?)\s' | sed 's/private=//' | sed 's/ //')
ID_DEV_DNS=$(terraform output k8s_dev | grep -oP 'public=(.*)\"' | sed 's/public=//' | sed 's/\"//' | sed 's/ //')

cat <<EOF > ../ansible/hosts
[ec2-k8s-proxy]
$ID_HAPROXY_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH

[ec2-k8s-m1]
$ID_M1_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH
[ec2-k8s-m2]
$ID_M2_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH
[ec2-k8s-m3]
$ID_M3_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH

[ec2-k8s-w1]
$ID_W1_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH
[ec2-k8s-w2]
$ID_W2_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH
[ec2-k8s-w3]
$ID_W3_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH

[ec2-mysql]
$ID_MYSQL ansible_ssh_private_key_file=$PVT_KEY_PATH
[ec2-mysql:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -q k8sdev"'

[ec2-jenkins]
$ID_DEV_DNS ansible_ssh_private_key_file=$PVT_KEY_PATH
EOF

echo "
global
        log /dev/log    local0
        log /dev/log    local1 notice
        chroot /var/lib/haproxy
        stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
        stats timeout 30s
        user haproxy
        group haproxy
        daemon

        # Default SSL material locations
        ca-base /etc/ssl/certs
        crt-base /etc/ssl/private

        # See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
        errorfile 400 /etc/haproxy/errors/400.http
        errorfile 403 /etc/haproxy/errors/403.http
        errorfile 408 /etc/haproxy/errors/408.http
        errorfile 500 /etc/haproxy/errors/500.http
        errorfile 502 /etc/haproxy/errors/502.http
        errorfile 503 /etc/haproxy/errors/503.http
        errorfile 504 /etc/haproxy/errors/504.http

frontend kubernetes
        mode tcp
        bind $ID_HAPROXY:6443 # IP ec2 Haproxy 
        option tcplog
        default_backend k8s-masters

backend k8s-masters
        mode tcp
        balance roundrobin # maq1, maq2, maq3  # (check) verifica 3 vezes negativo (rise) verifica 2 vezes positivo
        server k8s-master-0 $ID_M1:6443 check fall 3 rise 2 # IP ec2 Cluster Master k8s - 1 
        server k8s-master-1 $ID_M2:6443 check fall 3 rise 2 # IP ec2 Cluster Master k8s - 2 
        server k8s-master-2 $ID_M3:6443 check fall 3 rise 2 # IP ec2 Cluster Master k8s - 3 
        
" > ../ansible/haproxy/haproxy.cfg


echo "
127.0.0.1 localhost
$ID_HAPROXY k8s-haproxy # IP privado proxy

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
" > ../ansible/hosts_dns/hosts

echo $PWD

cd ../ansible
echo $PWD

ansible-playbook -i hosts staging.yml

ANSIBLE_OUT=$(ansible-playbook -i hosts k8s_master_init.yml)

K8S_JOIN_MASTER=$(echo $ANSIBLE_OUT | grep -oP "(kubeadm join.*?certificate-key.*?)'" | sed 's/\\//g' | sed "s/'t//g" | sed "s/'//g" | sed "s/,//g")
K8S_JOIN_WORKER=$(echo $ANSIBLE_OUT | grep -oP "(kubeadm join.*?discovery-token-ca-cert-hash.*?)'" | head -n 1 | sed 's/\\//g' | sed "s/'t//g" | sed "s/'//g" | sed "s/'//g" | sed "s/,//g")

echo $K8S_JOIN_MASTER
echo $K8S_JOIN_WORKER

cat <<EOF > provisionar-k8s-master-auto-shell.yml
- hosts:
  - ec2-k8s-m2
  - ec2-k8s-m3
  become: yes
  tasks:
    - name: "Reset cluster"
      shell: "kubeadm reset -f"
    - name: "Fazendo join kubernetes master"
      shell: $K8S_JOIN_MASTER
    - name: "Colocando no path da maquina o conf do kubernetes"
      shell: mkdir -p $HOME/.kube && sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config && export KUBECONFIG=/etc/kubernetes/admin.conf
#---
- hosts:
  - ec2-k8s-w1
  - ec2-k8s-w2
  - ec2-k8s-w3
  become: yes
  tasks:
    - name: "Reset cluster"
      shell: "kubeadm reset -f"
    - name: "Fazendo join kubernetes worker"
      shell: $K8S_JOIN_WORKER
#---
- hosts:
  - ec2-k8s-m1
  become: yes
  tasks:
    - name: "Configura weavenet para reconhecer os nós master e workers"
      shell: kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=\$(kubectl version | base64 | tr -d '\n')"
EOF

ansible-playbook -i hosts provisionar-k8s-master-auto-shell.yml

ansible-playbook -i hosts deploy_mysql.yml

ansible-playbook -i hosts deploy_app.yml

ansible-playbook -i hosts deploy_jenkins.yml

echo $"URL Jenkins: http://$ID_DEV_DNS:8080"