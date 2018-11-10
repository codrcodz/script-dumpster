#!/usr/bin/env bash
#
### Name: disk_alert_crusher.sh
### Author: Cody Lee Cochran <cody.cochran@rackspace.com>
#
### Description:
# This script is designed to crush/self-heal nuisance alerts.
# The script covers alerts for /var/log, /var/log/audit, and /tmp.
#
## For /var/log/audit and /tmp:
# Before working with the main /var/log directory,
# some preliminary clean-up is done to make room to work on /var/log.
# Sometimes, this is enough (by itself) to heal the alert.
# See the Make_space_to_work() function below for more details.
#
## For /var/log:
# This script is designed to be a fallback for logrotate,
# or other logging-rotate mechanisms. When executed via cronjob/zabbix,
# the script will check the disk space of the partition hosting
# /var/log, and if it reaches a threshold, it will clean-up the
# files located in /var/log until space is back below the threshold.
# If the script takes action, it logs it's activities to let admins
# know which log files it deleted or truncated. It's log can then
# be monitored for changes, and log-rotate policies can be tweaked
# to prevent the script from having to take action on the server.
#
#
################################################################################
### PROGRAM DEFINITIONS
################################################################################

# Sets the log_dir_partition variable
# This variable let the script know what partition /var/log is hosted on
Set_var_log_dir_partition() {
    var_log_dir_partition="$( \
                              df /var/log \
                              | grep -oP "(?<=(%\s))/.*" \
                            )"
}

# Sets the disk_status variable
# This variable lets the script know if the disk usage threshold has been met
# This can be fed ${1} to adjust the threshold disk usage; else default is used
Set_disk_status() {
  disk_usage_percent="$( \
                         df -h ${var_log_dir_partition} \
                         | grep -oP "(?<=(\s))[0-9]+(?=(%))" \
                       )"
  if [[ "${disk_usage_percent}" -lt "${1:-83}" ]]; then
    disk_status="low"
  else
    disk_status="not_low"
  fi
}


Check_disk_status() {
  if [[ "${disk_status}" == "not_low" ]]; then
    exit 0
  fi
}

# Before cleaning up the log directories, we first need to make working space.
# If we don't, gzip might fail to compress old logs.
# First, we clear the package manager cache.
# Second, we clear /tmp of files that have not been touched today.
# Lastly, we rotate the auditd logs.
Make_space_to_work() {
  yum clean all || apt-get clean;
  find /tmp \
    -type f \
    -mtime +1 \
    -delete;
  service auditd rotate;
}

# Initiates a logrotate using configs/policies in the default locations.
Gracefully_rotate_logs() {
  logrotate -f /etc/logrotate.conf;
}

# This finds *.log[something] files and compresses them.
# Some programs rename-to-rotate their logs without compressing them.
# This step is intended to address those logs exclusively.
Compress_old_rotated_logs() {
    find /var/log \
      -type f \
      -regextype egrep \
      -regex ".*\.log?.*" \
      -mtime +${days_ago_of_last_mod} \
      -exec gzip '{}' \; \
      -printf "$(date --rfc-3339='seconds' 2>/dev/null || date) " \; \
      -exec echo "[COMPRESSED] /var/log: '{}'" \; \
      >> /var/log/disk_disk_alert_crusher.log \
    && Set_disk_status \
    && Check_disk_status;
}

# Removes logs from /var/log ending in "z" or "z" + plus a number (i.e. bz2).
# Uses mtime (time last modified) to step down from 30 days down to 7 days.
# It rechecks space on the partition; stopping the loop if space is good again.
# This is intended to be executed only after/if rotation & compression fails.
Remove_compressed_logs() {
  for days_ago_of_last_mod in {30..0}; do
    find /var/log \
      -type f \
      -mtime +${days_ago_of_last_mod} \
      -regextype egrep \
      -regex ".*log.*\.(z[0-9]*$)" \
      -delete \
      -printf "$(date --rfc-3339='seconds' 2>/dev/null || date) " \; \
      -exec echo "[DELETED] /var/log: '{}'" \; \
      >> /var/log/disk_alert_crusher.log \; \
    && Set_disk_status \
    && Check_disk_status;
  done
}

# This truncates ".log" files by temp storing the last 1000 lines in memory.
# It stores the last 1000 lines; empties the file; then appends the 1000 lines.
# This is intended to be executed only after/if other steps fail to work.
Remove_uncompressed_logs() {
  find /var/log \
    -type f \
    -name "*log" \
    -print \
    | while read log_file; do
        { \
          type mapfile &>/dev/null \
          && mapfile < <(tail -n 1000 ${log_file}) \
          && echo \
               "$( \
                   date --rfc-3339='seconds' 2>/dev/null || date \
                 ) [TRUNCATED] '${log_file}'" \
             >> /var/log/disk_alert_crusher.log \
          && > ${log_file} \
          && for line in ${MAPFILE[@]}; do
              echo "${line}" >> ${log_file};
            done;
        } \
        || \
        { \
          > ${log_file} \
          && echo \
               "$( \
                   date --rfc-3339='seconds' 2>/dev/null || date \
                 ) [DELETED] '${log_file}'" \
             >> /var/log/disk_alert_crusher.log \
        } \
    done
}

################################################################################
### PROGRAM EXECUTION
################################################################################

Make_space_to_work \
&& Set_log_dir_partition \
&& Set_disk_status \
&& for function in \
     Gracefully_rotate_logs \
     Compress_old_rotated_logs \
     Remove_compressed_logs \
     Remove_uncompressed_logs \
     ;
   do \
     Set_disk_status \
     && Check_disk_status;
     ${function} ${1};
   done
