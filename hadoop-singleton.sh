#!/bin/bash
#hadoop单机安装,2.6.5;2.9.1通过验证

#环境设置:u 不存在的变量报错;e 发生错误退出;pipefail 管道有错退出
set -euo pipefail

#########要更改变的变量#######
###软件包下载地址
DWON_URL=""

###SSH端口
SSH_PORT="22"

###jdk md5验证
JDK_MD5="781e3779f0c134fb548bde8b8e715e90"

###HOSTNAME
HOSTNAME=`hostname`

###版本
HADOOP_VERSION="2.9.1"

###安装用户
HADOOP_USER="hdfs"
HADOOP_USER_PASS=""

###HADOOP目录
HA_INSTALL_DIR="/usr/local"
HA_ROOT_DIR="/cache1,/cache2"
HA_TMP_DIR="/cache1/tmp"
NAMENODE_NAME_DIR="/cache1/dfs/nn,/cache2/dfs/nn"
DATANODE_DATA_DIR="/cache1/dfs/dn,/cache2/dfs/dn"
YARN_NODEMG_DIR="/cache1/yarn/nm,/cache2/yarn/nm"
YARN_NODEMG_LOG="/cache1/yarn/container-logs,/cache2/yarn/container-logs"

##############################
set +e
grep ${HADOOP_USER} /etc/passwd && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    echo "#########用户创建#########"
    groupadd ${HADOOP_USER}
    useradd -g ${HADOOP_USER} ${HADOOP_USER}
    echo ${HADOOP_USER_PASS}| passwd ${HADOOP_USER} --stdin  &>/dev/null
fi

mkdir -p ${HA_TMP_DIR}
STR1="mkdir -p {${NAMENODE_NAME_DIR}}"
STR2="mkdir -p {${DATANODE_DATA_DIR}}"
STR3="mkdir -p {${YARN_NODEMG_DIR}}"
STR4="mkdir -p {${YARN_NODEMG_LOG}}"
echo $STR1
echo $STR2
echo $STR3
echo $STR4
eval $STR1
eval $STR2
eval $STR3
eval $STR4
STR5="chown -R ${HADOOP_USER}:${HADOOP_USER} {${HA_ROOT_DIR}}"
eval $STR5
set -e

if [ ! -f "/etc/profile.d/path.sh" ]
then
cat > /etc/profile.d/path.sh <<EOF
export PATH=\$PATH:/sbin:/usr/sbin:/usr/local/sbin
export TMOUT=1800
if [[ -n "\$SSH_CLIENT"  ]] || [[ -n "\$SSH_CONNECTION" ]];then
        export TMOUT=3600
fi
EOF
fi

echo "#########root ssh 设置#########"
rm -rf /root/.ssh/
ssh-keygen -t rsa -N '' -f '/root/.ssh/id_rsa'
cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

echo "#####${HADOOP_USER} ssh 设置######"
rm -rf /home/${HADOOP_USER}/.ssh/
mkdir /home/${HADOOP_USER}/.ssh
chmod 700 /home/${HADOOP_USER}/.ssh
ssh-keygen -t rsa -N '' -f "/home/${HADOOP_USER}/.ssh/id_rsa" -C "${HADOOP_USER}@$HOSTNAME"
cp /home/${HADOOP_USER}/.ssh/id_rsa.pub /home/${HADOOP_USER}/.ssh/authorized_keys
chmod 600 /home/${HADOOP_USER}/.ssh/authorized_keys
chown -R ${HADOOP_USER}:${HADOOP_USER} /home/${HADOOP_USER}
echo "#########ssh 设置完成#########"

grep 'SELINUX=disabled' /etc/selinux/config && ISSET="true" || ISSET="false"
if [ "$ISSET" == "false" ]; then
    echo "#########关闭selinux#########"
    sed -i 's;SELINUX=enforcing;SELINUX=disabled;'  /etc/selinux/config
    setenforce 0
else
    echo "#########selinux 已关闭#########"
fi

