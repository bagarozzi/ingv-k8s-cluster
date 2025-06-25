# Join the entire cluster:
# On the master:
kubeadm token create --print-join-command
# Paste the result of the previous command on the workers. Mind that the token lasts 24 hours

# Deploy the NodePort Ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.3/deploy/static/provider/baremetal/deploy.yaml

# Wait that the controller gets registered

# Clone examples' repository
git clone https://github.com/bagarozzi/minikube-examples.git examples

# Deploy the example
kubectl apply -R -f examples/minikube/multiple-ingress/manifests

# Get the port where the NodePort Ingress is exposed:
kubectl get svc -n ingress-nginx

# Use the service from localhost
curl -i -H "Host: www.animals.com" http://127.0.0.1:<port>/cats
curl -i -H "Host: www.animals.com" http://127.0.0.1:<port>/dogs

# Connect to the Endian Firewall and forward traffic from a port of your choice towards a node in the cluster with the NodePort's port

# Test from the outside
curl -i -H "Host: www.animals.com" http://gw-ingv-labdidattica.pp.ingv.it:<externalPort>/dogs