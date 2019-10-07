#!/bin/bash

# Version/Date
CLIENTVM_VERSION=0.40
TERMINAL_TAG=2.1.0
BUILD_DATE=`date "+DATE: %Y-%m-%d%n"`

# Software Versions
# OpenShift Client is already in the base image
TKN_VERSION=0.2.2
KUBEFEDCTL_VERSION=0.1.0-rc6
S2I_LOCATION=https://github.com/openshift/source-to-image/releases/download/v1.1.14/source-to-image-v1.1.14-874754de-linux-amd64.tar.gz

# Remove any previous working container
buildah rm clientvm

# FROM Image
buildah from --name clientvm docker://quay.io/openshifthomeroom/workshop-homeroom:${TERMINAL_TAG}

#
# Set image annotations
#
buildah config --created-by "Wolfgang Kulhanek"          clientvm
buildah config --author     "wkulhane@redhat.com"        clientvm
buildah config --annotation "name=OpenShift 4 Client VM" clientvm
buildah config --annotation "version=$CLIENTVM_VERSION"  clientvm
buildah config --annotation "build-date=$BUILD_DATE"     clientvm

# Switch to root to install/configure everything
buildah config --user root clientvm

# Update packages, install additional packages
buildah run clientvm -- yum -y update
buildah run clientvm -- yum -y install \
  ansible \
  skopeo \
  wget \
  nano \
  vim

buildah run clientvm -- yum clean all

# Clean out tmp
buildah run clientvm -- rm -rf /tmp/src/.git*

# Set up Git Bash Prompt
buildah run clientvm -- ansible --connection=local all -i localhost, -m git -a"repo=https://github.com/magicmonty/bash-git-prompt.git dest=/opt/app-root/src/.bash-git-prompt clone=yes"
buildah copy --chown 1001:0 clientvm bashrc /tmp/src/.bashrc
buildah run clientvm -- bash -c "cat /tmp/src/.bashrc >> /opt/app-root/src/.bash_profile"
buildah run clientvm -- rm /tmp/src/.bashrc

# Set up S2I
buildah run clientvm -- ansible --connection=local all -i localhost, -m unarchive -a"src=${S2I_LOCATION} remote_src=yes dest=/opt/app-root/bin owner=root group=root mode=0755 extra_opts='--strip=1'"

# Set up newer version of kubefedctl (KubeFed V2 CLI)
buildah run clientvm -- ansible --connection=local all -i localhost, -m unarchive -a"src=https://github.com/kubernetes-sigs/kubefed/releases/download/v${KUBEFEDCTL_VERSION}/kubefedctl-${KUBEFEDCTL_VERSION}-linux-amd64.tgz remote_src=yes dest=/opt/app-root/bin owner=root group=root mode=0775"

# Set up newer version of tkn (OpenShift Pipelines CLI)
buildah run clientvm -- ansible --connection=local all -i localhost, -m unarchive -a"src=https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/tkn_${TKN_VERSION}_Linux_x86_64.tar.gz remote_src=yes dest=/opt/app-root/bin owner=1001 group=root mode=0775"

# Set up Python libraries and FTL
buildah run clientvm -- pip install openshift
buildah copy --chown 1001:0 clientvm requirements.yml /tmp/src/requirements.yml
buildah run clientvm -- ansible-galaxy install -r /tmp/src/requirements.yml
buildah run clientvm -- rm /tmp/src/requirements.yml
buildah copy --chown 1001:0 clientvm install_ftl.yml /tmp/src/install_ftl.yml
buildah run clientvm -- ansible-playbook --connection=local -i localhost, /tmp/src/install_ftl.yml

# Fix Permissions
buildah run clientvm -- chown -R 1001:0 /opt/app-root
buildah run clientvm -- chgrp -R 0 /opt/app-root
buildah run clientvm -- chmod -R g+w /opt/app-root
buildah run clientvm -- fix-permissions /opt/app-root

buildah run clientvm -- rm -rf /opt/app-root/src/.ansible

#
# Define container settings
#
buildah config --user 1001 clientvm

#
# Commit this container to an image name and tag
#
buildah commit clientvm quay.io/gpte-devops-automation/clientvm-terminal:${CLIENTVM_VERSION}

#
# Also tag latest
#
buildah tag quay.io/gpte-devops-automation/clientvm-terminal:${CLIENTVM_VERSION} quay.io/gpte-devops-automation/clientvm-terminal:latest

#
# Push to Quay
#
podman push quay.io/gpte-devops-automation/clientvm-terminal:${CLIENTVM_VERSION}
podman push quay.io/gpte-devops-automation/clientvm-terminal:latest