#软件包目录
cd /var/tmp
if [ ! -d "/usr/java/jdk1.8.0_162" ]; then
    echo "#########JDK 安装#########"
    yum remove -y java*
    yum remove -y jdk*
    if [ ! -f "jdk-8u162-linux-x64.tar.gz" ]; then
        if [ -n "${DWON_URL}" ]; then
            wget ${DWON_URL}/jdk-8u162-linux-x64.tar.gz
        else
            wget https://mail-tp.fareoffice.com/java/jdk-8u162-linux-x64.tar.gz
        fi
    fi

    MD5NUM=`md5sum jdk-8u162-linux-x64.tar.gz|awk '{print $1}'`
    if [ "$MD5NUM" == "$JDK_MD5" ]; then
        tar -zxf jdk-8u162-linux-x64.tar.gz
        mkdir /usr/java/
        mv jdk1.8.0_162 /usr/java/
    else
        echo "md5 check wrong"
        exit
    fi
else
    echo "#########JDK 已安装#########"
fi

if [ ! -f "/etc/profile.d/java.sh" ]; then
    echo "#########JDK 环境配置#########"
    echo 'export JAVA_HOME=/usr/java/jdk1.8.0_162' > /etc/profile.d/java.sh
    echo 'export JRE_HOME=$JAVA_HOME/jre' >> /etc/profile.d/java.sh
    echo 'export CLASSPATH=.:$JAVA_HOME/lib:$JRE_HOME/lib' >> /etc/profile.d/java.sh
    source /etc/profile.d/java.sh
else
    echo "#########JDK 环境已配置#########"
fi

grep "JAVA_HOME" /etc/profile.d/path.sh && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    ###在行末插入
    sed -i '/PATH/ s/$/:\$JAVA_HOME\/bin/' /etc/profile.d/path.sh
    source /etc/profile.d/path.sh
fi

java -version

echo "#########hadoop 安装#########"
cd /var/tmp
if [ -d "${HA_INSTALL_DIR}/hadoop" ]; then
    rm -rf ${HA_INSTALL_DIR}/hadoop
fi
if [ ! -f "hadoop-${HADOOP_VERSION}.tar.gz" ]; then
    wget https://mirrors.tuna.tsinghua.edu.cn/apache/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz
fi

tar -zxf hadoop-${HADOOP_VERSION}.tar.gz -C ${HA_INSTALL_DIR}
mv /usr/local/hadoop-${HADOOP_VERSION} ${HA_INSTALL_DIR}/hadoop
chown -R ${HADOOP_USER}:${HADOOP_USER}  ${HA_INSTALL_DIR}/hadoop
echo "#########hadoop 安装完成#########"

###环境设置
if [ ! -f "/etc/profile.d/hadoop.sh" ]; then
    echo "#########hadoop 环境设置#########"
    echo "export HADOOP_HOME=${HA_INSTALL_DIR}/hadoop" > /etc/profile.d/hadoop.sh
    source /etc/profile.d/hadoop.sh
fi

###JAVA_HOME设置
grep "/usr/java/jdk1.8.0_162" ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    echo "export JAVA_HOME=/usr/java/jdk1.8.0_162" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh
fi

###HADOOP_PREFIX设置
grep "${HADOOP_HOME}" ${HADOOP_HOME}/libexec/hadoop-config.sh && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    sed -i "/# or POSIX:2001 compliant cd and pwd/a\HADOOP_PREFIX=\"/usr/local/hadoop\""  ${HADOOP_HOME}/libexec/hadoop-config.sh
fi

#SSH端口
grep "${SSH_PORT}" ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    echo "export HADOOP_SSH_OPTS=\"-p ${SSH_PORT}\"" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh
fi

###PATH设置
grep "HADOOP_HOME" /etc/profile.d/path.sh && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    sed -i '/PATH/ s/$/:\$HADOOP_HOME\/bin:\$HADOOP_HOME\/sbin/' /etc/profile.d/path.sh
    source /etc/profile.d/path.sh
else
    echo "#########hadoop 环境已设置#########"
fi

echo "#########hadoop 软链接设置#########"
rm -f /usr/libexec/hadoop-config.sh
rm -f /usr/libexec/hdfs-config.sh
rm -f /usr/bin/hadoop
rm -f /usr/bin/hdfs

