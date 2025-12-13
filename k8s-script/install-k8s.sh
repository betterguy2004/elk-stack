#!/bin/bash

## Change to a unique hostname
# sudo hostnamectl set-hostname master-node

# Disable swap 
sudo swapoff -a
# Comment swap entry in fstab file
sudo sed -i.bak '/\bswap\b/ s/^/#/' /etc/fstab


# ----------   Configure prerequisites  ( kubernetes.io/docs/setup/production-environment/container-runtimes/ )
sudo cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
 
lsmod | grep br_netfilter
lsmod | grep overlay

# Verify that is all outcomes are 1
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# ----------   Installation Of CRI -  CONTAINERD and Docker using Package ( https://docs.docker.com/engine/install/ubuntu/ )
#              using Binary - ( https://github.com/containerd/containerd/blob/main/docs/getting-started.md  )
sudo apt-get install -y conntrack || true

sudo apt-get remove docker docker-engine docker.io containerd runc -y
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates curl gnupg -y

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

if sudo docker ps | grep -q 'CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES'; then
            echo "Docker Installed successfully!"
    else echo  "Docker Installtion failed"
                    exit 1
fi

# ----------   Edit the Containerd Config file /etc/containerd/config.yaml
#              by default this config file conatains disable CRI so need to remove it and add required stuff suggested by K8s doc
if [ -f /etc/containerd/config.toml ]; then
        sudo chmod 770 -R /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml
        sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
fi
sudo systemctl restart containerd

# ----------  Installing kubeadm, kubelet and kubectl ---------
sudo apt-get update
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# install kubelet, kubeadm and kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "Installing of k8s component is Successfull"

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# ---------- Common configuration for both worker and master node is DONE
# ---------- Below one is For Master Node ( control-plane )
echo "\n At this stage your node is ready to work as worker node by adding join-token of cluster node"
read -p "To make it Control-plane ( master-node ) Enter 0 ,For Exit Enter 1  : " user_input
if [ "$user_input" -eq 0 ];then
        user_ip=$(hostname -I | awk '{print $1}')
        echo "Initializing Kubeadm , may take some time"
        # ------- good practice to pass cidr as it invert overlapping of k8s network with host network 
        if sudo kubeadm init --pod-network-cidr=10.32.0.0/16 --apiserver-advertise-address=$user_ip --ignore-preflight-errors=all | grep -q 'kubeadm join';then
                echo ""

        else 
                sudo kubeadm reset
                sudo systemctl daemon-reload
                sudo systemctl restart kubelet
                sudo systemctl status kubelet
                sudo kubeadm init --pod-network-cidr=10.32.0.0/16 --apiserver-advertise-address=$user_ip --ignore-preflight-errors=all -y
        fi

        sudo mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
 #--------
 # ---------- Installing Helm 3
echo "-------------Installing Helm 3-------------"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# Verify helm for both root and ubuntu user environments
helm version || true
su - ubuntu -c "helm version" || true


# -----------   Installing weave net (  the deault cidr=10.32.0.0/12 this can be overlap with host newtork so we are going to change it with /16 by downloading its yaml file and make changes in it)
        kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
        echo "\n Control-Plane is Ready \n"
        sudo kubectl get nodes
        echo "\n copy below one token to pass it to Worker Nodes\n"
        sudo kubeadm token create --print-join-command
        echo "\n----- complete -----\n"
        sudo systemctl daemon-reload
        sudo systemctl daemon-reload
        kubectl get nodes
else
        echo "\nTo make this NODE as control plane, Refer - kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/\n"
        echo "\n----- complete -----\n"
        sudo systemctl daemon-reload
fi
