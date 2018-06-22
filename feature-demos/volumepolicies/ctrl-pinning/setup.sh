#!/usr/bin/env sh

set -o errexit
set -o nounset

CURDIR=`pwd`

#Install latest minikube
ls /usr/local/bin/minikube || \
(curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
&& chmod +x minikube \
&& sudo mv minikube /usr/local/bin/)

#Install latest kubectl
ls /usr/local/bin/kubectl || \
(curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
&& chmod +x kubectl \
&& sudo mv kubectl /usr/local/bin/)

#Setup minikube
mkdir -p $HOME/.minikube
mkdir -p $HOME/.kube
touch $HOME/.kube/config

# Push these ENV k:v to $HOME/.profile to start/restart minikube.
grep "MINIKUBE_WANTUPDATENOTIFICATION=false" $HOME/.profile || \
  echo "MINIKUBE_WANTUPDATENOTIFICATION=false" >> $HOME/.profile

grep "MINIKUBE_WANTREPORTERRORPROMPT=false" $HOME/.profile || \
  echo "MINIKUBE_WANTREPORTERRORPROMPT=false" >> $HOME/.profile

grep "MINIKUBE_HOME=$HOME" $HOME/.profile || \
  echo "MINIKUBE_HOME=$HOME" >> $HOME/.profile

grep "CHANGE_MINIKUBE_NONE_USER=true" $HOME/.profile || \
  echo "CHANGE_MINIKUBE_NONE_USER=true" >> $HOME/.profile

grep "KUBECONFIG=$HOME/.kube/config" $HOME/.profile || \
  echo "KUBECONFIG=$HOME/.kube/config" >> $HOME/.profile

# Export above as well for `minikube start` to work 
# in the same session of `vagrant up`
export MINIKUBE_WANTUPDATENOTIFICATION=false
export MINIKUBE_WANTREPORTERRORPROMPT=false
export MINIKUBE_HOME=$HOME
export CHANGE_MINIKUBE_NONE_USER=true
export KUBECONFIG=$HOME/.kube/config

# Permissions
sudo chown -R $USER $HOME/.kube
sudo chgrp -R $USER $HOME/.kube

sudo chown -R $USER $HOME/.minikube
sudo chgrp -R $USER $HOME/.minikube

# Start minikube on this host itself with RBAC enabled
sudo -E minikube start --vm-driver=none --extra-config=apiserver.Authorization.Mode=RBAC

# Wait for Kubernetes to be up and ready.
JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get nodes -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done

echo ""
echo "================================================"
echo "Congrats!! minikube apiserver is running"
echo "================================================"
echo ""

# install socat
sudo apt-get install socat

# temp folder
mkdir -p .tmp

# Download and initialize helm
ls .tmp/get_helm.sh ||
(curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > .tmp/get_helm.sh \
&& chmod 700 .tmp/get_helm.sh)

bash .tmp/get_helm.sh
helm init

echo ""
echo "================================================"
echo "Congrats!! helm is installed"
echo "================================================"
echo ""

# Patch the tiller with rbac rules
kubectl -n kube-system create sa tiller \
 || echo "Will skip creation of serviceaccounts tiller"

kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller \
 || echo "Will skip creation of clusterrolebindings tiller "

kubectl -n kube-system patch deploy/tiller-deploy -p '{"spec": {"template": {"spec": {"serviceAccountName": "tiller"}}}}' \
 || echo "Will skip patching of deploy/tiller-deploy"

# Replace this with logic to wait till the pods are running
sleep 30
kubectl get pods --all-namespaces 
kubectl get sa

# Add openebs helm charts
helm repo add openebs-charts https://openebs.github.io/charts/
helm repo update
helm repo list

cd .tmp && helm fetch openebs-charts/openebs --untar

cd ${CURDIR}