ln -s ${HADOOP_HOME}/libexec/hadoop-config.sh /usr/libexec/hadoop-config.sh
ln -s ${HADOOP_HOME}/libexec/hdfs-config.sh /usr/libexec/hdfs-config.sh
ln -s ${HADOOP_HOME}/bin/hadoop /usr/bin/hadoop
ln -s ${HADOOP_HOME}/bin/hdfs /usr/bin/hdfs

echo "#########hadoop 软链接设置完成#########"

sudo -u ${HADOOP_USER} hadoop version


echo "#########hadoop 伪分布式配置#########"
echo "###设置core-site.xml###"
cat > ${HADOOP_HOME}/etc/hadoop/core-site.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>file://${HA_TMP_DIR}</value>
        <description>Abase for other temporary directories.</description>
    </property>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
</configuration>
EOF

echo "###设置hdfs-site.xml###"
cat > ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file://${NAMENODE_NAME_DIR}</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://${DATANODE_DATA_DIR}</value>
    </property>
</configuration>
EOF

echo "###设置mapred-site.xml###"
cat > ${HADOOP_HOME}/etc/hadoop/mapred-site.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>mapreduce.jobhistory.webapp.address</name>
    <value>$HOSTNAME:19888</value>
  </property>
  <property>
    <name>mapreduce.shuffle.max.connections</name>
    <value>0</value>
  </property>
     <property>
      <name>yarn.app.mapreduce.am.staging-dir</name>
      <value>/tmp/logs/</value>
     </property>
	<property>
	   <name>mapreduce.jobhistory.address</name>
	   <value>$HOSTNAME:10020</value>
	 </property>
	<property>
	   <name>mapreduce.jobhistory.joblist.cache.size</name>
	   <value>15000</value>
	 </property> 
</configuration>
EOF
echo "###设置yarn-site.xml###"
cat > $HADOOP_HOME/etc/hadoop/yarn-site.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>yarn.acl.enable</name>
    <value>true</value>
  </property>
  <property>
    <name>yarn.admin.acl</name>
    <value>*</value>
  </property>
  <property>
    <name>yarn.log-aggregation-enable</name>
    <value>true</value>
  </property>
  <property>
    <name>yarn.log-aggregation.retain-seconds</name>
    <value>604800</value>
  </property>
  <property>
    <name>yarn.resourcemanager.address</name>
    <value>$HOSTNAME:8032</value>
  </property>
  <property>
    <name>yarn.resourcemanager.admin.address</name>
    <value>$HOSTNAME:8033</value>
  </property>
  <property>
    <name>yarn.resourcemanager.scheduler.address</name>
    <value>$HOSTNAME:8030</value>
  </property>
  <property>
    <name>yarn.resourcemanager.resource-tracker.address</name>
    <value>$HOSTNAME:8031</value>
  </property>
  <property>
    <name>yarn.nodemanager.webapp.address</name>
    <value>$HOSTNAME:8042</value>
  </property>
  <property>
    <name>yarn.nodemanager.address</name>
    <value>$HOSTNAME:8041</value>
  </property>
  <property>
    <name>yarn.resourcemanager.client.thread-count</name>
    <value>50</value>
  </property>
  <property>
    <name>yarn.resourcemanager.scheduler.client.thread-count</name>
    <value>50</value>
  </property>
  <property>
    <name>yarn.resourcemanager.admin.client.thread-count</name>
    <value>1</value>
  </property>
  <property>
    <name>yarn.scheduler.minimum-allocation-mb</name>
    <value>1024</value>
  </property>
  <property>
    <name>yarn.scheduler.increment-allocation-mb</name>
    <value>512</value>
  </property>
  <property>
    <name>yarn.scheduler.maximum-allocation-mb</name>
    <value>61881</value>
  </property>
  <property>
    <name>yarn.scheduler.minimum-allocation-vcores</name>
    <value>1</value>
  </property>
  <property>
    <name>yarn.scheduler.increment-allocation-vcores</name>
    <value>1</value>
  </property>
  <property>
    <name>yarn.scheduler.maximum-allocation-vcores</name>
    <value>32</value>
  </property>
  <property>
    <name>yarn.resourcemanager.amliveliness-monitor.interval-ms</name>
    <value>1000</value>
  </property>
  <property>
    <name>yarn.am.liveness-monitor.expiry-interval-ms</name>
    <value>600000</value>
  </property>
  <property>
    <name>yarn.resourcemanager.am.max-attempts</name>
    <value>2</value>
  </property>
  <property>
    <name>yarn.resourcemanager.container.liveness-monitor.interval-ms</name>
    <value>600000</value>
  </property>
  <property>
    <name>yarn.resourcemanager.nm.liveness-monitor.interval-ms</name>
    <value>1000</value>
  </property>
  <property>
    <name>yarn.nm.liveness-monitor.expiry-interval-ms</name>
    <value>600000</value>
  </property>
  <property>
    <name>yarn.resourcemanager.resource-tracker.client.thread-count</name>
    <value>50</value>
  </property>
  <property>
    <name>yarn.resourcemanager.scheduler.class</name>
    <value>org.apache.hadoop.yarn.server.resourcemanager.scheduler.fair.FairScheduler</value>
  </property>
  <property>
    <name>yarn.nodemanager.container-monitor.interval-ms</name>
    <value>3000</value>
  </property>
  <property>
    <name>yarn.resourcemanager.max-completed-applications</name>
    <value>10000</value>
  </property>
  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle</value>
  </property>
  <property>
    <name>yarn.nodemanager.aux-services.mapreduce_shuffle.class</name>
    <value>org.apache.hadoop.mapred.ShuffleHandler</value>
  </property>
  <property>
    <name>yarn.nodemanager.local-dirs</name>
    <value>${YARN_NODEMG_DIR}</value>
  </property>
  <property>
    <name>yarn.nodemanager.log-dirs</name>
    <value>${YARN_NODEMG_LOG}</value>
  </property>
  <property>
    <name>yarn.nodemanager.webapp.address</name>
    <value>$HOSTNAME:8042</value>
  </property>
  <property>
    <name>yarn.nodemanager.webapp.https.address</name>
    <value>$HOSTNAME:8044</value>
  </property>
  <property>
    <name>yarn.nodemanager.address</name>
    <value>$HOSTNAME:8041</value>
  </property>
  <property>
    <name>yarn.nodemanager.env-whitelist</name>
    <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,HADOOP_YARN_HOME</value>
  </property>
  <property>
    <name>yarn.nodemanager.container-manager.thread-count</name>
    <value>20</value>
  </property>
  <property>
    <name>yarn.nodemanager.delete.thread-count</name>
    <value>4</value>
  </property>
  <property>
    <name>yarn.resourcemanager.nodemanagers.heartbeat-interval-ms</name>
    <value>100</value>
  </property>
  <property>
    <name>yarn.nodemanager.localizer.address</name>
    <value>$HOSTNAME:8040</value>
  </property>
  <property>
    <name>yarn.nodemanager.localizer.cache.cleanup.interval-ms</name>
    <value>600000</value>
  </property>
  <property>
    <name>yarn.nodemanager.localizer.cache.target-size-mb</name>
    <value>10240</value>
  </property>
  <property>
    <name>yarn.nodemanager.localizer.client.thread-count</name>
    <value>5</value>
  </property>
  <property>
    <name>yarn.nodemanager.localizer.fetch.thread-count</name>
    <value>4</value>
  </property>
  <property>
    <name>yarn.nodemanager.log.retain-seconds</name>
    <value>10800</value>
  </property>
  <property>
    <name>yarn.nodemanager.resource.memory-mb</name>
    <value>61881</value>
  </property>
  <property>
    <name>yarn.nodemanager.linux-container-executor.cgroups.strict-resource-usage</name>
    <value>false</value>
  </property>
  <property>
    <name>yarn.nodemanager.resource.percentage-physical-cpu-limit</name>
    <value>100</value>
  </property>
  <property>
    <name>yarn.nodemanager.resource.cpu-vcores</name>
    <value>32</value>
  </property>
  <property>
    <name>yarn.nodemanager.delete.debug-delay-sec</name>
    <value>0</value>
  </property>
  <property>
    <name>yarn.nodemanager.disk-health-checker.interval-ms</name>
    <value>120000</value>
  </property>
  <property>
    <name>yarn.nodemanager.disk-health-checker.min-free-space-per-disk-mb</name>
    <value>0</value>
  </property>
  <property>
    <name>yarn.nodemanager.disk-health-checker.max-disk-utilization-per-disk-percentage</name>
    <value>90.0</value>
  </property>
  <property>
    <name>yarn.nodemanager.disk-health-checker.min-healthy-disks</name>
    <value>0.25</value>
  </property>
  <property>
    <name>mapreduce.shuffle.max.threads</name>
    <value>80</value>
  </property>
  <property>
    <name>yarn.log.server.url</name>
    <value>http://$HOSTNAME:19888/jobhistory/logs</value>
  </property>
