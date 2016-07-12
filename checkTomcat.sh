#!/bin/bash
# 检测tomcat进程的状态
# 异常后自动重启
# 不允许使用root执行
# 创建：高峰
# 时间：2016-07-11

# 依赖包：
# 	bc


# 设定全局变量
source /etc/profile
pidfile="/dev/shm/checkTomcat.pid"

###############################################先设定这里######################################
# 检测次数，检测多少次以后算问题出现
checkCount=100
# CPU限额，超过这个值认为cpu使用过高，设为1则cpu使用率限额为1%。
usage=1
# tomcat pid的地址，用于关闭tomcat
TOMCAT_PID_PATH="/dev/shm/tomcat7.pid"
# tomcat bin 路径，用于寻找启动脚本
TOMCAT_BIN_PATH="/opt/soft/tomcat-7.0.64/bin"
###############################################################################################

# 定义日志路径
logFile=/dev/null
# logFile=$path"reloadTomcat_"`date +%F`.log

# 定义字体颜色
logErr() {
    echo -e `date +%G/%m/%d\ %T`" [\033[31;1m错误\033[0m] \033[31;1m"$@"\033[0m"
    echo `date +%G/%m/%d\ %T`" [错误] "$@ >> $logFile
}
logNotice(){
    echo -e `date +%G/%m/%d\ %T`" [\033[36;1m信息\033[0m] \033[36;1m"$@"\033[0m"
    echo `date +%G/%m/%d\ %T`" [信息] "$@ >> $logFile
}
logSucess(){
    echo -e `date +%G/%m/%d\ %T`" [\033[32;1m正确\033[0m] \033[32;1m"$@"\033[0m"
    echo `date +%G/%m/%d\ %T`" [正确] "$@ >> $logFile
}
echoRed(){
    echo -e "\033[31;1m"$@"\033[0m"
}
echoBlue(){
    echo -e "\033[36;1m"$@"\033[0m"
}
echoGreen(){
    echo -e "\033[32;1m"$@"\033[0m"
}
echoYellow(){
    echo -e "\033[33;1m"$@"\033[0m"
}

eexit(){
	rm -rf $pidfile
	exit $1
}

sleepa(){
	# 一次等待时间需要调整sleep值，等待时间=sleep*50 秒
	b=''
	for ((i=100;$i>=0;i-=2))
	do
	    printf "等待中:[%-50s]\r" $b 
	    sleep 0.1
	    b==$b
	done
	echo
}

getCpuUsege() {
	# t1=`cat /proc/stat|head -n1|tr "cpu" " "|awk '{print $1+$2+$3+$4+$5+$6+$7+$8+$9}'`
	# s1=`cat /proc/$1/stat|awk '{print $14+$15+$16+$17}'`
	# sleep 0.1
	# t2=`cat /proc/stat|head -n1|tr "cpu" " "|awk '{print $1+$2+$3+$4+$5+$6+$7+$8+$9}'`
	# s2=`cat /proc/$1/stat|awk '{print $14+$15+$16+$17}'`
	# echo -e "$t1\t$t2\t$s1\t$s2"|awk '{print 100*($4-$3)/($2-$1)}'
	echo `top -n 1 -b -p $1|grep java|awk '{print $9}'`
}

