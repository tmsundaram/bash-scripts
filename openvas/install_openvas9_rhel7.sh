#########################################################################################################################
#Description: Downlaod Openvas v9 source codes with dependancy codes. Compile install Openvas v9 on RHEL 7.5.           #
#Features: Complete isolated source code installation. Target directory can be specified. Example - /mnt/scans/openvas  #
#Supported OS: RHEL 7.5 or higher                                                                                       #
#Written by: TMSundaram                                                                                                 #
#Date: 20180612                                                                                                         #
#########################################################################################################################

#!/bin/bash
#set -x
ERROR_EXIT() {
	echo "Fix the above error and rerun the script. Check $BUILD_LOG for more info. Exiting as ERROR occurred"
	exit 1
}

status_check() {
	if [ "$?" == "0" ]; then
		echo "success: $1"
	else
		echo "failed: $1"
		ERROR_EXIT
	fi
}

check_failure() {
	if [ $? -ne "0" ]; then
		return 1
	fi
}

add_repo() {
	cd ${OPENVAS_DOWNLOAD_DIR}
	wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	yum install -y epel-release-latest-7.noarch.rpm
}

install_deps_yum() {
	echo "Installing OS base dependancy packages through Yum"
	yum install wget -y >> $BUILD_LOG 2>&1 
	status_check "Install wget"
	add_repo >> $BUILD_LOG 2>&1
	status_check "add extra packages repo"
	yum groupinstall "Development tools" -y >> $BUILD_LOG 2>&1
	status_check "Install developemt tools"
	#yum install libusb1-devel qt-devel libtool qt5-qtbase perl-JSON ncurses-devel libdb-devel texinfo popt-devel glib2-devel mingw32-gcc openssl-devel libuuid-devel libsqlite3x-devel gnutls-utils gnutls-devel hiredis-devel wget -y
	yum install libusb1-devel qt-devel libtool qt5-qtbase perl-JSON ncurses-devel libdb-devel texinfo popt-devel glib2-devel mingw32-gcc openssl-devel libuuid-devel gnutls-utils gnutls-devel hiredis-devel -y >> $BUILD_LOG 2>&1
	status_check "Install mandatory deps 1/2"
	yum install xmltoman texlive-collection-fontsrecommended texlive-collection-latexrecommended texlive-comment -y >> $BUILD_LOG 2>&1
	status_check "Install mandatory deps 2/2"
}

url_status_check() {
			if [ "$?" != "0" ]; then
				echo $1 >> $ERR
			fi
		}

download_extract_codes() {
	ERR=/tmp/openvas_links && cat "/dev/null" > $ERR
	SOURCE_CODE_URL="/tmp/openvas_code_url"

	cd ${OPENVAS_DOWNLOAD_DIR}
cat > ${SOURCE_CODE_URL} << TEXT
	http://download.redis.io/redis-stable.tar.gz
	http://www.h5l.org/dist/src/heimdal-7.1.0.tar.gz
	https://github.com/greenbone/openvas-smb/archive/v1.0.3.tar.gz
	https://cmake.org/files/v3.6/cmake-3.6.2-Linux-x86_64.tar.gz
	https://git.libssh.org/projects/libssh.git/snapshot/master.tar.gz
	https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.31.tar.bz2
	https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.8.2.tar.bz2
	https://www.gnupg.org/ftp/gcrypt/libksba/libksba-1.3.5.tar.bz2
	https://www.gnupg.org/ftp/gcrypt/libassuan/libassuan-2.5.1.tar.bz2
	https://www.gnupg.org/ftp/gcrypt/npth/npth-1.5.tar.bz2
	https://www.gnupg.org/ftp/gcrypt/gnupg/gnupg-2.2.7.tar.bz2
	https://www.gnupg.org/ftp/gcrypt/gpgme/gpgme-1.11.1.tar.bz2
	http://www.tcpdump.org/release/libpcap-1.8.1.tar.gz
	https://github.com/greenbone/gvm-libs/releases/download/v9.0.2/openvas-libraries-9.0.2.tar.gz
	https://github.com/greenbone/openvas-scanner/archive/v5.1.2.tar.gz
	https://github.com/greenbone/gvm/releases/download/v7.0.3/openvas-manager-7.0.3.tar.gz
	http://wald.intevation.org/frs/download.php/2397/openvas-cli-1.4.5.tar.gz
	https://www.sqlite.org/2018/sqlite-autoconf-3230100.tar.gz
	http://ctan.mirrors.hoobly.com/macros/latex/contrib/titlesec.zip
	http://ctan.mirrors.hoobly.com/macros/latex/contrib/changepage.zip
	https://nmap.org/dist/nmap-7.70.tar.bz2
TEXT

	echo "Downloading Source codes to ${OPENVAS_DOWNLOAD_DIR}" >> $BUILD_LOG 2>&1
	for i in `cat ${SOURCE_CODE_URL}`
	do
		wget $i >> $BUILD_LOG 2>&1
		url_status_check $i
	done

	if [ -s ${ERR} ]; then
		echo -e "failed to download packages from following URL\n`cat ${ERR}`"
		ERROR_EXIT
	else
		find ${OPENVAS_DOWNLOAD_DIR} -name "*.tar.gz" -exec tar -xzf {} \; >> $BUILD_LOG 2>&1
		find ${OPENVAS_DOWNLOAD_DIR} -name "*.tar.bz2" -exec tar -xjf {} \; >> $BUILD_LOG 2>&1
		find ${OPENVAS_DOWNLOAD_DIR} -name "*.zip" -exec unzip {} \; >> $BUILD_LOG 2>&1
	fi
}

