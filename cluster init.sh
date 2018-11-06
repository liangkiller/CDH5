#!/bin/sh

#用空格分隔
#需指定master,为空或不为master的为slave
CLUSTER=`cat << EOF
192.168.115.141 master.com master
192.168.115.142 slave.com slave
EOF
`

function set_ntp_server(){
#配置ntp.conf
cat > /etc/ntp.conf << EOF
driftfile /var/lib/ntp/drift
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1 
restrict -6 ::1
server ntp1.aliyun.com iburst
server 0.cn.pool.ntp.org iburst
server 3.asia.pool.ntp.org iburst
# 允许上层时间服务器主动修改本机时间
restrict ntp1.aliyun.com nomodify notrap noquery
restrict 0.cn.pool.ntp.org nomodify notrap noquery
restrict 3.asia.pool.ntp.org nomodify notrap noquery
# 外部时间服务器不可用时，以本地时间作为时间服务
server 127.127.1.0 # local clock
fudge 127.127.1.0 stratum 10

includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
EOF
    service ntpd start
}

function set_ntp_client(){
    MASTERIP=$1
#配置ntp.conf
cat > /etc/ntp.conf << EOF
driftfile /var/lib/ntp/drift
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1 
restrict -6 ::1
server $MASTERIP prefer
# 允许上层时间服务器主动修改本机时间
restrict $MASTERIP nomodify notrap noquery
# 外部时间服务器不可用时，以本地时间作为时间服务
server 127.127.1.0 # local clock
fudge 127.127.1.0 stratum 10
includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
EOF
    service ntpd start
}


#ntp
#安装
NTPINSTALL=`rpm -qa|grep ntp`
ret=$?
if [ $ret -ne 0 ]
then
    echo "==========安装ntp=========="
    #同步时间
    ntpdate ntp1.aliyun.com
    hwclock --systohc
    yum install  -y ntp
    chkconfig ntpd on
else
    echo "==========ntp已安装=========="
fi
#时区
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime



echo "==========获得master ip=========="
while read line; do
    ROLE=`echo $line | awk '{print $3}'`
    ret=$?
    if [ $ret -eq 0  -a "$ROLE" == "master" ]
    then
        MASTERIP=`echo $line | awk '{print $1}'`
    fi
done <<< "$CLUSTER"
echo "==========master ip:$MASTERIP=========="

echo "==========设置/etc/hosts=========="
while read line; do
        #获得hostname
        HOSTNAME=`echo $line | awk '{print $2}'`
        cat /etc/hosts|grep $HOSTNAME
        ret=$?
        if [ $ret -ne 0 ]
        then
            echo $line >> /etc/hosts
        fi
done <<< "$CLUSTER"
echo "==========/etc/hosts设置完成=========="

while read line; do
    #本机IP
    LOCALIP=`/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:" `
    #配置ip
    IP=`echo $line | awk '{print $1}'`

    if [ "$LOCALIP" == "$IP" ]
    then
        echo "==========hostname设置=========="
        #获得hostname
        HOSTNAME=`echo $line | awk '{print $2}'`
        echo "/bin/hostname $HOSTNAME"
        /bin/hostname $HOSTNAME
    #here document要顶格写
cat > /etc/sysconfig/network << EOF 
NETWORKING=yes
HOSTNAME=$HOSTNAME
EOF
        ROLE=`echo $line | awk '{print $3}'`
        ret=$?
        if [ $ret -eq 0  -a "$ROLE" == "master" ]
        then
            echo "==========NTP服务端设置=========="
            set_ntp_server
        else
            echo "==========NTP客户端设置=========="
            set_ntp_client $MASTERIP
        fi
    fi
done <<< "$CLUSTER"

echo "==========ssh 设置=========="
rm -rf ~/.ssh/
echo "ssh key 密码为 as457KY"
ssh-keygen  -t  rsa -N 'as457KY' -f  '/root/.ssh/id_rsa'
cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "==========关闭selinux=========="
sed -i 's;SELINUX=enforcing;SELINUX=disabled;'  /etc/selinux/config
setenforce 0
read -p "是否关闭防火墙[y/n]:" -n 1 str
echo -e "\n"
if [ "$str" == "y" ]
then
    echo "==========关闭防火墙=========="
    service iptables stop
    chkconfig iptables off
fi
