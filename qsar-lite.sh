echo -e "\n---------\n- Time Script Ran\n---------"; \
date; \
echo -e "\n---------\n- Hostname and Private IP(s)\n---------"; \
hostname; \
hostname -I 2>/dev/null || hostname -i; \
echo -e "\n---------\n- Sudoer Users/Groups and Permissions\n---------"; \
grep -avP '^\s*(#|User_Alias|Cmnd_Alias|Defaults|\ )' /etc/sudoers /etc/sudoers.d/* 2>/dev/null \
| sed '/^$/d'; \
echo -e "\n---------\n- Sudoers Alias Commands\n---------"; \
grep -ai 'Cmnd_Alias' /etc/sudoers /etc/sudoers.d/* 2>/dev/null \
| grep -vP '\s*#' \
| sed -e 's|/etc/sudoers.*:Cmnd_Alias\ ||g'; \
printf "\n---------\n- LDAP Sudoer Groups\n---------"; \
grep -avP '^\s*(#|User_Alias|Cmnd_Alias|Defaults|\ )' /etc/sudoers /etc/sudoers.d/* 2>/dev/null \
| grep -oP "^%.*(?=(ALL.*=))" \
| sed '/^$/d' \
| while read -r group; do \
    egrep "^${group:1}" /etc/group >/dev/null || echo ${group}; \
  done \
| while read -r ldap_group; do \
  getent group ${ldap_group:1} 2> /dev/null \
  | while IFS=: read -r group_name _ _ members; do \
    printf "\n%%${group_name}"; \
    while IFS=, read -r member{1..9999}; do \
      SSO_ARRAY=( $member{1..9999} ); \
      for sso in ${SSO_ARRAY[@]}; do \
        printf "\n ${sso}"; \
        curl -s -m 1 \
          "ldaps://auth.edir.rackspace.com/cn=${sso},ou=Users,o=rackspace?displayName" \
        | grep -aoP "(?<=(displayName:\s)).*" 2>/dev/null \
        | while read -r grep_output; do \
          if [[ "${#grep_output}" != "0" ]]; then \
            printf " (${grep_output})"; \
          fi; \
        done; \
      done; \
    done <<<${members}; \
  done; \
done; \
echo; \
echo -e "\n---------\n- Groups allowed in sshd\n---------"; \
grep 'AllowGroups' /etc/ssh/sshd_config \
| grep -vP '^\\s*#' \
| sed -e 's|AllowGroups\\ ||g'; \
echo -e "\n---------\n- User Aliases\n---------"; \
grep -P '^\\s*User_Alias' /etc/sudoers /etc/sudoers.d/* 2>/dev/null \
| grep -avP '^/.*:\\s*#' \
echo -e "\n---------\n- Users in /etc/passwd\n---------"; \
sudo grep -vP '^(\\s*#|$)' /etc/shadow \
| cut -d: -f1; \
echo -e "\n---------\n- Local users with hash\n---------"; \
for line in $(grep -vP \'\^\(\\s\*\#\|\$\)\' /etc/shadow); do \
  while IFS=: read -r user hash other_info; do \
    if [[ "${hash:0:1}" == '!' || ${hash:0:1} == '*' || ${#hash} -eq "0" ]]; then \
      echo "No hash"; \
    else \
      echo "Has Hash"; \
    fi; \
  done <<<${line}; \
done; \
echo -e "\n---------\n- Groups in /etc/group\n---------"; \
grep -vP '^(\\s*#|$)' /etc/group; \
# qsar-lite one-liner by Cody Lee Cochran