add_popt.pc () {
cat > /usr/lib64/pkgconfig/popt.pc << EOT
prefix=/usr
exec_prefix=${prefix}
libdir=/usr/lib64
includedir=${prefix}/include

Name: popt
Version: 1.13
Description: popt library.
Libs: -L${libdir} -lpopt
Cflags: -I${includedir}
EOT
}

install-redis() {
	cd ${OPENVAS_DOWNLOAD_DIR}/redis-stable
	make && make install
	mkdir -p /etc/redis /var/redis/redis-server
	cp utils/redis_init_script /etc/init.d/redis-server
	cp redis.conf /etc/redis/
	sed  -i '/REDISPORT=/c \REDISPORT=redis\nREDISSOCK=/tmp/redis.sock'  /etc/init.d/redis-server
	sed -i '/$CLIEXEC -p $REDISPORT shutdown/c\$CLIEXEC -s $REDISSOCK shutdown' /etc/init.d/redis-server
	sed -i '/PIDFILE=/c\PIDFILE=/var/run/redis.pid' /etc/init.d/redis-server
	sed -i '/^pidfile /c\pidfile /var/run/redis.pid' /etc/redis/redis.conf
	sed -i '/^daemonize/c \daemonize yes' /etc/redis/redis.conf
	sed -i '/^port /c\port 0' /etc/redis/redis.conf
	sed -i '/^logfile /c\logfile /var/log/redis-server.log' /etc/redis/redis.conf
	sed -i '/^dir/c\dir /var/redis/redis-server' /etc/redis/redis.conf
	echo "unixsocket /tmp/redis.sock" >> /etc/redis/redis.conf
	/etc/init.d/redis-server start
}

install_dep_libs() {
	cd ${OPENVAS_DOWNLOAD_DIR}
	DIR_NAMES="heimdal-7.1.0 libgpg-error-1.31 libgcrypt-1.8.2 libksba-1.3.5 libassuan-2.5.1 npth-1.5 gnupg-2.2.7 gpgme-1.11.1 libpcap-1.8.1 sqlite-autoconf-3230100"
	for i in $DIR_NAMES
	do
		LIB_NAME="$i"
		if [ -d "$LIB_NAME" ]; then
			    echo "*****------working on directory $LIB_NAME " | tee -a $BUILD_LOG
				cd $i >> $BUILD_LOG 2>&1
				mkdir build >> $BUILD_LOG 2>&1
				cd build >> $BUILD_LOG 2>&1
				../configure --prefix=${OPENVAS_HOME} >> $BUILD_LOG 2>&1
				check_failure
				make >> $BUILD_LOG 2>&1
				check_failure
				make install >> $BUILD_LOG 2>&1
				check_failure
				cd ${OPENVAS_DOWNLOAD_DIR}
		else
				false
				status_check "read source code directory $LIB_NAME"
		fi
	done
	LIB_NAME="first set of libs"
	ln -s ${OPENVAS_HOME}/include ${OPENVAS_HOME}/include/heimdal
}

