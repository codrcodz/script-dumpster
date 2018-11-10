#!/bin/bash
# In a nutshell, this script was originally just a huuuge one-liner that I used to run pre/post reboot checks.
#
# Note: This broken out version has not been very well tested, please see gist for one-liner, better-tested version:
# http://bit.ly/2lH0rkT
#
# It prints out diagnostic information about mounts, NFS, mysql clustering, httpd, etc.
# If the server has unique settings or a unique environment, this can help you readily identify that before a reboot.
# It helps you find "gotchas" like services that are currently running, but aren't chkconfiged on.
# The script primarily run checks on the LAMP stack and is RHEL6-centric.
# Most importantly, it gives you a good snapshot of what the server looks like before and after a reboot.
# If something goes haywire after the server comes back up, you can use the output of this script to see what changed.

# Output header
printf "\n====================\nPre-reboot Checks\n====================\n";

# The "br" variable stores a seperator used between each diagnostic section in the script's output.
br='\n----------\n'; 

# The File System Check finds all the mounts, and tells you if anything is due for a fsck at next reboot.
# When a system runs a file system check, it can add several minutes to boot time, which may be unacceptable.
printf "${br}File System Check (fsck) Counts:${br}\n";
for 
  partition in $(mount | awk '{print $1}' | grep '/dev/');
do 
  printf "$partition:\n $(tune2fs -l $partition | egrep -i "mount count")\n\n";
done;

# The Cluster Configuration checks to see if the server is part of a MySQL cluster.
# If it is, the mysql services should be moved to another node in the cluster prior to rebooting.
printf "${br}Cluster Configuration:${br}";
if 
  [ -z "$(cat /etc/cluster/cluster.conf 2>/dev/null)" ];
then 
  printf "\nClustering Not Configured\n\n"; 
else 
  printf "\nCluster Config:\n$(cat /etc/cluster/cluster.conf 2>/dev/null)\n\n"; 
  printf "Cluster Daemons Running (if any):\n";
  netstat -plnt | egrep -i "(ricci|luci|modclusterd|rgman|cman|clvm)";
  printf "\n";
fi;

# The NFS Exports section checks to see if this server is configured to serve part of it's file system to others.
# This can be an issue if you do not know about it before hand, because a reboot will cause an interruption in NFS service.
printf "${br}NFS Exports:${br}";
if 
   [ -z "$(cat /etc/exports)" ];
then 
  printf "\nNo NFS Exports Configured\n\n";
else 
  printf "\n$(cat /etc/exports)\n\n";
fi;

# This complementary check finds an NFS mounts that this server relies on.
# It is important to ensure that /etc/fstab instructs the bootloader to skip these if it can not mount them at boot.
# Even though the server's performance would likely be degraded without the NFS mount, it is better than it hanging on boot.
printf "${br}NFS Mounts:${br}";
if 
  [ -z "$(cat /etc/fstab | grep ':' | egrep -v "^#")" ];
then 
  printf "\nNo NFS Mounts Configured\n\n";
else
  printf "\n$(cat /etc/fstab | grep ':')\n\n";
fi;

# This check parses a list of all running services and find those that are NOT set to start at boot.
# Sometimes custom Java applications or other non-LAMP stack server configs do not have init files and must be manually restarted.
# It is useful to know how to perform this manual restart beforehand; you can usefully figure it  out by seeing the running daemons.
printf "${br}Running Services Not Chkconfiged On (if any):${br}\n";
for 
  i in $(chkconfig --list | grep 3:off | awk '{print $1}'); 
do 
  service $i status 2>&1 \
  | egrep -i '(running$|running\.\.\.)' \
  | egrep -i -v 'not running' \
  | while 
      read status;
    do 
      printf "$i:\n$status\n\n";
    done; 
done; 

# This checks to see if MySQL is running just before/after reboot, and also checks the replication status.
# Nodes found to be part of a replication config should have both the master and slave checked after reboot.
printf "\n";
printf "${br}MySQL Status Checks:${br}";
printf "\n$(service mysqld status 2>&1)\n\n";
for
  i in {Master,Slave};
do 
  if 
    [[ -n $(echo "show $i status" | mysql 2>&1 | grep "ERROR") ]];
  then
    printf "MySQL Login Error\n";
  elif 
    [[ -z $(echo "show $i status" | mysql 2>&1 | grep -v "ERROR") ]];
    then 
      printf "\n$i Status:\nNot configured as MySQL replication $i\n";
    else
       printf "\n$i Status:\n$(echo "show $i status\G" | mysql  2>&1 )\n";
    fi;
done;

# This check is great for some of the more subtle things that can occur after a reboot.
# It returns the URL and http status code for each site hosted on the server.
# Sometimes subtle config changes are lying dormaint in the config files like httpd.conf or my.cnf files.
# These minor changes may have dramatic effects on the LAMP stack sites when they take effect after a reboot.
# Ruling out major changes via the other checks, and having before/after data helps you quickly rule out common issues.
# Ruling out any of the "usual suspects" help you dig into the config files more quickly and fix httpd/mysql config issues.
# It is also useful to ID if the change affected all sites, or just some; this narrows down where the config change was made.
printf "\n";
printf "${br}httpd Status Checks:${br}\n$(service httpd status)\n\n$(httpd -t 2>&1)\n";
printf "\n";
printf "${br}Site Statuses:${br}";
if 
  [ -z $(httpd -S 2>&1 | grep "namevhost" | awk '{print $4}' | head -n1) ];
then
  printf "\nNo vhosts appear to be configured;\nbelow is raw output of the VirtualHost configuration check:\n\n$(httpd -S 2>&1 | egrep -v "^Syntax OK")\n\n";
else 
  printf "\n";
  for 
    site in $(httpd -S 2>&1 | grep "namevhost" | awk '{print $4}' | sort | uniq);
  do 
    printf "\nSite: $site\n";
    if 
      [ -z "$(curl -IL $site 2>/dev/null)" ];
    then
      printf "Site Down\n--\n";
    else
      printf "$(curl -I $site 2>/dev/null)\n";
    fi;
  done \
  | egrep -A1 "^Site:";
fi;

printf "\n"
