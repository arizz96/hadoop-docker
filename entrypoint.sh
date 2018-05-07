#!/bin/bash

: ${HADOOP_ROLE:?"HADOOP_ROLE is required and should be one of: namenode, datanode, journalnode, resourcemanager, nodemanager, proxyserver or historyserver."}

# Set some sensible defaults
export CORE_CONF_fs_defaultFS=${CORE_CONF_fs_defaultFS:-hdfs://`hostname -f`:8020}

# Setup SSH keys
rm -r /root/.ssh
mkdir /root/.ssh
echo $HADOOP_SSH_KEY | sed -r 's/\\n/\n/g' >> /root/.ssh/id_rsa
echo $HADOOP_SSH_PUB_KEY | sed -r 's/\\n/\n/g' >> /root/.ssh/id_rsa.pub
chmod 600 -R /root/.ssh
chmod 700 /root/.ssh
cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
service sshd restart

function addProperty() {
  local path=$1
  local name=$2
  local value=$3

  if [ $# -ne 3 ]; then
      echo "There should be 3 arguments to addConfig: <file-to-modify.xml>, <property>, <value>"
      echo "Given: $@"
      exit 1
  fi

  xmlstarlet ed -L -s "/configuration" -t elem -n propertyTMP -v "" \
   -s "/configuration/propertyTMP" -t elem -n name -v $name \
   -s "/configuration/propertyTMP" -t elem -n value -v $value \
   -r "/configuration/propertyTMP" -v "property" \
   $path
}

function configure() {
    local path=$1
    local module=$2
    local envPrefix=$3

    local var
    local value

    echo "Configuring $module"
    for c in `printenv | perl -sne 'print "$1 " if m/^${envPrefix}_(.+?)=.*/' -- -envPrefix=$envPrefix`; do
        name=`echo ${c} | perl -pe 's/___/-/g; s/__/_/g; s/_/./g'`
        var="${envPrefix}_${c}"
        value=${!var}
        echo " - Setting $name=$value"
        addProperty /etc/hadoop/$module-site.xml $name "$value"
    done
}

function configureHostResolver() {
    sed -i "/hosts:/ s/.*/hosts: $*/" /etc/nsswitch.conf
}

configure $HADOOP_CONF_DIR/core-site.xml core CORE_CONF
configure $HADOOP_CONF_DIR/hdfs-site.xml hdfs HDFS_CONF
configure $HADOOP_CONF_DIR/yarn-site.xml yarn YARN_CONF
configure $HADOOP_CONF_DIR/httpfs-site.xml httpfs HTTPFS_CONF
configure $HADOOP_CONF_DIR/kms-site.xml kms KMS_CONF
configure $HADOOP_CONF_DIR/mapred-site.xml kms MAPRED_CONF

# start node
if [[ ${HADOOP_ROLE,,} = namenode ]]; then
    $HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR start namenode
elif [[ ${HADOOP_ROLE,,} = datanode ]]; then
    $HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR start datanode
elif [[ ${HADOOP_ROLE,,} = journalnode ]]; then
    $HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR start journalnode
elif [[ ${HADOOP_ROLE,,} = resourcemanager ]]; then
    $HADOOP_HOME/bin/yarn --config $HADOOP_CONF_DIR start resourcemanager
elif [[ ${HADOOP_ROLE,,} = nodemanager ]]; then
    $HADOOP_HOME/bin/yarn --config $HADOOP_CONF_DIR start nodemanager
elif [[ ${HADOOP_ROLE,,} = proxyserver ]]; then
    $HADOOP_HOME/bin/yarn --config $HADOOP_CONF_DIR start proxyserver
elif [[ ${HADOOP_ROLE,,} = historyserver ]]; then
    $HADOOP_HOME/bin/mapred --config $HADOOP_CONF_DIR start historyserver
else
    echo "HADOOP_ROLE's value must be one of: namenode, datanode, journalnode, resourcemanager, nodemanager, proxyserver or historyserver."
    exit 1
fi
