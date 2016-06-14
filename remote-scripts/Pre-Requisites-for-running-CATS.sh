#!/bin/bash
logfile="$HOME/Pre-Requisites-for-running-CATS.log"
fifofile=test.fifo

if [ -e $logfile ]; then
        rm -f $logfile
fi

if [ -e $fifofile ]; then
        rm -f $fifofile
fi


#save output to a log file
mkfifo $fifofile
cat $fifofile | tee $logfile &
exec 1>$fifofile
exec 2>&1

PackageInstall()
{
	if [[ `command -v $1` == *$1  ]]; then
		echo "$1 has been installed, skip it"
	else	
		sudo apt-get install $1 -y
		if [ $? -eq 0 ]; then
			echo "$1 install successful" 
		else
			echo "ERROR: $1 failed to install" 
			exit 1
		fi
	fi
}

#1. Install and config GO
echo '1. Start to download and install GO' 
if [ -e /usr/local/go/bin ]; then
	echo 'GO has been installed, skip it' 
else
	wget https://storage.googleapis.com/golang/go1.6.2.linux-amd64.tar.gz -nv
	if [ $? -eq 0 ]; then
		sudo tar -C /usr/local -xzf go1.6.2.linux-amd64.tar.gz
		if [ $? -eq 0 ]; then
			echo 'Start to config GO environment variable' 
				if [ -e $HOME/work ]; then
					rm -rf $HOME/work
				fi
				mkdir $HOME/work
				echo "export GOPATH=$HOME/work" >> $HOME/.profile
				echo "export PATH=$PATH:/usr/local/go/bin:$HOME/work/bin" >> $HOME/.profile
				source $HOME/.profile
				if [ $? -eq 0 ]; then
					echo 'config GO environment variable successful' 
				else
					echo 'ERROR: fail to config GO environment variable' 
					exit 1
				fi
		fi

	else
		echo 'ERROR: GO package failed to download, please check!' 
		exit 1
	fi
fi


#2. Install git and curl
echo "2. Start to install git and curl"
PackageInstall git
PackageInstall curl

#3. Install CF-CLI
echo "3. Start to download and install cf-cli" 	
if [[ `command -v cf` == *cf  ]]; then
	echo "cf-cli has been installed, skip it" 
else
	wget -O cf-cli.deb https://cli.run.pivotal.io/stable?release=debian64 -nv
	sudo dpkg -i cf-cli.deb
	if [ $? -eq 0 ]; then
		echo "cf-cli install successful" 
	else
		echo "ERROR: cf-cli failed to install with error code $?" 
		exit 1
	fi
fi

#4. Check out a copy of cf-acceptance-tests and Ensure all submodules are checked out to the correct SHA
echo "4. Check out cf-acceptance-tests"
go get -d github.com/cloudfoundry/cf-acceptance-tests
if [ $? -eq 0 ]; then
	cd $GOPATH/src/github.com/cloudfoundry/cf-acceptance-tests/
	./bin/update_submodules	
else
	echo "ERROR: Failed to check out cf-acceptance-tests with error code $?" 
	exit 1
fi

#5. install gvt
echo "5. Install gvt"
go get -u github.com/FiloSottile/gvt

#6. Test Configuration
echo "6. Configurate test json file"
cd $HOME
if [ -e settings ]; then
	IP=`cat settings | grep cf-ip | awk '{print $2}' | awk '{split($0,b,"\"");print b[2]}'`
	cat > integration_config.json <<EOF
	{
		  "api": "api.$IP.xip.io",
		  "admin_user": "admin",
		  "admin_password": "c1oudc0w",
		  "apps_domain": "$IP.xip.io",
		  "skip_ssl_validation": true,
		  "use_http": false
	}
EOF
	echo "export CONFIG=$PWD/integration_config.json" >> $HOME/.profile
	echo "Successful to prepared pre-requisites for running CATS" 
	exit 0
else
	echo "ERROR: The file 'settings' don't exist" 
	exit 1
fi
