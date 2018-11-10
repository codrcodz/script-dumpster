#!/usr/bin/env bash
#
### Name: jenkins-slack-notifier.sh
### Author: Cody Lee Cochran <cody.cochran@rackspace.com>
#
### Description:
# This script is designed to notify a Slack channel,(via email integration),
# whenever the partition hosting the Jenkins workspace is near full (84% usage).
#
#
################################################################################
### PROGRAM DEFINITIONS
################################################################################

set -x

# Set the notification email provided by the Slack-email plugin
# The plugin provides a unique address for each channel
# https://get.slack.help/hc/en-us/articles/206819278-Send-emails-to-Slack
#
Set_slack_notification_email_address() {
  slack_notification_email_address="${1}"
}


# Sets the monitored_dir_partition variable
# This variable let the script know what partition the monitored dir is on
#
Set_jenkins_dir_partition() {
    jenkins_dir_partition="$( \
                              df /var/lib/jenkins/workspace \
                              | grep -oP "(?<=(%\s))/.*" \
                            )"
}


# Sets the disk_status variable
# This variable lets the script know if the disk usage threshold has been met
#
Set_disk_status() {
  disk_usage_percent="$( \
                         df -h ${jenkins_dir_partition} \
                         | grep -oP "(?<=(\s))[0-9]+(?=(%))" \
                       )"
  if [[ "${disk_usage_percent}" -ge "84" ]]; then
    disk_status="low"
  else
    disk_status="not_low"
  fi
}


# When invoked, this checks the disk_status variable
# If disk_status is "not_low", (less than 84% disk usage), the script exits.
#
Check_disk_status() {
  if [[ "${disk_status}" == "not_low" ]]; then
    exit 0
  fi
}


# Sends the notification to Slack channel via Slack-provided email address.
#
Send_notification_to_slack() {
  cat \
    <( \
        echo "Check Jenkins workspace and please free space on:"; \
        echo " \"${jenkins_dir_partition}\" "; \
     ) \
    <( \
        printf "\nMB\tDirectory Name\n" \
     ) \
    <( \
        find /var/lib/jenkins/jobs \
          -maxdepth 1 \
          -mindepth 1 \
          -type d \
          -exec du -sm '{}' \; \
        | sort -nr \
     ) \
  | mail -s "[WARNING] \"${jenkins_dir_partition}\" at ${disk_usage_percent}%" ${1}
}


################################################################################
### PROGRAM EXECUTION
################################################################################

Set_slack_notification_email_address ${1} \
&& Set_jenkins_dir_partition \
&& Set_disk_status \
&& Check_disk_status \
&& Send_notification_to_slack ${slack_notification_email_address}
