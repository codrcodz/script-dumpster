kernel_version="$(uname -r 2>/dev/null)"; \
os_release="$(grep -oP "(?<=(el))." <<<${kernel_version} )"; \
header(){ \
  printf "\n\n----------\n"; \
  printf "%s" "${1}"; \
  printf "\n----------\n\n"; \
}; \
printf "\n=============================\n"; \
printf "Reboot Checks for:\n"; \
hostname; \
printf "============================="; \
header "Kernel Version:";\
printf "${kernel_version}\n"; \
header "Listening Services:"; \
netstat -plunt \
| tail -n +3 \
| while read protocol _ _ ip_and_port _ pid_and_prog; do \
    printf "${pid_and_prog##*/} "; \
    printf "${ip_and_port}/${protocol}\n"; \
done \
| sort; \
header "Running Services Not Enabled at Boot (if any):"; \
if [[ ${os_release} != "7" ]]; then
  for service in $(chkconfig --list \
             | grep 3:off \
             | awk '{print $1}'); do \
    service ${service} status 2>&1 \
    | egrep -i '(running$|running\.\.\.)' \
    | egrep -i -v 'not running' \
    | while read status; do \
        printf "${service}:\n${status}\n\n"; \
    done;
  done; \
else \
  for service in $( \
                     systemctl list-units --type=service --state=running 2>/dev/null \
                     | grep -oP ".*\.service.*?(?=(\s))" \
                     | egrep -v "@"
                  ); do \
    printf "${service}: "; \
    systemctl is-enabled ${service} 2>/dev/null; \
  done \
  | grep "disabled"; \
fi; \
header "Services in a Failed State (if any):"; \
if [[ ${os_release} == "7" ]]; then \
  systemctl list-unit-files --type=service --state=failed 2>/dev/null \
  | grep -oP "[[:alnum:]_-]+\.service(?=(\s))"; \
fi; \
header "File System Check (fsck) Counts on ext Filesystems:"; \
for partition in $( \
                     mount \
                     | grep -oP "^/dev/.*?(?=(\s.*ext))" \
                  ); do \
  printf "\n${partition}:\n$( \
                               tune2fs -l ${partition} \
                               | egrep -i "mount count" \
                            )\n"; \
done; \
header "Cluster Configuration:"; \
if [ ! -e "/etc/cluster/cluster.conf" ]; then \
  printf "Clustering Not Configured\n"; \
else \
  printf "\nCluster Config:\n$(cat /etc/cluster/cluster.conf 2>/dev/null)\n"; \
  printf "Cluster Daemons Running (if any):\n"; \
  netstat -plnt \
  | egrep -i "(ricci|luci|modclusterd|rgman|cman|clvm)"; \
fi; \
header "File System Table Syntax Errors:"; \
mount -a 2>&1 >/dev/null; \
if [[ "${?}" == "0" ]]; then \
  printf "No Syntax Errors in /etc/fstab"; \
else \
  printf "\x1b[31mSyntax errors in /etc/fstab; DO NOT REBOOT\x1b[0m"; \
fi; \
header "NFS Exports:"; \
if [ -z "$(cat /etc/exports 2>/dev/null)" ]; then \
  printf "No NFS Exports Configured\n"; \
else \
  printf "\n$(cat /etc/exports)\n"; \
fi; \
header "NFS Mounts:"; \
if [ -z "$(cat /etc/fstab \
           | grep ':' \
           | grep -vP "^\s*#")" ]; then \
  printf "No NFS Mounts Configured\n"; \
else \
  cat /etc/fstab | grep ':'; \
fi; \
header "MySQL/MariaDB Status Checks:"; \
printf "Service Status:\n"; \
if [[ ${os_release} != "7" ]]; then \
  service mysqld status 2>&1; \
else \
  systemctl status mariadb 2>&1; \
fi; \
for i in {Master,Slave}; do \
  if [[ -n $(echo "show $i status" | mysql 2>&1 | grep "ERROR") ]]; then \
    printf "MySQL Login Error\n"; \
  elif [[ -z $(echo "show $i status" | mysql 2>&1 | grep -v "ERROR") ]]; then \
    printf "\n$i Status:\nNot configured as MySQL replication $i\n"; \
  else \
    printf "\n$i Status:\n$(echo "show $i status\G" | mysql  2>&1 )\n"; \
  fi; \
done; \
header "sssd Status Checks:"; \
printf "sssd Config Errors (if any):\n"; \
sssd --genconf 2>&1 \
| egrep ".*"; \
header "Postfix Status Checks:"; \
printf "Postfix Config Errors (if any):\n"; \
postfix check 2>&1; \
header "nginx Status Checks:"; \
printf "Config File Syntax Check:\n"; \
nginx -t 2>&1; \
header "httpd Status Checks:"; \
printf "httpd Config File Syntax Check:\n"; \
httpd -t 2>&1; \
printf "\nService Status:\n"; \
if [[ ${os_release} != "7" ]]; then \
  service httpd status 2>&1; \
else \
  systemctl status httpd 2>&1; \
fi; \
if [[ "${?}" == "0" ]]; then \
  header "Site Statuses:"; \
  if [ -z $(httpd -S 2>&1 \
            | grep "namevhost" \
            | awk '{print $4}' \
            | head -n1) ]; then \
    printf "\nNo vhosts appear to be configured;\n"; \
    printf "below is raw output of the VirtualHost configuration check:\n\n"; \
    printf "$(httpd -S 2>&1 \
              | egrep -v "^Syntax OK")\n\n"; \
  else \
    printf "\n"; \
    for site in $(httpd -S 2>&1 \
                  | grep "namevhost" \
                  | awk '{print $4}' \
                | sort -u); do \
      printf "\nSite: $site\n"; \
      if [ -z "$(curl -IL $site 2>/dev/null)" ]; then \
        printf "Site Down\n--\n"; \
      else \
        printf "$(curl -I $site 2>/dev/null)\n"; \
      fi; \
    done \
    | egrep -A1 "^Site:"; \
  fi; \
fi; \
if [[ "${UID}" != "0" ]]; then \
  printf "\x1b[31m\nMust be run as root to generate valid output\x1b[0m\n\n"; \
else \
  printf "\n";
fi;
