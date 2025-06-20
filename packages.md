Installation of kubernetes using containerd as container runtime.

0. Disable memory swap
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#swap-configuration

1. Install containerd (container runtime)
    https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
    
2. Set systemd as the cgroup driver for containerd
    a. Create configuration .toml
        https://github.com/containerd/containerd/blob/main/docs/getting-started.md
        sudo mkdir -p /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml
    b. Edit the configuration file:
        https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd
        see also https://kubernetes.io/docs/setup/production-environment/container-runtimes/#systemd-cgroup-driver
    c. Restart and enable containerd

3. Find out host's IP
    ip route show

4. Control plane node:
    a. Install kubeadm, kubelet, kubectl:
        https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
        https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management
    b. Enable network ports:
        https://kubernetes.io/docs/reference/networking/ports-and-protocols/#control-plane
    c. Create the cluster
        https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#initializing-your-control-plane-node
        It could be necessary to specify the container runtime socket: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-runtime
        It could be necessary to specify the pod network: --pod-network-cidr
    d. Follow the instruction about exporting the kubectl configuration inside the $HOME/.kube/config directory
    e. Installation of a Container Network Interface-compatible network plugin
        kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    f. ONLY NOW YOU CAN ADD OTHER NODES

5. Worker node:
    a. Follow steps 0-3
    b. Use the kube join command from the master

PROBLEM: