#!/bin/bash
###cdh集群离线安装

START_TIME=`date +%s`

#环境设置:u 不存在的变量报错;e 发生错误退出;pipefail 管道有错退出
set -euo pipefail

#########要更改变的变量#######
###安装类型,可输入server,client.默认client
TYPE=${1:-"client"}

###版本
CDH_VERSION="5.15.0-1.cm5150.p0.62"
PARCEL_VERSION="5.15.0-1.cdh5.15.0.p0.21"
PARCEL_PARENT=`echo ${CDH_VERSION} | awk -F "-" '{print $1}'`

###MYSQL信息
MYSQL_CNF="/etc/my.cnf"
MYSQL_DATA_DIR=`sed '/^datadir.*=/!d;s/.*=//' ${MYSQL_CNF} | sed 's/^[ \t]*//g'| head -1`
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASS=''

###MYSQL创建信息
##cloudera-manager
CM_DB="cmf"
CM_USER="cmf"
CM_PASS="cmf"
###其他库信息，按数据库名，用户，密码格式
DB_INFO="
amon amon amon
rman rman rman
nav nav nav
navms navms navms
sentry sentry sentry
hive hive hive
oozie oozie oozie
hue hue hue
"

###下载地址
DOWN_URL="http://222.187.240.238/soft"

if [ -n "${DOWN_URL}" ]; then
    CDH_MG_SERVER_URL="${DOWN_URL}/cdh/cloudera-manager-server-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_DB_URL="${DOWN_URL}/cdh/cloudera-manager-server-db-2-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_DAEMON_URL="${DOWN_URL}/cdh/cloudera-manager-daemons-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_AGENT_URL="${DOWN_URL}/cdh/cloudera-manager-agent-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_DEBUG_URL="${DOWN_URL}/cdh/enterprise-debuginfo-${CDH_VERSION}.el6.x86_64.rpm"
    MYSQL_CONNECTOR_URL="${DOWN_URL}/mysql/mysql-connector-java-5.1.46.tar.gz"
    PARCEL_URL="${DOWN_URL}/cdh/CDH-${PARCEL_VERSION}-el6.parcel"
    PARCEL_SHA="${DOWN_URL}/cdh/CDH-${PARCEL_VERSION}-el6.parcel.sha1"
    REPO="${DOWN_URL}/cdh/cloudera-cm.repo"
    JDBC="${DOWN_URL}/mysql/mysql-connector-java-5.1.46.tar.gz"
else
    CDH_URL="https://archive.cloudera.com/cm5/redhat/6/x86_64/cm/5.15.0/RPMS/x86_64"
    CDH_MG_SERVER_URL="${CDH_URL}/cloudera-manager-server-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_DB_URL="${CDH_URL}/cloudera-manager-server-db-2-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_DAEMON_URL="${CDH_URL}/cloudera-manager-daemons-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_AGENT_URL="${CDH_URL}/cloudera-manager-agent-${CDH_VERSION}.el6.x86_64.rpm"
    CDH_MG_DEBUG_URL="${CDH_URL}/enterprise-debuginfo-${CDH_VERSION}.el6.x86_64.rpm"
    MYSQL_CONNECTOR_URL="http://mirrors.ustc.edu.cn/mysql-ftp/Downloads/Connector-J/mysql-connector-java-5.1.46.tar.gz"
    PARCEL_URL="https://archive.cloudera.com/cdh5/parcels/${PARCEL_PARENT}/CDH-${CDH_VERSION}-el6.parcel"
    PARCEL_SHA="https://archive.cloudera.com/cdh5/parcels/${PARCEL_PARENT}/CDH-${CDH_VERSION}-el6.parcel.sha1"
    REPO="https://archive.cloudera.com/cm5/redhat/6/x86_64/cm/cloudera-manager.repo"
    JDBC="http://mirrors.ustc.edu.cn/mysql-ftp/Downloads/Connector-J/mysql-connector-java-5.1.46.tar.gz"
fi

##############################
###安装前系统设置
echo 1 > /proc/sys/vm/swappiness
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo never > /sys/kernel/mm/transparent_hugepage/enabled
###写入启动文件
grep "transparent_hugepage" /etc/rc.local  && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    echo "echo 1 > /proc/sys/vm/swappiness" >> /etc/rc.local
    echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.local
    echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
fi

cd /var/tmp

echo "=========依赖包安装=========="
if [ ! -f "/usr/sbin/httpd" ]; then
    yum install -y apr apr-util apr-util-ldap fuse fuse-libs httpd httpd-tools mod_ssl bind-utils
fi
if [ ! -f "/usr/bin/xsltproc" ]; then
    yum install -y MySQL-python python-psycopg2  libxslt cyrus-sasl-plain cyrus-sasl-gssapi portmap openssl-devel redhat-lsb-core
fi
if [ ! -f "/usr/bin/postgres" ]; then
    yum install -y postgresql-server
fi

echo "=========repo安装=========="
if [ ! -f "/etc/yum.repos.d/cloudera-manager.repo" ]; then
    wget ${REPO} -O /etc/yum.repos.d/cloudera-manager.repo
fi

echo "=========jdbc安装=========="
if [ ! -f "/usr/share/java/mysql-connector-java.jar" ]; then
    cd /var/tmp
    wget ${JDBC}
    tar -zxf mysql-connector-java-5.1.46.tar.gz
    cp mysql-connector-java-5.1.46/mysql-connector-java-5.1.46-bin.jar /usr/share/java/mysql-connector-java.jar
fi