get_cmakev3() {
	cd ${OPENVAS_DOWNLOAD_DIR}
	cp -rp cmake-3.6.2-Linux-x86_64/bin/* ${OPENVAS_HOME}/bin/ >> $BUILD_LOG 2>&1
	status_check "Install latest cmake v3"
	cp -rp cmake-3.6.2-Linux-x86_64/share/* ${OPENVAS_HOME}/share/
	export CMAKECMD="${OPENVAS_HOME}/bin/cmake"
}

install_openvas() {
	cd ${OPENVAS_DOWNLOAD_DIR}
	C_DIR_NAMES="master openvas-smb-1.0.3 gvm-libs-9.0.2 openvas-scanner-5.1.2 gvm-7.0.3 openvas-cli-1.4.5"
	for i in $C_DIR_NAMES
	do
		PACKAGE_NAME="$i"
		if [ -d "$PACKAGE_NAME" ]; then
				echo "*****------working on directory $PACKAGE_NAME"
				cd $PACKAGE_NAME 
				mkdir build
				cd build
				$CMAKECMD -DCMAKE_INSTALL_PREFIX=${OPENVAS_HOME} -DCMAKE_INSTALL_RPATH=${OPENVAS_HOME}/lib .. >> $BUILD_LOG 2>&1
				check_failure
				make  >> $BUILD_LOG 2>&1
				check_failure
				make install >> $BUILD_LOG 2>&1
				check_failure
				make rebuild_cache >> $BUILD_LOG 2>&1
				check_failure
				ldconfig
				cd ${OPENVAS_DOWNLOAD_DIR}
		else
				false
				status_check "read source code directory $PACKAGE_NAME"
		fi
	done
	PACKAGE_NAME="second set of libs"
}

install_nmap() {
	cd ${OPENVAS_DOWNLOAD_DIR}/nmap-7.70
	./configure --prefix=/mnt/SecScans/openvas --with-libpcap=/mnt/SecScans/openvas >> $BUILD_LOG 2>&1
	check_failure
	make >> $BUILD_LOG 2>&1
	check_failure
	make install >> $BUILD_LOG 2>&1
}

openvas_feed_sync() {
	echo "PATH=${OPENVAS_HOME}/bin:${OPENVAS_HOME}/sbin:\$PATH" >> $HOME/.bash_profile
	greenbone-nvt-sync
	greenbone-scapdata-sync
	greenbone-certdata-sync
	openvas-manage-certs -a
}

create_omp_conf() {
	PASSWD=`openvasmd --create-user=admin --role=Admin|awk -F "'" '{print $2}'`
	if [ "$?" == "0" ]; then
	cat > $HOME/omp.config << EOT
[Connection]
port=9390
username=admin
host=localhost
EOT
	echo "password=$PASSWD" >> $HOME/omp.config
	else
		echo "warning: openvas user admin exist already. Not setting up connetion settings" |tee -a $BUILD_LOG
	fi
}

start-openvas-services() {
	openvassd
	while [ "$X" == "0" ]
	do
		sleep 30
		ps -ef |grep openvassd |grep "incoming connections"
		if [ "$?" == "0" ]; then
			X=1
		fi
	done
	openvasmd --rebuild --progress
	openvasmd -a 127.0.0.1 -p 9390
}

openvas_service_status() {
	ps -C openvassd
	  if [ "$?" == "0" ]; then
	  	 echo "OPenvas scanner running"
	  	 ps -C openvasmd
	  	 if [ "$?" == "0" ]; then
	  	 	echo "OPenvas manager service running"
	  	 else
	  	 	echo "failed to start openvas-manager"
	  	 	exit 1
	  	 fi
	  else
	  	 echo "failed to start OPenvas scanner"
	  	 exit 1
	  fi
}

install_pdf_report_deps() {
	if [ -d "${OPENVAS_DOWNLOAD_DIR}/titlesec" ]; then
		cd ${OPENVAS_DOWNLOAD_DIR}/titlesec
		mkdir -p /usr/share/texlive/texmf-local/tex/latex/titlesec
		cp *.{sty,tss,def} /usr/share/texlive/texmf-local/tex/latex/titlesec/
		if [ "$?" -eq "0" ]; then
			true && status_check "texlive dependancy titlesec install"
			if [ -d "${OPENVAS_DOWNLOAD_DIR}/changepage" ]; then
				cd ${OPENVAS_DOWNLOAD_DIR}/changepage
				latex changepage.ins >> $BUILD_LOG 2>&1
				mkdir -p /usr/share/texlive/texmf-local/tex/latex/chngpage/
				cp *.sty /usr/share/texlive/texmf-local/tex/latex/chngpage/
				status_check "texlive dependancy changepage install"
			else
				false
				status_check "read source directory - texlive changepage"
			fi
		else
			false
			status_check "texlive dependancy titlesec install"
		fi
	else
		false
		status_check "read source directory - texlive titlesec"
	fi
}

main() {
	export LC_ALL=en_US.UTF-8
	export OPENVAS_DOWNLOAD_DIR=/mnt/SecScans/Downloads/Openvas
	export OPENVAS_HOME=/mnt/SecScans/openvas
	if [ -d ${OPENVAS_DOWNLOAD_DIR} ]; then
		rm -rf ${OPENVAS_DOWNLOAD_DIR}
	fi
	mkdir -p ${OPENVAS_HOME} ${OPENVAS_DOWNLOAD_DIR}/logs
	export BUILD_LOG=${OPENVAS_DOWNLOAD_DIR}/logs/openvas_build_log

	###Ready to go, starting
	echo "Starting with OPenvas v9 Installation - It may take 30mins or even more depends on system performance"
	install_deps_yum
#		status_check "Install OS base dependancy through yum."
	download_extract_codes
		status_check "download & extract source codes"
	add_popt.pc >> $BUILD_LOG 2>&1
		status_check "add popt conf files"
	install-redis >> $BUILD_LOG 2>&1
		status_check "Install and confiugre redis"
	export C_INCLUDE_PATH="${OPENVAS_HOME}/include"
	export PKG_CONFIG_PATH=${OPENVAS_HOME}/lib/pkgconfig:$PKG_CONFIG_PATH
	export PATH=${OPENVAS_HOME}/bin:${OPENVAS_HOME}/sbin:$PATH
	export LIBRARY_PATH="${OPENVAS_HOME}/lib"
	export LD_LIBRARY_PATH="${OPENVAS_HOME}/lib"
	export LD_RUN_PATH="${OPENVAS_HOME}/lib"
	export CFLAGS="-L${OPENVAS_HOME}/lib -I${OPENVAS_HOME}/include"
	export CC="gcc -Wl,-rpath -Wl,${OPENVAS_HOME}/lib"
	echo -e "${OPENVAS_HOME}/lib" > /etc/ld.so.conf.d/openvas.conf
	install_pdf_report_deps
	echo "Starting source code installation"
	install_dep_libs
		status_check "Source install $LIB_NAME"
	get_cmakev3 >> $BUILD_LOG 2>&1
		status_check "configure required version of cmake"
	install_openvas
		status_check "Source install $PACKAGE_NAME"
	install_nmap
		status_check "Source install latest nmap"
	echo "Gettng latest NVT's from feed"
	openvas_feed_sync >> $BUILD_LOG 2>&1
	echo "Starting Openvas services"
	start-openvas-services >> $BUILD_LOG 2>&1
	create_omp_conf
	openvas_service_status
}

echo "********************" | tee -a $BUILD_LOG
date | tee -a $BUILD_LOG
main
echo "********************" | tee -a $BUILD_LOG
