#!/bin/bash
#azkaban安装

#环境设置:u 不存在的变量报错;e 发生错误退出;pipefail 管道有错退出
set -euo pipefail

START_TIME=`date +%s`

#########要更改变的变量#######
###临时目录
TMP_DIR="/var/tmp"

###安装模式:sole:单机;singledist:单机伪分布式
INSTALL_MODE="singledist"

###安装目录
INSTALL_DIR="/usr/local"
###登录信息
USER="azadmin"
PASS="111111"

###mysql,要先创建好
MYSQL_PORT="63751"
MYSQL_HOST="127.0.0.1"
MYSQL_DB="azkaban"
MYSQL_USER="azkaban"
MYSQL_PASS="azkaban"

SQL_PATH="${INSTALL_DIR}/db/create-all-sql.sql"
##############################
cd ${TMP_DIR}
if [ ! -f "/usr/bin/funzip" ]; then
    echo "==========安装unzip========="
    yum install -y unzip
fi

if [ ! -f "/etc/profile.d/path.sh" ]; then
cat > /etc/profile.d/path.sh <<EOF
export PATH=\$PATH:/sbin:/usr/sbin:/usr/local/sbin
#export TMOUT=1800
#if [[ -n "\$SSH_CLIENT"  ]] || [[ -n "\$SSH_CONNECTION" ]];then
#        export TMOUT=3600
#fi
EOF
fi

if [ ! -f "/usr/bin/git" ]; then
    yum install -y git
fi

if [ ! -f "gradle-4.6-bin.zip" ]; then
    echo "==========下载gradle========="
    wget --no-check-certificate https://services.gradle.org/distributions/gradle-4.6-bin.zip
fi


if [ ! -d "/usr/local/gradle" ]; then
    echo "==========安装gradle========="
    echo "unzip -q gradle-4.6-bin.zip"
    unzip -q gradle-4.6-bin.zip
    echo "mv gradle-4.6 /usr/local/gradle"
    mv gradle-4.6 /usr/local/gradle
fi

if [ ! -f "/etc/profile.d/gradle.sh" ]; then
    echo 'export GRADLE_HOME=/usr/local/gradle' > /etc/profile.d/gradle.sh
fi


grep "GRADLE_HOME" /etc/profile.d/path.sh && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    sed -i  '/PATH/ s/$/:$GRADLE_HOME\/bin/' /etc/profile.d/path.sh
fi

###gradle国内镜像
if [ ! -f "/root/.gradle/init.gradle" ]; then
cat > /root/.gradle/init.gradle <<EOF
allprojects{ 
    repositories { 
        def ALIYUN_REPOSITORY_URL = 'http://maven.aliyun.com/nexus/content/groups/public' 
        def ALIYUN_JCENTER_URL = 'http://maven.aliyun.com/nexus/content/repositories/jcenter' 
        all { 
            ArtifactRepository repo -> 
                if(repo instanceof MavenArtifactRepository){ 
                    def url = repo.url.toString() 
                    if (url.startsWith('https://repo1.maven.org/maven2')) { 
                        project.logger.lifecycle "Repository \${repo.url} replaced by \$ALIYUN_REPOSITORY_URL." 
                        remove repo 
                    }
                    if (url.startsWith('https://repo.maven.apache.org/maven2')) { 
                        project.logger.lifecycle "Repository \${repo.url} replaced by \$ALIYUN_REPOSITORY_URL." 
                        remove repo 
                    } 
                    if (url.startsWith('https://jcenter.bintray.com/')) { 
                        project.logger.lifecycle "Repository \${repo.url} replaced by \$ALIYUN_JCENTER_URL." 
                        remove repo 
                    } 
                } 
        } 
        maven { 
            url ALIYUN_REPOSITORY_URL 
            url ALIYUN_JCENTER_URL 
        } 
    } 
}
EOF
fi

source /etc/profile.d/gradle.sh
source /etc/profile.d/path.sh

echo "==========安装azkaban========="
if [ ! -d "${TMP_DIR}/azkaban" ]; then
    git clone git://github.com/azkaban/azkaban.git
fi

echo "cd ${TMP_DIR}/azkaban"
cd ${TMP_DIR}/azkaban

echo "==========编译azkaban========="
echo "gradle wrapper --gradle-distribution-url https://repo.gradle.org/gradle/dist-snapshots/gradle-kotlin-dsl-4.9-20180629133202+0000-all.zip"
${GRADLE_HOME}/bin/gradle wrapper --gradle-distribution-url https://repo.gradle.org/gradle/dist-snapshots/gradle-kotlin-dsl-4.9-20180629133202+0000-all.zip
echo "${TMP_DIR}/azkaban/gradlew distTar -x test"
${TMP_DIR}/azkaban/gradlew distTar -x test