if [ "$TYPE" == 'server' ]; then
    if [ ! -f "cloudera-manager-server-${CDH_VERSION}.el6.x86_64.rpm" ]; then
        wget ${CDH_MG_SERVER_URL}
        wget ${CDH_MG_DB_URL}
        wget ${CDH_MG_DAEMON_URL}
        wget ${CDH_MG_DEBUG_URL}
        wget ${CDH_MG_AGENT_URL}
    fi
    if [ ! -f "/usr/sbin/cmf-server" ]; then
        echo "=========CM server端 安装=========="
        rpm -ivh cloudera-*.rpm
        rpm -ivh enterprise-debuginfo-${CDH_VERSION}.el6.x86_64.rpm
        echo "=========CM server端已安装=========="
    else
        echo "=========CM server端已存在=========="
    fi

    echo "=========配置使用mysql=========="
    if [ ! -f "/usr/bin/mysql" ]; then
        echo "请安装mysql"
        exit;
    fi
    
    if [ ! -d "${MYSQL_DATA_DIR}/${CM_DB}" ]; then
        ###新建库
        ###cloudera-manager
        echo "mysql -h${MYSQL_HOST} -u${MYSQL_USER} -P${MYSQL_PORT} -p'${MYSQL_PASS}' --connect-expired-password  -e \"create database ${CM_DB} DEFAULT CHARACTER SET utf8;CREATE USER '${CM_USER}'@'%' IDENTIFIED BY '${CM_PASS}';CREATE USER '${CM_USER}'@'localhost' IDENTIFIED BY '${CM_PASS}';GRANT ALL PRIVILEGES ON ${CM_DB}.* TO '${CM_USER}';GRANT ALL PRIVILEGES ON ${CM_DB}.* TO '${CM_USER}'@'localhost';\""

        mysql -h${MYSQL_HOST} -u${MYSQL_USER} -P${MYSQL_PORT} -p"${MYSQL_PASS}" --connect-expired-password  -e "create database cmf DEFAULT CHARACTER SET utf8;CREATE USER '${CM_USER}'@'%' IDENTIFIED BY '${CM_PASS}';CREATE USER '${CM_USER}'@'localhost' IDENTIFIED BY '${CM_PASS}';GRANT ALL PRIVILEGES ON ${CM_DB}.* TO '${CM_USER}'@'%';GRANT ALL PRIVILEGES ON ${CM_DB}.* TO '${CM_USER}'@'localhost';"
        echo "=========${CM_DB}库设置完成=========="
    else
        echo "=========cfm库已存在=========="
    fi

    echo "${DB_INFO}" | while read line; do
        if [ -n "$line"  ]; then
            DB=`echo $line|awk '{print $1}'`
            USER=`echo $line|awk '{print $2}'`
            PASS=`echo $line|awk '{print $3}'`
            echo "数据库: "$DB
            if [ ! -d "${MYSQL_DATA_DIR}/${DB}" ]; then
                mysql -h${MYSQL_HOST} -u${MYSQL_USER} -P${MYSQL_PORT} -p"${MYSQL_PASS}" --connect-expired-password  -e "create database $DB DEFAULT CHARACTER SET utf8;CREATE USER '${USER}'@'%' IDENTIFIED BY '${PASS}';CREATE USER '${USER}'@'localhost' IDENTIFIED BY '${PASS}';GRANT ALL PRIVILEGES ON ${DB}.* TO '${USER}'@'%';GRANT ALL PRIVILEGES ON ${DB}.* TO '${USER}'@'localhost';"
            fi
        fi
    done

    grep "${CM_DB}" /etc/cloudera-scm-server/db.properties && ISSET="true" || ISSET="false"
    if [  "$ISSET" == "false" ]; then
cat > /etc/cloudera-scm-server/db.properties <<EOF
com.cloudera.cmf.db.type=mysql
com.cloudera.cmf.db.host=${MYSQL_HOST}:${MYSQL_PORT}
com.cloudera.cmf.db.name=${CM_DB}
com.cloudera.cmf.db.user=${CM_USER}
com.cloudera.cmf.db.password=${CM_PASS}
com.cloudera.cmf.db.setupType=EXTERNAL
EOF
    fi

    ###下载parcel
    if [ ! -f "/opt/cloudera/parcel-repo/CDH-${PARCEL_VERSION}-el6.parcel" ]; then
        wget ${PARCEL_URL} -O /opt/cloudera/parcel-repo/CDH-${PARCEL_VERSION}-el6.parcel
        wget ${PARCEL_SHA} -O /opt/cloudera/parcel-repo/CDH-${CDH_VERSION}-el6.parcel.sha
    fi

    chown cloudera-scm.cloudera-scm /opt/cloudera -R
    chown cloudera-scm.cloudera-scm /var/log/cloudera-scm-agent -R

    service cloudera-scm-server start
    tail -f /var/log/cloudera-scm-server/cloudera-scm-server.log
fi

if [ "$TYPE" == 'client' ]; then
    if [ ! -f "cloudera-manager-agent-${CDH_VERSION}.el6.x86_64.rpm" ]; then
        wget ${CDH_MG_AGENT_URL}
        wget ${CDH_MG_DAEMON_URL}
    fi

    if [ ! -f "/usr/sbin/cmf-agent" ]; then
        echo "=========CM 客户端 安装=========="
        rpm -ivh  cloudera-manager-daemons-${CDH_VERSION}.el6.x86_64.rpm
        rmm -ivh  cloudera-manager-agent-${CDH_VERSION}.el6.x86_64.rpm
        echo "=========CM 客户端端已安装=========="
    else
        echo "=========CM 客户端端已存在=========="
    fi

fi


echo "=====运行时间为====="
END_TIME=`date +%s`
dif=$[ END_TIME - START_TIME ] 
echo $dif "秒"
