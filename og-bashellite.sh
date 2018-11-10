#!/usr/bin/env bash
#
### Program Name: Bashellite
#
### Program Author: Cody Lee Cochran <Cody.L.Cochran@gmail.com>
### Program Contributors: Eric Lake <EricLake@Gmail.com>
#
### Program Purpose:
#   The purpose of this program is to create an automated method for pulling
#   package files from an upstream mirror on the internet, and exporting
#   the newly created local mirror to an external HDD for import to an "air-gapped"
#   network. The repo data retrieved from upstream repos is staged on a local mirror
#   that does have internet access, and is prepped for export on that local
#   mirror. The local mirror is also used to keep track of what has previously
#   been exported so that a diff can be run each time data is pulled from
#   the upstream repos. This is used to determine what gets exported from the
#   local staging mirror to the downstream air-gapped mirror. The exports are
#   then shipped via a read-only medium to the air-gapped network to prevent
#   leakage from the air-gapped network onto the internet-connected network.
#
################################################################################


################################################################################
### DEBUGGING OPTIONS ###
#########################
#
### This section is for toggling debugging on/off.
#
################################################################################
set +x # <- Debugging off
#set -x # <- Debugging on

################################################################################


################################################################################
### ADMINISTRATIVE FUNCTION DEFINITIONS ###
###########################################
#
### This section is for boilerplate-type functions not specific to syncing.
### It includes sections for:
###   - Checking to make sure user is root or a superuser
###   - Creating/maintaining time and date stamping for logs
###   - Generating error messages for the user and logs
###   - Defining/printing the usage message
###   - Parsing the command-line parameters passed by user
###   - Parses the absolute path of this script for use later in script
#
### Note: logging is not enabled for any of these functions.
#
################################################################################

# This function ensures you are root and/or have sudo access.
Check_user() {
  if [[ "${EUID}" != "0" ]]; then
    echo "[FAIL] This script must be run as root and/or with sudo.";
    exit 1;
  fi
}

# This function does a dependency check before proceeding
Check_deps() {
  for dep in grep \
             date \
             tput \
             basename \
             realpath \
             dirname \
             ls \
             mkdir \
             chown \
             touch \
             cat \
             sed \
             tee;
  do
    type ${dep} &>/dev/null \
      || { echo "[FAIL] Dependency (${dep}) missing!"; exit 1; };
  done
}

# Ensures that the versions of certain deps are the GNU version before proceeding
Ensure_gnu_deps() {
  for dep in grep \
             date \
             basename \
             realpath \
             dirname \
             ls \
             mkdir \
             chown \
             touch \
             cat \
             sed \
             tee;
  do
    grep "GNU" <<<"$(${dep} --version 2>&1)" &>/dev/null \
      || { echo "[FAIL] Dependency (${dep}) not GNU version!"; exit 1; };
  done
}

# These functions create variables used throughout the program
# This one generates a datestamp for use in log file names
Get_date() {
  unset datestamp;
  datestamp="$(date --iso-8601 2>/dev/null)";
  datestamp="${datestamp//[^0-9]}";
  readonly datestamp="${datestamp:2}"
  if [[ "${#datestamp}" != "6" ]]; then
    echo "[FAIL] Failed to set datestamp; ensure date supports \"--iso-8601\" flag!";
    exit 1;
  fi
}

# Sets timestamp used in log file lines and log file names and other functions
Get_time() {
  unset timestamp;
  timestamp="$(date --iso-8601='ns' 2>/dev/null)";
  timestamp="${timestamp//[^0-9]}";
  timestamp="${timestamp:8:8}";
  if [[ "${#timestamp}" != "8" ]]; then
    echo "[FAIL] Failed to set timestamp; ensure date supports \"--iso-8601\" flag!";
    exit 1;
  fi
}

# Sets run_id used in log file names to give each script run a unique id
Get_run_id() {
  Get_time;
  readonly run_id="${timestamp}";
  if [[ "${#run_id}" != "8" ]]; then
    echo "[FAIL] Failed to set run_id!"
    exit 1;
  fi
}

# Determines the script_dir
Get_script_dir() {
  readonly script_dir="$(realpath $(dirname ${0}))";
  # This variable is validated later
}


