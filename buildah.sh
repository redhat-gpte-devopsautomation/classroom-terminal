#!/bin/bash

# Remove any previous working container
buildah rm clientvm

# FROM Image
buildah from --name clientvm docker://quay.io/openshiftlabs/workshop-terminal:2.8.0

# Version/Date
CLIENTVM_VERSION=0.3
BUILD_DATE=`date "+DATE: %Y-%m-%d%n"`

# Software Versions
# OpenShift Client is already in the base image
ODO_VERSION=v1.0.0-beta2
S2I_LOCATION=https://github.com/openshift/source-to-image/releases/download/v1.1.14/source-to-image-v1.1.14-874754de-linux-amd64.tar.gz

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
  buildah \
  podman \
  wget \
  nano \
  vim

buildah run clientvm -- yum clean all

# Clean out tmp
buildah run clientvm -- rm -rf /tmp/src/.git*

# Set up Git Bash Prompt
buildah run clientvm -- ansible --connection=local all -i localhost, -m git -a"repo=https://github.com/magicmonty/bash-git-prompt.git dest=/tmp/src/.bash-git-prompt clone=yes"
buildah copy --chown 1001:0 clientvm bashrc /tmp/src/.bashrc

# Set up newer version of odo
buildah run clientvm -- ansible --connection=local all -i localhost, -m get_url -a"url=https://github.com/openshift/odo/releases/download/${ODO_VERSION}/odo-linux-amd64 dest=/tmp/src/odo owner=1001 group=root mode=0775 force=yes"

# Set up S2I
buildah run clientvm -- ansible --connection=local all -i localhost, -m unarchive -a"src=${S2I_LOCATION} remote_src=yes dest=/tmp/src owner=root group=root mode=0755 extra_opts='--strip=1'"

# Install FTL
# TBD


# Fix Permissions
buildah run clientvm -- chown -R 1001:0 /tmp/src
buildah run clientvm -- chgrp -R 0 /tmp/src
buildah run clientvm -- chmod -R g+w /tmp/src
buildah run clientvm -- fix-permissions /opt/app-root

buildah run clientvm -- rm -rf /opt/app-root/src/.ansible

#
# Define container settings
#
buildah config --user 1001 clientvm

#
# Run S2I Assemble
# 

buildah run clientvm -- /usr/libexec/s2i/assemble

#
# Commit this container to an image name and tag
#
buildah commit clientvm quay.io/gpte-devops-automation/clientvm-terminal:${CLIENTVM_VERSION}

#
# Push to Quay
#
podman push quay.io/gpte-devops-automation/clientvm-terminal:${CLIENTVM_VERSION}