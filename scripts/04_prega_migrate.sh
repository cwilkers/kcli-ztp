#!/usr/bin/env bash

cd /root
export PATH=/root/bin:$PATH
export OCP_RELEASE="$(openshift-install version | head -1 | cut -d' ' -f2 | cut -d'.' -f 1,2)"
{% if disconnected_prega_operators_version != None %}
export OCP_RELEASE="{{ disconnected_prega_operators_version }}"
{% endif %}
export OCP_PULLSECRET_AUTHFILE='/root/openshift_pull.json'
{% if disconnected_url != None %}
{% set registry_port = disconnected_url.split(':')[-1] %}
{% set registry_name = disconnected_url|replace(":" + registry_port, '') %}
REGISTRY_NAME={{ registry_name }}
REGISTRY_PORT={{ registry_port }}
{% else %}
PRIMARY_NIC=$(ls -1 /sys/class/net | grep 'eth\|en' | head -1)
IP=$(ip -o addr show $PRIMARY_NIC | head -1 | awk '{print $4}' | cut -d'/' -f1)
REGISTRY_NAME=$(echo $IP | sed 's/\./-/g' | sed 's/:/-/g').sslip.io
REGISTRY_PORT={{ 8443 if disconnected_quay else 5000 }}
{% endif %}
export LOCAL_REGISTRY=$REGISTRY_NAME:$REGISTRY_PORT
REGISTRY_USER={{ "init" if disconnected_quay else disconnected_user }}
REGISTRY_PASSWORD={{ "super" + disconnected_password if disconnected_quay and disconnected_password|length < 8 else disconnected_password }}
podman login -u $REGISTRY_USER -p $REGISTRY_PASSWORD $LOCAL_REGISTRY

# Make manifests from the prega stuff that we synced in 04_mirror_olm.sh
PREGA_DIR=/root/prega-workspace
rm -rf $PREGA_DIR/{manifests,idms}
mkdir -p $PREGA_DIR/{manifests,idms}

oc adm catalog mirror quay.io/prega/prega-operator-index:${OCP_RELEASE} ${REGISTRY_NAME}:${REGISTRY_PORT} \
	 --index-filter-by-os="linux/amd6" \
  --insecure --max-components=4 --continue-on-error=False \
  --registry-config ${OCP_PULLSECRET_AUTHFILE} \
  --to-manifests=${PREGA_DIR}/manifests --manifests-only=true

oc adm migrate icsp ${PREGA_DIR}/manifests/imageContentSourcePolicy.yaml --dest-dir ${PREGA_DIR}/idms
IDMS=$(ls -t ${PREGA_DIR}/idms/imagedigest*.yaml | head -n 1)
sed -i -e \
  '/source:/!b;/bundle/b;/cincinnati-operator-metadata-container/b;/custom-metrics-autoscaler-operator-metadata/b;s,quay.io/prega/test/,registry.redhat.io/,' \
  $IDMS

oc apply -f $IDMS 2>/dev/null || cp $IDMS /root/manifests/imageContentSourcePolicy.yaml