# These functions are used to generate colored output
#  Info is green, Warn is yellow, Fail is red.
# Timestamps are always white, and color is reset at end of messages.

Set_colors() {
  readonly mk_wht="$(tput setaf 7)"; # make white
  readonly mk_grn="$(tput setaf 2)"; # make green
  readonly mk_ylw="$(tput setaf 3)"; # make yellow
  readonly mk_red="$(tput setaf 1)"; # make red
  readonly mk_clr="$(tput sgr0)";    # make clear / clear-out colors
  for color in mk_{wht,grn,ylw,red,clr}; do
    if [[ ! -v "${color}" ]]; then
      echo "[FAIL] Failed to set terminal output color: ${color}!"
      exit 1;
    fi
  done
}

Info() {
  Get_time \
  && echo -e "${mk_wht}${timestamp} ${mk_grn}[${dryrun}INFO] $*${mk_clr}";
}

Warn() {
  Get_time \
  && echo -e "${mk_wht}${timestamp} ${mk_ylw}[${dryrun}WARN] $*${mk_clr}" >&2;
}

Fail() {
  Get_time \
  && echo -e "${mk_wht}${timestamp} ${mk_red}[${dryrun}FAIL] $*${mk_clr}" >&2;
  exit 1;
}


# This function prints usage messaging to STDOUT when invoked.
Usage() {
  echo
  echo "Usage: $(basename ${0})"
  echo "       -m mirror_top-level_directory"
  echo "       [-h]"
  echo "       [-d]"
  echo "       [-r repository_name] | [-a]"
  echo
  echo "       Mandatory Parameter(s):"
  echo "       -m:  Sets the disk mirror top-level directory."
  echo "            Only absolute (full) paths are accepted!"
  echo
  echo "       Optional Parameter(s):"
  echo "       -h:  Prints this usage message."
  echo "       -d:  Dry-run mode. Pulls down a listing of the files and"
  echo "            directories it would download, and then exits."
  echo "       -r:  The repo name to sync."
  echo "       -a:  Mutually exclusive with -r option; sync all repos."
  echo
}

# This function parses the parameters passed over the command-line by the user.
Parse_parameters() {
  if [[ "${#}" = "0" ]]; then
    Usage;
    Fail "\nBashellite has mandatory parameters; review usage message and try again.\n";
  fi

  # This section unsets some variables, just in case.
  unset mirror_tld;
  unset target_repo_name;
  unset dryrun;
  unset all_repos;

  # Bash-builtin getopts is used to perform parsing, so no long options are used.
  while getopts ":m:r:ahd" passed_parameter; do
   case "${passed_parameter}" in
      m)
        if [[ "${OPTARG:0:1}" != "/" ]]; then
          Usage;
          Fail "\nAbsolute paths only, please; exiting.\n";
        else
          mirror_tld="${OPTARG}";
          # Drops the last "/" from the value of mirror_tld to ensure uniformity for functions using it.
          # Note: as a side-effect, this effective prevents using just "/" as the value for mirror_tld.
          mirror_tld="${mirror_tld%\/}";
          # This santizes the directory name of spaces or any other undesired characters.
          mirror_tld="${mirror_tld//[^a-zA-Z1-9_-/]}";
        fi
        ;;
      r)
        # Sanitizes the directory name of spaces or any other undesired characters.
	target_repo_name="${OPTARG//[^a-zA-Z1-9_-]}";
	;;
      d)
        dryrun="DRYRUN|";
        ;;
      a)
        all_repos="true"
        ;;
      h)
        Usage;
        exit 0;
        ;;
      *)
        Usage;
        Fail "\nInvalid option passed to \"$(basename ${0})\"; exiting. See Usage below.\n";
        ;;
    esac
  done
  shift $((OPTIND-1));
}

# This function determines the scope of work; if all_repos is true, all repos are involved.
Determine_scope() {
  unset repo_name_array;
  if [[ "${all_repos}" == "true" ]]; then
    repo_name_array=( $(ls ${mirror_tld}/_metadata/) );
  else
    repo_name_array=( ${target_repo_name} );
  fi
  # The success of this variable assignment is checked later once logging is on.
}