</configuration>
EOF

STR_LS="ls {${NAMENODE_NAME_DIR}}/current  && ISSET='true' || ISSET='false'"
echo $STR_LS
eval ${STR_LS}

if [ "$ISSET" == "false" ]; then
    echo "###格式化NameNode###"
    sudo -u ${HADOOP_USER} hdfs namenode -format
else
    echo "###NameNode已格式化###"
fi

#在指定行前插入用户定义
grep "HDFS_SECONDARYNAMENODE_USER" ${HADOOP_HOME}/sbin/start-dfs.sh && ISSET="true" || ISSET="false"
if [ "ISSET" == "false" ]; then
    sed -i "/# Start hadoop dfs daemons./i\export HDFS_SECONDARYNAMENODE_USER=${HADOOP_USER}"  ${HADOOP_HOME}/sbin/start-dfs.sh
    sed -i "/export HDFS_SECONDARYNAMENODE_USER=root/i\export HDFS_NAMENODE_USER=${HADOOP_USER}"  ${HADOOP_HOME}/sbin/start-dfs.sh
    sed -i "/export HDFS_NAMENODE_USER=root/i\export HDFS_DATANODE_SECURE_USER=${HADOOP_USER}" ${HADOOP_HOME}/sbin/start-dfs.sh
    sed -i "/export HDFS_DATANODE_SECURE_USER=root/i\export HDFS_DATANODE_USER=${HADOOP_USER}" ${HADOOP_HOME}/sbin/start-dfs.sh
fi

grep "HDFS_SECONDARYNAMENODE_USER" ${HADOOP_HOME}/sbin/stop-dfs.sh && ISSET="true" || ISSET="false"
if [ "ISSET" == "false" ]; then
    sed -i "/# Stop hadoop dfs daemons./i\export HDFS_SECONDARYNAMENODE_USER=${HADOOP_USER}"  ${HADOOP_HOME}/sbin/stop-dfs.sh
    sed -i "/export HDFS_SECONDARYNAMENODE_USER=root/i\export HDFS_NAMENODE_USER=${HADOOP_USER}"  ${HADOOP_HOME}/sbin/stop-dfs.sh
    sed -i "/export HDFS_NAMENODE_USER=root/i\export HDFS_DATANODE_SECURE_USER=${HADOOP_USER}" ${HADOOP_HOME}/sbin/stop-dfs.sh
    sed -i "/export HDFS_DATANODE_SECURE_USER=root/i\export HDFS_DATANODE_USER=${HADOOP_USER}" ${HADOOP_HOME}/sbin/stop-dfs.sh
fi

echo "###启动hadoop dfs###"
echo "sudo -u ${HADOOP_USER} $HADOOP_HOME/sbin/start-dfs.sh"
sudo -u ${HADOOP_USER} $HADOOP_HOME/sbin/start-dfs.sh

echo "###启动hadoop yarn###"
echo "sudo -u ${HADOOP_USER} $HADOOP_HOME/sbin/start-yarn.sh"
sudo -u ${HADOOP_USER} $HADOOP_HOME/sbin/start-yarn.sh

echo "###启动hadoop jobhistory##"
echo "sudo -u ${HADOOP_USER} $HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver"
sudo -u ${HADOOP_USER} $HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver

echo "###查看进程###"
jps