isSelfOn(){	#检测本进程是否有运行中的 根据pidfile检查 ，存在返回1，不存在返回0.
	logNotice "pid文件\t\t->\t$pidfile"
	if [[ -a $pidfile ]]; then
		# 如果文件存在，继续检查
		# 获取pid
		pid=`cat /dev/shm/checkTomcat.pid`
		logNotice "PID文件存在，记录的PID为[$pid]。"
		# 获取此pid在进程列表中的数量，最大值为1，如果是1，则存在。
		selfCount=`ps -e|grep $pid|grep -v grep|wc -l`
		logNotice "进程数量\t\t->\t$selfCount"
		if [[ $selfCount -eq 1 ]]; then
			# 如果为1，则进程存在，退出.
			logErr "此进程已经在运行，不允许重复执行，退出！"
			eexit 1
		else
			# 如果检测不到，说明这个进程没启动
			logNotice "PID文件存在，但进程不存在，将继续启动。"
			logSucess "本次创建的进程pid为[$$]。"
			echo $$ > $pidfile
			return 0
		fi
	else
		# 如果文件不存在，说明这个进程没启动
		logNotice "PID文件不存在，程序启动。"
		logSucess "本次创建的进程pid为[$$]。"
		echo $$ > $pidfile
		return 0
	fi
}

restartTomcat(){	#根据pid重启这个tomcat进程
logSucess "$1\t->\t$1"
if [[ ! -z $1 ]]; then
	#statements
	logNotice "要重启的tomcat其PID为[$1]。"
	sleepa
	kill -9 $1
	logSucess "杀死了pid为$1的Tomcat进程。"
	sh /usr/local/tomcat7/bin/startup.sh
	logSucess "启动新的Tomcat进程……"
	sleepa
	logNotice `ps -ef|grep tomcat|grep -v grep|grep -v $$`
	eexit 0
else
	logErr "参数1不能为空！"
	eexit 1
fi
}

checkMe (){
	if [ `id -u` -eq 0 ];then
		# 必须使用root身份，否则不能操作nginx
		logErr 	"您不能使用root身份来执行此脚本。"
		eexit	1
	fi
}

checkTomcat(){	#检查tomcat的健康状态
	if [[ ! -a $TOMCAT_PID_PATH ]]; then
		logNotice "$TOMCAT_PID_PATH文件不存在，Tomcat未启动，将启动Tomcat。"
		sh /usr/local/tomcat7/bin/startup.sh
		eexit 0
	fi

	tomPid=`cat $TOMCAT_PID_PATH`
	logNotice "TOMCAT_PID\t\t->\t$tomPid"
	cpuUsage=`getCpuUsege $tomPid`
	logNotice "TOMCAT_CPU_USAGE\t->\t$cpuUsage%"
	aa=`echo -e $cpuUsage\>\=$usage|bc`	# 如果第一个值大于等于第二个值，则输出1，否则输出0.

	if [[ $aa -lt "1" ]]; then
		logSucess "CPU使用率正常。"
		eexit 0
	else
		for ((ii=1;$ii<=$checkCount;ii+=1))
		do
			logNotice "检测次数\t\t->\t$ii"
			if [[ $aa -lt "1" ]]; then
				# 如果小于1，则说明没有超过设定值，直接退出。
				logSucess "CPU使用率恢复正常，将退出。"
				ii=$checkCount
			else
				# cpu使用率超过了设定值，根据条件决定下面操作。
				if [[ $ii -ge $checkCount ]]; then
					#超过设定次数，执行重启操作，然后跳出。
					logErr "CPU使用率[$cpuUsage%]超过了限定值[$usage%]!"
					logErr "在检测了[$checkCount]次以后CPU使用率仍然没有恢复到设定值以下，判定为cpu使用率不正常，将重启Tomcat。"
					logSucess "tomcatpid\t->\t$tomPid"
					restartTomcat $tomPid
					break
				fi
				logErr "CPU使用率[$cpuUsage%]超过了限定值[$usage%]，等一会将重新检测！"
				sleepa
				cpuUsage=`getCpuUsege $tomPid`
				logNotice "TOMCAT_CPU_USAGE\t->\t$cpuUsage%"
				aa=`expr $cpuUsage \>\= $usage`	# 如果第一个值大于等于第二个值，则输出1，否则输出0.
			fi
		done
	fi

	eexit 0
}

main(){
	isSelfOn   #需要先执行这个，检测pid，写pid
	checkMe
	checkTomcat
	eexit 0
}

main