################################################################################

################################################################################
### SYNC FUNCTION DEFINITIONS ###
#################################
#
### This section is for functions related to the main execution of the program.
### Functions in this section perform the following tasks:
###   - Ensure all required parameters are set before attempting sync
###   - Ensuring appropriate directories exist for mirror
###   - Ensuring appropriate dirs/files exist per repo
###   - Ensuring repo metadata is populated before attempting sync
###   - Ensuring required sync providers are installed and accesssible
###   - Performing the sync
###   - Reporting on the success of the sync
#
################################################################################

Validate_variables() {

  # Ensures repo_name_array is not empty
  if [[ "${#repo_name_array[@]}" -lt "1" ]]; then
    Fail "Bashellite requires at least one valid repository.";
  fi

  # Ensures script_dir is a valid absolute path to a real directory.
  if [[ ! -d "${script_dir}" ]]; then
    Fail "The value of script_dir is not valid; exiting.";
  fi

  # Exit if both -a and -r are passed and display usage
  # Thanks for this contribution, Eric. :-)
  if [[ ${all_repos} && ${target_repo_name} ]]; then
      Usage;
      echo;
      Fail "The flags -a and -r are mutually exclusive. Use one or the other; exiting.\n";
  fi

  # If the mirror_tld is unset or null; then exit.
  # Since the last "/" was dropped in Parse_parameter,
  # If user passed "/" for mirror_tld value, it effectively becomes "" (null).
  if [[ "${#mirror_tld}" -lt "1" ]]; then
    Usage;
    echo;
    Fail "Please set the desired location of the local mirror; exiting.\n";
  fi
}

# Ensuring _metadata/ subdirectory exists in user-passed ${mirror_tld}.
Validate_mirror_framework() {
    Info "Creating/validating directory for mirror...";
    mkdir -p ${mirror_tld}/_metadata;
    mkdir -p /var/log/bashellite/;
    chown root:root /var/log/bashellite;
}

# This function creates/validates the file/directory framework for the requested repo.
Validate_repo_framework() {
  if [[ -n "${repo_name}" ]]; then
    Info "Creating/validating directory and file structure for repo (${repo_name})...";
    mkdir -p ${mirror_tld}/_metadata/${repo_name}/;
    mkdir -p ${mirror_tld}/_bin/;
    touch ${mirror_tld}/_metadata/${repo_name}/rsync_url.conf;
    touch ${mirror_tld}/_metadata/${repo_name}/http_url.conf;
    touch ${mirror_tld}/_metadata/${repo_name}/pypi_url.conf;
    touch ${mirror_tld}/_metadata/${repo_name}/repo_filter.conf;
    touch ${mirror_tld}/_metadata/${repo_name}/dns_name.conf;
    touch ${mirror_tld}/_metadata/${repo_name}/README.txt
    mkdir -p ${mirror_tld}/${repo_name}/;
  fi
}