if [ "${INSTALL_MODE}" == "sole" ]; then
    echo "==========设置azkaban单机模式========="
    cp ${TMP_DIR}/azkaban/azkaban-solo-server/build/distributions/*.tar.gz ${TMP_DIR}/
    cd ${TMP_DIR}
    tar -zxf azkaban-solo-server-*.tar.gz
    rm -f azkaban-solo-server-*.tar.gz
    mv azkaban-solo-server-* ${INSTALL_DIR}/azkaban
    if [ ! -d "${INSTALL_DIR}/azkaban/plugins/jobtypes" ]; then
        mkdir -p ${INSTALL_DIR}/azkaban/plugins/jobtypes
    fi
    cd ${INSTALL_DIR}/azkaban/conf
    mv azkaban.properties azkaban.properties.bak
cat > azkaban.properties <<EOF
azkaban.name=Test
azkaban.label=My Local Azkaban
azkaban.color=#FF3601
azkaban.default.servlet.path=/index
web.resource.dir=web/
default.timezone.id=Asia/Shanghai
user.manager.class=azkaban.user.XmlUserManager
user.manager.xml.file=conf/azkaban-users.xml
executor.global.properties=conf/global.properties
azkaban.project.dir=projects
database.type=h2
h2.path=./h2
h2.create.tables=true
velocity.dev.mode=false
jetty.use.ssl=false
jetty.maxThreads=25
jetty.port=8081
executor.port=12321
lockdown.create.projects=false
lockdown.upload.projects=false
cache.directory=cache
jetty.connector.stats=true
executor.connector.stats=true
azkaban.jobtype.plugin.dir=plugins/jobtypes
EOF

    mv azkaban-users.xml azkaban-users.xml.bak
cat > azkaban-users.xml <<EOF
<azkaban-users>
<user groups="azkaban" password=""$PASS"" username=""$USER""/>

<group name="azkaban" roles="admin"/>
<group name="metrics" roles="metrics"/>
<group name="group_leader" roles="leader"/>
<group name="group_inspector" roles="inspector"/>
<group name="group_schedule" roles="schedule"/>

<role name="admin" permissions="ADMIN"/>
<role name="metrics" permissions="METRICS"/>
<role name="leader" permissions="READ,WRITE,EXECUTE,SCHEDULE,CREATEPROJECTS"/>
<role name="inspector" permissions="READ"/>
<role name="write" permissions="WRITE"/>
<role name="execute" permissions="EXECUTE"/>
<role name="schedule" permissions="SCHEDULE"/>
<role name="createprojects" permissions="CREATEPROJECTS"/>
</azkaban-users>
EOF
    cd ${INSTALL_DIR}/azkaban
    ./bin/start-solo.sh
fi

if [ "${INSTALL_MODE}" == "sole" ]; then
    echo "==========azkaban单机伪分布式安装========="
    cp ${TMP_DIR}/azkaban/azkaban-exec-server/build/distributions/*.tar.gz ${TMP_DIR}/
    cp ${TMP_DIR}/azkaban/azkaban-web-server/build/distributions/*.tar.gz ${TMP_DIR}/
    cp ${TMP_DIR}/azkaban/azkaban-db/build/distributions/*.tar.gz ${TMP_DIR}/
    cd ${TMP_DIR}
    tar -zxf azkaban-web-server-*.tar.gz
    tar -zxf azkaban-exec-server-*.tar.gz
    tar -zxf azkaban-db-*.tar.gz
    rm -f azkaban-web-server-*.tar.gz
    rm -f azkaban-exec-server-*.tar.gz
    rm -f azkaban-db-*.tar.gz
    if [ -d "${INSTALL_DIR}/azkaban" ]; then
        rm -rf ${INSTALL_DIR}/azkaban
        mkdir ${INSTALL_DIR}/azkaban
    fi

    mv azkaban-web-server-* ${INSTALL_DIR}/azkaban/web
    mv azkaban-exec-server-* ${INSTALL_DIR}/azkaban/exec
    mv azkaban-db-* ${INSTALL_DIR}/azkaban/db

    echo "==========设置azkaban单机伪分布式exec========="
    cd ${INSTALL_DIR}/azkaban/exec/conf
    if [ ! -d "${INSTALL_DIR}/azkaban/exec/plugins/jobtypes" ]; then
        mkdir -p ${INSTALL_DIR}/azkaban/exec/plugins/jobtypes
    fi
    if [ ! -f "${INSTALL_DIR}/azkaban/exec/conf/global.properties" ]; then
        touch ${INSTALL_DIR}/azkaban/exec/conf/global.properties
    fi

    mv azkaban.properties azkaban.properties.bak
cat > azkaban.properties <<EOF
#executor 在启动时会向executors表插入记录
database.type=mysql
mysql.port=${MYSQL_PORT}
mysql.host=${MYSQL_HOST}
mysql.database=${MYSQL_DB}
mysql.user=${MYSQL_USER}
mysql.password=${MYSQL_PASS}
mysql.numconnections=100

# 下面都是默认值
# Azkaban Executor settings
executor.maxThreads=50
executor.port=12321
executor.flow.threads=30

# Azkaban JobTypes Plugins
azkaban.jobtype.plugin.dir=plugins/jobtypes

# Azkaban the parent for all jobs
executor.global.properties=conf/global.properties
EOF

    echo "==========设置azkaban单机伪分布式web========="
    if [ ! -d "${INSTALL_DIR}/azkaban/web/plugins/jobtypes" ]; then
        mkdir -p ${INSTALL_DIR}/azkaban/web/plugins/jobtypes
    fi

    if [ ! -d "${INSTALL_DIR}/azkaban/web/plugins/triggers" ]; then
        mkdir -p ${INSTALL_DIR}/azkaban/web/plugins/triggers
    fi

    cd ${INSTALL_DIR}/azkaban/web/conf
    mv azkaban.properties azkaban.properties.bak
cat > azkaban.properties <<EOF
azkaban.name=Test
azkaban.label=My Local Azkaban
azkaban.color=#FF3601
azkaban.default.servlet.path=/index
web.resource.dir=web/
default.timezone.id=Asia/Shanghai
user.manager.class=azkaban.user.XmlUserManager
user.manager.xml.file=conf/azkaban-users.xml
executor.global.properties=conf/global.properties
azkaban.project.dir=projects
h2.create.tables=true
velocity.dev.mode=false
jetty.use.ssl=false
jetty.maxThreads=25
jetty.port=8081
executor.port=12321
lockdown.create.projects=false
lockdown.upload.projects=false
cache.directory=cache
jetty.connector.stats=true
executor.connector.stats=true
azkaban.jobtype.plugin.dir=plugins/jobtypes
database.type=mysql
mysql.port=${MYSQL_PORT}
mysql.host=${MYSQL_HOST}
mysql.database=${MYSQL_DB}
mysql.user=${MYSQL_USER}
mysql.password=${MYSQL_PASS}
mysql.numconnections=100
EOF

    mv azkaban-users.xml azkaban-users.xml.bak
cat > azkaban-users.xml <<EOF
<azkaban-users>
<user groups="azkaban" password=""$PASS"" username=""$USER""/>

<group name="azkaban" roles="admin"/>
<group name="metrics" roles="metrics"/>
<group name="group_leader" roles="leader"/>
<group name="group_inspector" roles="inspector"/>
<group name="group_schedule" roles="schedule"/>

<role name="admin" permissions="ADMIN"/>
<role name="metrics" permissions="METRICS"/>
<role name="leader" permissions="READ,WRITE,EXECUTE,SCHEDULE,CREATEPROJECTS"/>
<role name="inspector" permissions="READ"/>
<role name="write" permissions="WRITE"/>
<role name="execute" permissions="EXECUTE"/>
<role name="schedule" permissions="SCHEDULE"/>
<role name="createprojects" permissions="CREATEPROJECTS"/>
</azkaban-users>
EOF

    mv log4j.properties log4j.properties.bak
cat > log4j.properties <<EOF
log4j.rootLogger=INFO, Console
log4j.logger.azkaban=INFO, server
log4j.appender.server=org.apache.log4j.RollingFileAppender
log4j.appender.server.layout=org.apache.log4j.PatternLayout
log4j.appender.server.File=local/azkaban-webserver.log
log4j.appender.server.layout.ConversionPattern=%d{yyyy/MM/dd HH:mm:ss.SSS Z} %p [%c{1}] [Azkaban] %m%n
log4j.appender.server.MaxFileSize=102400MB
log4j.appender.server.MaxBackupIndex=2
log4j.appender.Console=org.apache.log4j.ConsoleAppender
log4j.appender.Console.layout=org.apache.log4j.PatternLayout
log4j.appender.Console.layout.ConversionPattern=%d{yyyy/MM/dd HH:mm:ss.SSS Z} %p [%c{1}] [Azkaban] %m%n
EOF


    echo "==========启动azkaban单机伪分布式========="
    cd ${INSTALL_DIR}/azkaban/exec/ && ./bin/start-exec.sh
    cd ${INSTALL_DIR}/azkaban/web/ && ./bin/start-web.sh
fi
