#!/bin/bash

# if username and password were not provided, exit.
# otherwise, create the user, add to groups, and modify file system permissions
if [[ -z $CONTAINER_USER_USERNAME ]] || [[ -z $CONTAINER_USER_PASSWORD ]];
then
      exit 1
else
    groupadd rstudio-users

    useradd $CONTAINER_USER_USERNAME \
	&& mkdir /home/${CONTAINER_USER_USERNAME} \
	&& chown ${CONTAINER_USER_USERNAME}:${CONTAINER_USER_USERNAME} /home/${CONTAINER_USER_USERNAME} \
	&& chown ${CONTAINER_USER_USERNAME}:${CONTAINER_USER_USERNAME} /HostData \
	&& addgroup ${CONTAINER_USER_USERNAME} staff \
	&& echo "$CONTAINER_USER_USERNAME:$CONTAINER_USER_PASSWORD" | chpasswd \
	&& adduser ${CONTAINER_USER_USERNAME} sudo \
	&& chsh -s /bin/bash ${CONTAINER_USER_USERNAME}

    usermod -a -G rstudio-users $CONTAINER_USER_USERNAME
fi

# ACCEPT_EULA needs to be set to 'Y'
# and SA_PASSWORD needs to be not null (actually needs to pass complexity requirements, but not testing here)
# to run SQL Server
if [[ $ACCEPT_EULA == "Y" && ! -z $SA_PASSWORD ]]
then
	export MSSQL_SA_PASSWORD=$SA_PASSWORD
	runuser -m -p  mssql -c '/opt/mssql/bin/sqlservr  --accept-eula --reset-sa-password &'
		
	# make the SA password available to all users
	echo "SA_PASSWORD=\"$SA_PASSWORD\"" >> /etc/environment
	echo "SA_PASSWORD=\"$SA_PASSWORD\"" >> /usr/local/lib/R/etc/Renviron.site
fi

# start sshd
/usr/sbin/sshd -D &

# rocker/shiny runs this by default
/init