# This function validates that a URL has been provided for the rsync repo.
# The _metadata/ directory is relative to the bashellite script's location.
# It is not relative to the mirror_tld, as one might think.
Validate_repo_metadata() {
  # Sanitizing variables
  unset rsync_url;
  unset http_url;
  unset pypi_url;
  unset dryrun_flag;
  count=0;

  Info "Validating repo (${repo_name}) metadata...";

  # Ensuring two (or more) *_url.conf files are not populated.
  for url_conf_file in ${script_dir}/_metadata/${repo_name}/*_url.conf; do
    if [[ -s "${url_conf_file}" ]]; then
      target_url_conf_file="${url_conf_file}"
      count="$(( ++count))"
      if [[ "${count}" -gt "1" ]]; then
         Warn "More than one *_url.conf is populated for this repo (${repo_name}).";
         Fail "Please ensure only ONE *_url.conf is populated at a time; exiting.";
      fi
    fi
  done

  # Parsing populated *_url.conf file and setting variable values accordingly.
  if [[ -s "${script_dir}/_metadata/${repo_name}/rsync_url.conf" ]]; then
    rsync_url="$(cat ${script_dir}/_metadata/${repo_name}/rsync_url.conf)";
    if [[ "${dryrun}" == "DRYRUN|" ]]; then
      dryrun_flag="--dry-run";
    fi
  elif [[ -s "${script_dir}/_metadata/${repo_name}/http_url.conf" ]]; then
    http_url="$(cat ${script_dir}/_metadata/${repo_name}/http_url.conf)";
    # Ensures consistency by dropping trailing "/" from $http_url.
    http_url="${http_url%\/}";
    if [[ "${dryrun}" == "DRYRUN|" ]]; then
      dryrun_flag="--spider";
    fi
  elif [[ -s "${script_dir}/_metadata/${repo_name}/pypi_url.conf" ]]; then
    pypi_url="$(cat ${script_dir}/_metadata/${repo_name}/pypi_url.conf)";
  else
    Warn "Please place the mirror URL of the repo in ONE of the following only:";
    Warn " rsync => ${script_dir}/_metadata/${repo_name}/rsync_url.conf";
    Warn " http => ${script_dir}/_metadata/${repo_name}/http_url.conf";
    Warn " pypi => ${script_dir}/_metadata/${repo_name}/pypi_url.conf";
    Warn "Please place any desired filter parameters, (aka includes and/or excludes), in:";
    Warn " => ${script_dir}/_metadata/${repo_name}/repo_filter.conf";
    Fail "Place the URL of the repo (${repo_name}) in one, and ONLY one, \"_metadata/*_url.conf\" file and try again.";
  fi
}

Ensure_sync_provider_installed() {
  Info "Ensuring sync provider is installed for repo (${repo_name})...";
  # If rsync_url is populated, ensure rsync is installed
  if [[ -n "${rsync_url}" ]]; then
    which rsync &>/dev/null;
    if [[ "${?}" == "0" ]]; then
      Info "rsync appears to be installed and/or in the path...";
    else
      Fail "rsync does NOT appear to be installed and/or in the path; exiting";
    fi
  # if http_url is populated, ensure wget is installed
  elif [[ -n "${http_url}" ]]; then
    which wget &>/dev/null;
    if [[ "${?}" == "0" ]]; then
      Info "wget appears to be installed and/or in the path...";
    else
      Fail "wget does NOT appear to be installed and/or in the path; exiting.";
    fi
  # if pypi_url is populated, ensure pip and virtualenv are installed
  elif [[ -n "${pypi_url}" ]]; then
    which pip &>/dev/null;
    if [[ "${?}" != "0" ]]; then
      Fail "Can not proceed until pip is installed and accessible in path; exiting."
    fi
    which virtualenv &>/dev/null;
    if [[ "${?}" != "0" ]]; then
      Fail "Can not proceed until virutalenv is installed and accessible in path; exiting."
    fi
    # If pip and virtualenv are installed, ensure bandersnatch is installed in proper location, and functional.
    ${script_dir}/_bin/${repo_name}/bin/bandersnatch --help &>/dev/null;
    if [[ "${?}" == "0" ]]; then
      Info "bandersnatch appears to be installed for this repo (${repo_name})...";
    else
      # If bandersnatch is not installed, or broken, blow away the old one, (if required), and install a new one.
      Warn "bandersnatch does NOT appear to be installed, (or it is broken), for repo (${repo_name}); (re)installing...";
      rm -fr ${script_dir}/_bin/${repo_name}/ &>/dev/null;
      virtualenv --python=python3.5 ${script_dir}/_bin/${repo_name};
      ${script_dir}/_bin/${repo_name}/bin/pip install -r https://bitbucket.org/pypa/bandersnatch/raw/stable/requirements.txt;
      ${script_dir}/_bin/${repo_name}/bin/bandersnatch -c "${script_dir}/_bin/${repo_name}/bandersnatch.conf";
      sed -i "s%^\s*master\s*=.*%master = ${pypi_url}%g" ${script_dir}/_bin/${repo_name}/bandersnatch.conf;
      sed -i "s%^\s*directory\s*=.*%directory = ${mirror_tld}/${repo_name}%g" ${script_dir}/_bin/${repo_name}/bandersnatch.conf;
      ${script_dir}/_bin/${repo_name}/bin/bandersnatch --help &>/dev/null;
      if [[ "${?}" == "0" ]]; then
        Info "bandersnatch installed successfully for repo (${repo_name})...";
      else
        Fail "bandersnatch was NOT installed successfully for repo (${repo_name}); exiting.";
      fi
    fi
  fi
}

# This function performs the actual sync of the repository
Sync_repository() {
  Info "Syncing from upstream mirror to local repo (${repo_name})...";
  # If rsync_url is set, use rsync to sync
  if [[ -n ${rsync_url} ]]; then
    rsync -avSLP ${rsync_url} \
      ${dryrun_flag} \
      --exclude-from="${mirror_tld}/_metadata/${repo_name}/repo_filter.conf" \
      --safe-links \
      --no-motd \
      --hard-links \
      --update \
      --links \
      --delete \
      --delete-before \
      --ignore-existing \
      ${mirror_tld}/${repo_name}
    if [[ "${?}" != "0" ]]; then
      Warn "rsync completed with errors for repo (${repo_name})."
    else
      Info "rsync completed successfully for repo (${repo_name})."
    fi
    unset rsync_url;
  # If http_url is set, use wget to sync
  elif [[ -n ${http_url} ]]; then
    for file_path in $(cat ${mirror_tld}/_metadata/${repo_name}/repo_filter.conf); do
      if [[ "${dryrun}" == "DRYRUN|" ]]; then
        # wget unfortunately sends ALL output to STDERR.
        wget ${dryrun_flag} ${http_url}/${file_path} 2>&1;
        if [[ "${?}" == "0" ]]; then
          Info "wget successfully downloaded file(s) from:"
          Info "  => ${http_url}/${file_path}\n"
        else
          Warn "wget did NOT successfully download file(s) from:"
          Warn "  => ${http_url}/${file_path}\n"
        fi
      else
        # wget unfortunately sends ALL output to STDERR.
        wget -mk -nH -P ${repo_name} ${http_url}/${file_path} 2>&1;
        if [[ "${?}" == "0" ]]; then
          Info "wget successfully downloaded file(s) from:"
          Info "  => ${http_url}/${file_path}\n"
        else
          Warn "wget did NOT successfully download file(s) from:"
          Warn "  => ${http_url}/${file_path}\n"
        fi
      fi
    done
    unset http_url;
  # If pypi_url is set, use bandersnatch to sync
  elif [[ -n "${pypi_url}" ]]; then
    # Perform some pre-sync checks
    read _ pypi_status_code _ <<<"$(curl -sI ${pypi_url})";
    if [[ "${pypi_status_code:0:1}" < "4" ]]; then
      Info "The pypi mirror appears to be up; sync should work...";
    else
      Fail "The pypi mirror appears to be down/invalid/inaccessible; exiting...";
    fi
    # If dryrun is true, perform dryrun
    if [[ "${dryrun}" == "DRYRUN|" ]]; then
      Info "Proceeding with sync of repo (${repo_name})..."
      Info "Sync of repo (${repo_name}) completed without error..."
      # After dryrun completes, dryrun the removal of excluded packages
      for pkg_name in $(cat ${script_dir}/_metadata/${repo_name}/repo_filter.conf); do
        Info "Attempting to remove excluded package (${pkg_name})...";
        if [[ -e "${mirror_tld}/${repo_name}/web/simple/${pkg_name}/index.html" ]]; then
          for pkg_version in $(grep -oP "packages/.*(?=(#))" ${mirror_tld}/${repo_name}/web/simple/${pkg_name}/index.html); do
            Info "Removed ${mirror_tld}/${repo_name}/web/${pkg_version}";
          done
          Info "Removed ${mirror_tld}/${repo_name}/web/simple/${pkg_name}";
        else
          Warn "No matching package (${pkg_name}) found in repository...";
        fi
      done
    # If dryrun is not true, perform real run
    else
      Info "Proceeding with sync of repo (${repo_name})..."
      ${script_dir}/_bin/${repo_name}/bin/bandersnatch -c "${script_dir}/_bin/${repo_name}/bandersnatch.conf" mirror;
      if [[ "${?}" == "0" ]]; then
        Info "Sync of repo (${repo_name}) completed without error...";
      else
        Warn "Sync of repo (${repo_name}) did NOT complete without error...";
      fi
      # After run completes, remove excluded packages
      for pkg_name in $(cat ${script_dir}/_metadata/${repo_name}/repo_filter.conf); do
        Info "Attempting to remove excluded package (${pkg_name})...";
        if [[ -e "${mirror_tld}/${repo_name}/web/simple/${pkg_name}/index.html" ]]; then
          for pkg_version in $(grep -oP "packages/.*(?=(#))" ${mirror_tld}/${repo_name}/web/simple/${pkg_name}/index.html); do
            { rm -f ${mirror_tld}/${repo_name}/web/${pkg_version} \
            && Info "Removed ${mirror_tld}/${repo_name}/web/${pkg_version}"; } \
            || Fail "Failed to remove ${mirror_tld}/${repo_name}/web/${pkg_version}";
          done
          { rm -fr ${mirror_tld}/${repo_name}/web/simple/${pkg_name} \
          && Info "Removed ${mirror_tld}/${repo_name}/web/simple/${pkg_name}"; } \
          || Fail "Failed to remove ${mirror_tld}/${repo_name}/web/simple/${pkg_name}";
        else
          Warn "No matching package (${pkg_name}) found; check the subdirectories listed here for list of valid package names:"
          Warn " => ${mirror_tld}/${repo_name}/simple/"
        fi
      done
    fi
    unset pypi_url;
  fi
}

# Since hard fails cause the script to "exit 1", this function only gets called if it doesn't encounter any.
# Minor errors that aren't show-stoppers get logged as "WARN" messages, and the script continues.
Great_success() {
  if [[ -s "/var/log/bashellite/${repo_name}.${datestamp}.${run_id}.error.log" ]]; then
    Warn "Bashellite has successfully completed requested task for repo (${repo_name}), but...";
    Warn "Please see error log for error details; minor errors detected in this run's error log:";
    Warn " errors => /var/log/bashellite/${repo_name}.${datestamp}.${run_id}.error.log"
    echo
  else
    Info "Bashellite has successfully completed requested task for repo (${repo_name})!";
    Info "Please see logs for event details; no errors detected in this run's error log:";
    Info " events => /var/log/bashellite/${repo_name}.${datestamp}.${run_id}.event.log"
    echo
  fi
}


################################################################################


################################################################################
### PROGRAM EXECUTION ###
#########################
### This section is for the execution of the previously defined functions.
################################################################################

# These complete prepatory admin tasks before executing the sync functions.
# These functions require minimal file permissions and avoid writes to disk.
# This makes errors unlikely, which is why logging is not enabled for them.
# These function only write STDERR to the terminal, not log files.
Check_user \
&& Check_deps \
&& Ensure_gnu_deps \
&& Get_date \
&& Get_run_id \
&& Get_script_dir \
&& Set_colors \
&& Parse_parameters ${@} \
&& Determine_scope;

# This for-loop executes the sync functions on the appropriate repos (either all or just one of them).
# Logging is enabled for all of these functions; some don't technically need to be in the loop, except for logging.
if [[ "${?}" == "0" ]]; then
  for repo_name in ${repo_name_array[@]}; do
  Info "Starting Bashellite run (${run_id}) for repo (${repo_name})..."
    for task in Validate_variables \
                Validate_mirror_framework \
                Validate_repo_framework \
                Validate_repo_metadata \
                Ensure_sync_provider_installed \
                Sync_repository \
                Great_success;
    do
      ${task};
    done 1> >(tee -a /var/log/bashellite/${repo_name}.${datestamp}.${run_id}.event.log >&1) \
         2> >(tee -a /var/log/bashellite/${repo_name}.${datestamp}.${run_id}.error.log >&2);
  done
else
  # This is ONLY executed if one of the prepatory/administrative functions fails.
  # Most of them handle their own errors, and exit on failure, but a few do not.
  echo "[FAIL] Bashellite failed to execute requested tasks; exiting!";
  exit 1;
fi
################################################################################
