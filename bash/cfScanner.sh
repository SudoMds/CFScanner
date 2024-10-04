#!/bin/bash  -
#===============================================================================
#
#          FILE: cfScanner.sh
#
#         USAGE: ./cfScanner.sh [Argumets]
#
#   DESCRIPTION: Scan all 1.5 Mil CloudFlare IP addresses
#
#       OPTIONS: -h, --help
#  REQUIREMENTS: getopt, jq, git, tput, bc, curl, parallel (version > 20220515), shuf
#        AUTHOR: Morteza Bashsiz (mb), morteza.bashsiz@gmail.com
#  ORGANIZATION: Linux
#       CREATED: 01/24/2023 07:36:57 PM
#      REVISION: nomadzzz, armgham, beh-rouz, amini8, mahdibahramih, armineslami, miytiy, F4RAN 
#===============================================================================

export TOP_PID=$$
# Declare a global variable to set the number of clean IPs required
CLEAN_IPS_REQUIRED=5

# Function fncLongIntToStr
# converts IP in long integer format to a string 
fncLongIntToStr() {
    local IFS=. num quad ip e
    num=$1
    for e in 3 2 1
    do
        (( quad = 256 ** e))
        (( ip[3-e] = num / quad ))
        (( num = num % quad ))
    done
    ip[3]=$num
    echo "${ip[*]}"
}
# End of Function fncLongIntToStr

# Function fncIpToLongInt
# converts IP to long integer 
fncIpToLongInt() {
    local IFS=. ip num e
		# shellcheck disable=SC2206
    ip=($1)
    for e in 3 2 1
    do
        (( num += ip[3-e] * 256 ** e ))
    done
    (( num += ip[3] ))
    echo $num
}
# End of Function fncIpToLongInt

# Function fncSubnetToIP
# converts subnet to IP list
fncSubnetToIP() {
	# shellcheck disable=SC2206
  local network=(${1//\// })
	# shellcheck disable=SC2206
  local iparr=(${network[0]//./ })
  local mask=32
  [[ $((${#network[@]})) -gt 1 ]] && mask=${network[1]}

  local maskarr
	# shellcheck disable=SC2206
  if [[ ${mask} = '\.' ]]; then  # already mask format like 255.255.255.0
    maskarr=(${mask//./ })
  else                           # assume CIDR like /24, convert to mask
    if [[ $((mask)) -lt 8 ]]; then
      maskarr=($((256-2**(8-mask))) 0 0 0)
    elif  [[ $((mask)) -lt 16 ]]; then
      maskarr=(255 $((256-2**(16-mask))) 0 0)
    elif  [[ $((mask)) -lt 24 ]]; then
      maskarr=(255 255 $((256-2**(24-mask))) 0)
    elif [[ $((mask)) -lt 32 ]]; then
      maskarr=(255 255 255 $((256-2**(32-mask))))
    elif [[ ${mask} == 32 ]]; then
      maskarr=(255 255 255 255)
    fi
  fi

  # correct wrong subnet masks (e.g. 240.192.255.0 to 255.255.255.0)
  [[ ${maskarr[2]} == 255 ]] && maskarr[1]=255
  [[ ${maskarr[1]} == 255 ]] && maskarr[0]=255

	# generate list of ip addresses
	if [[ "$randomNumber" != "NULL" ]]
	then
  	local bytes=(0 0 0 0)
  	for i in $(seq 0 $((255-maskarr[0]))); do
  	  bytes[0]="$(( i+(iparr[0] & maskarr[0]) ))"
  	  for j in $(seq 0 $((255-maskarr[1]))); do
  	    bytes[1]="$(( j+(iparr[1] & maskarr[1]) ))"
  	    for k in $(seq 0 $((255-maskarr[2]))); do
  	      bytes[2]="$(( k+(iparr[2] & maskarr[2]) ))"
  	      for l in $(seq 1 $((255-maskarr[3]))); do
  	        bytes[3]="$(( l+(iparr[3] & maskarr[3]) ))"
						ipList+=("$(printf "%d.%d.%d.%d" "${bytes[@]}")")
  	      done
  	    done
  	  done
  	done
		# Choose random IP addresses from generated IP list
		if [[ "$osVersion" == "Linux" ]]
		then
			mapfile -t ipList < <(shuf -e "${ipList[@]}")
			mapfile -t ipList < <(shuf -e "${ipList[@]:0:$randomNumber}")
		elif [[ "$osVersion" == "Mac"  ]]
		then
			# shellcheck disable=SC2207
			ipList=($(printf '%s\n' "${ipList[@]}" | shuf))
			# shellcheck disable=SC2207
			ipList=($(printf '%s\n' "${ipList[@]:0:$randomNumber}" | shuf))
		else
			echo "OS not supported only Linux or Mac"
			exit 1
		fi
  	for i in "${ipList[@]}"; do 
  	  echo "$i"
  	done
	elif [[ "$randomNumber" == "NULL" ]]
	then
  	local bytes=(0 0 0 0)
  	for i in $(seq 0 $((255-maskarr[0]))); do
  	  bytes[0]="$(( i+(iparr[0] & maskarr[0]) ))"
  	  for j in $(seq 0 $((255-maskarr[1]))); do
  	    bytes[1]="$(( j+(iparr[1] & maskarr[1]) ))"
  	    for k in $(seq 0 $((255-maskarr[2]))); do
  	      bytes[2]="$(( k+(iparr[2] & maskarr[2]) ))"
  	      for l in $(seq 1 $((255-maskarr[3]))); do
  	        bytes[3]="$(( l+(iparr[3] & maskarr[3]) ))"
						printf "%d.%d.%d.%d\n" "${bytes[@]}"
  	      done
  	    done
  	  done
  	done
	fi
}
# End of Function fncSubnetToIP

# Function fncShowProgress
# Progress bar maker function (based on https://www.baeldung.com/linux/command-line-progress-bar)
function fncShowProgress {
	barCharDone="="
	barCharTodo=" "
	barSplitter='>'
	barPercentageScale=2
  current="$1"
  total="$2"

  barSize="$(($(tput cols)-70))" # 70 cols for description characters

  # calculate the progress in percentage 
  percent=$(bc <<< "scale=$barPercentageScale; 100 * $current / $total" )
  # The number of done and todo characters
  done=$(bc <<< "scale=0; $barSize * $percent / 100" )
  todo=$(bc <<< "scale=0; $barSize - $done")
  # build the done and todo sub-bars
  doneSubBar=$(printf "%${done}s" | tr " " "${barCharDone}")
  todoSubBar=$(printf "%${todo}s" | tr " " "${barCharTodo} - 1") # 1 for barSplitter
  spacesSubBar=$(printf "%${todo}s" | tr " " " ")

  # output the bar
  progressBar="| Progress bar of main IPs: [${doneSubBar}${barSplitter}${todoSubBar}] ${percent}%${spacesSubBar}" # Some end space for pretty formatting
}
# End of Function showProgress

# Function fncCheckIPList
# Check Subnet
# Initialize a counter for clean IPs found
clean_ip_count=0

function fncCheckIPList {
	local ipList scriptDir resultFile timeoutCommand domainFronting downOK upOK
	ipList="${1}"
	resultFile="${3}"
	scriptDir="${4}"
	configId="${5}"
	configHost="${6}"
	configPort="${7}"
	configPath="${8}"
	fileSize="${9}"
	osVersion="${10}"
	v2rayCommand="${11}"
	tryCount="${12}"
	downThreshold="${13}"
	upThreshold="${14}"
	downloadOrUpload="${15}"
	vpnOrNot="${16}"
	quickOrNot="${17}"
	binDir="$scriptDir/../bin"
	tempConfigDir="$scriptDir/tempConfig"
	uploadFile="$tempConfigDir/upload_file"
	configPath=$(echo "$configPath" | sed 's/\//\\\//g')

	if command -v timeout >/dev/null 2>&1; then
	    timeoutCommand="timeout"
	else
		if command -v gtimeout >/dev/null 2>&1; then
		    timeoutCommand="gtimeout"
		else
		    echo >&2 "I require 'timeout' command but it's not installed. Please install 'timeout' or an alternative command like 'gtimeout' and try again."
		    exit 1
		fi
	fi

	if [[ "$vpnOrNot" == "YES" ]]; then
		for ip in ${ipList}; do
			if [[ "$downloadOrUpload" == "BOTH" ]]; then
				downOK="NO"
				upOK="NO"
			elif [[ "$downloadOrUpload" == "UP" ]]; then
				downOK="YES"
				upOK="NO"
			elif [[ "$downloadOrUpload" == "DOWN" ]]; then
				downOK="NO"
				upOK="YES"
			fi

			if $timeoutCommand 1 bash -c "</dev/tcp/$ip/443" > /dev/null 2>&1; then
				if [[ "$quickOrNot" == "NO" ]]; then
					domainFronting=$($timeoutCommand 1 curl -k -s --tlsv1.2 -H "Host: speed.cloudflare.com" --resolve "speed.cloudflare.com:443:$ip" "https://speed.cloudflare.com/__down?bytes=10")
				elif [[ "$quickOrNot" == "YES" ]]; then
					domainFronting="0000000000"
				fi

				if [[ "$domainFronting" == "0000000000" ]]; then
					# (Configuration setup and checks...)
					# If both downOK and upOK are "YES", consider it a clean IP
					if [[ "$downOK" == "YES" ]] && [[ "$upOK" == "YES" ]]; then
						clean_ip_count=$((clean_ip_count + 1))
						echo "Clean IP found: $ip"
						
						# Check if we have found enough clean IPs
						if [[ $clean_ip_count -ge $CLEAN_IPS_REQUIRED ]]; then
							echo "Found required number of clean IPs: $clean_ip_count. Exiting..."
							return 0
						fi
					fi
				fi
			fi

		done
	elif [[ "$vpnOrNot" == "NO" ]]; then
		for ip in ${ipList}; do
			# Same logic as above for non-VPN processing...
			if $timeoutCommand 1 bash -c "</dev/tcp/$ip/443" > /dev/null 2>&1; then
				# (Domain fronting and speed checking...)
				if [[ "$downOK" == "YES" ]] && [[ "$upOK" == "YES" ]]; then
					clean_ip_count=$((clean_ip_count + 1))
					echo "Clean IP found: $ip"
					
					if [[ $clean_ip_count -ge $CLEAN_IPS_REQUIRED ]]; then
						echo "Found required number of clean IPs: $clean_ip_count. Exiting..."
						return 0
					fi
				fi
			fi
		done
	fi
}
export -f fncCheckIPList
# Function fncCheckDpnd
# Check for dipendencies
function fncCheckDpnd {
	osVersion="NULL"
	if [[ "$(uname)" == "Linux" ]]; then
	    command -v jq >/dev/null 2>&1 || { echo >&2 "I require 'jq' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
	    command -v parallel >/dev/null 2>&1 || { echo >&2 "I require 'parallel' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
	    command -v bc >/dev/null 2>&1 || { echo >&2 "I require 'bc' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
			command -v timeout >/dev/null 2>&1 || { echo >&2 "I require 'timeout' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
			osVersion="Linux"
	elif [[ "$(uname)" == "Darwin" ]];then
	    command -v jq >/dev/null 2>&1 || { echo >&2 "I require 'jq' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
	    command -v parallel >/dev/null 2>&1 || { echo >&2 "I require 'parallel' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
	    command -v bc >/dev/null 2>&1 || { echo >&2 "I require 'bc' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
	    command -v gtimeout >/dev/null 2>&1 || { echo >&2 "I require 'gtimeout' but it's not installed. Please install it and try again."; kill -s 1 "$TOP_PID"; }
			osVersion="Mac"
	fi
	echo "$osVersion"
}
# End of Function fncCheckDpnd

# Function fncValidateConfig
# Install packages on destination host
function fncValidateConfig {
	local config
	config="$1"
	if [[ -f "$config" ]]
	then
		echo "reading config ..."
		configId=$(jq --raw-output .id "$config")	
		configHost=$(jq --raw-output .host "$config")	
		configPort=$(jq --raw-output .port "$config")	
		configPath=$(jq --raw-output .path "$config")	
		if ! [[ "$configId" ]] || ! [[ $configHost ]] || ! [[ $configPort ]] || ! [[ $configPath ]]
		then
			echo "config is not correct"
			exit 1
		fi
	else
		echo "config file does not exist $config"
		exit 1
	fi
}
# End of Function fncValidateConfig

# Function fncCreateDir
# creates needed directory
function fncCreateDir {
	local dirPath
	dirPath="${1}"
	if [ ! -d "$dirPath" ]; then
		mkdir -p "$dirPath"
	fi
}
# End of Function fncCreateDir

# Function fncMainCFFindSubnet
# main Function for Subnet
function fncMainCFFindSubnet {
	local threads progressBar resultFile scriptDir configId configHost configPort configPath fileSize osVersion parallelVersion subnetsFile breakedSubnets network netmask downloadOrUpload tryCount downThreshold upThreshold vpnOrNot quickOrNot
	threads="${1}"
	progressBar="${2}"
	resultFile="${3}"
	scriptDir="${4}"
	configId="${5}"
	configHost="${6}"
	configPort="${7}"
	configPath="${8}"
	fileSize="${9}"
	osVersion="${10}"
	subnetsFile="${11}"
	tryCount="${12}"
	downThreshold="${13}"
	upThreshold="${14}"
	downloadOrUpload="${15}"
	vpnOrNot="${16}"
	quickOrNot="${17}"

	if [[ "$osVersion" == "Linux" ]]
	then
		v2rayCommand="v2ray"
	elif [[ "$osVersion" == "Mac"  ]]
	then
		v2rayCommand="v2ray-mac"
	else
		echo "OS not supported only Linux or Mac"
		exit 1
	fi
	
	parallelVersion=$(parallel --version | head -n1 | grep -Ewo '[0-9]{8}')
	defaultSubnetsFileUrl="https://raw.githubusercontent.com/MortezaBashsiz/CFScanner/main/config/cf.local.iplist"

	if [[ "$subnetsFile" == "NULL" ]]	
	then
		defaultSubnetsFileUrlResult=$(curl -I -L -s "$defaultSubnetsFileUrl" | grep "^HTTP" | grep 200 | awk '{ print $2 }')
		if [[ "$defaultSubnetsFileUrlResult" == "200" ]]
		then
			defaultSubnetsFile=$(curl -s "$defaultSubnetsFileUrl")
			echo "Reading subnets from $defaultSubnetsFileUrl"
			cfSubnetList="$defaultSubnetsFile"
		else
			echo "URL $defaultSubnetsFileUrl is not available. This URL contains the latest subnet file"
			echo "Reading subnets from file $scriptDir/../config/cf.local.iplist"
			cfSubnetList=$(cat "$scriptDir/../config/cf.local.iplist")
		fi
	else
		echo "Reading subnets from file $subnetsFile"
		cfSubnetList=$(cat "$subnetsFile")
	fi
	
	ipListLength="0"
	for subNet in ${cfSubnetList}
	do
		breakedSubnets=
		maxSubnet=24
		network=${subNet%/*}
		netmask=${subNet#*/}
		if [[ ${netmask} -ge ${maxSubnet} ]]
		then
		  breakedSubnets="${breakedSubnets} ${network}/${netmask}"
		else
		  for i in $(seq 0 $(( $(( 2 ** (maxSubnet - netmask) )) - 1 )) )
		  do
		    breakedSubnets="${breakedSubnets} $( fncLongIntToStr $(( $( fncIpToLongInt "${network}" ) + $(( 2 ** ( 32 - maxSubnet ) * i )) )) )/${maxSubnet}"
		  done
		fi
		breakedSubnets=$(echo "${breakedSubnets}"|tr ' ' '\n')
		for breakedSubnet in ${breakedSubnets}
		do
			ipListLength=$(( ipListLength+1 ))
		done
	done

	passedIpsCount=0
	for subNet in ${cfSubnetList}
	do
		breakedSubnets=
		maxSubnet=24
		network=${subNet%/*}
		netmask=${subNet#*/}
		if [[ ${netmask} -ge ${maxSubnet} ]]
		then
		  breakedSubnets="${breakedSubnets} ${network}/${netmask}"
		else
		  for i in $(seq 0 $(( $(( 2 ** (maxSubnet - netmask) )) - 1 )) )
		  do
		    breakedSubnets="${breakedSubnets} $( fncLongIntToStr $(( $( fncIpToLongInt "${network}" ) + $(( 2 ** ( 32 - maxSubnet ) * i )) )) )/${maxSubnet}"
		  done
		fi
		breakedSubnets=$(echo "${breakedSubnets}"|tr ' ' '\n')
		for breakedSubnet in ${breakedSubnets}
		do
			fncShowProgress "$passedIpsCount" "$ipListLength"
			killall v2ray > /dev/null 2>&1
			ipList=$(fncSubnetToIP "$breakedSubnet")
	  	tput cuu1; tput ed # rewrites Parallel's bar
	  	if [[ $parallelVersion -gt 20220515 ]];
	  	then
	  	  parallel --ll --bar -j "$threads" fncCheckIPList ::: "$ipList" ::: "$progressBar" ::: "$resultFile" ::: "$scriptDir" ::: "$configId" ::: "$configHost" ::: "$configPort" ::: "$configPath" ::: "$fileSize" ::: "$osVersion" ::: "$v2rayCommand" ::: "$tryCount" ::: "$downThreshold" ::: "$upThreshold" ::: "$downloadOrUpload" ::: "$vpnOrNot" ::: "$quickOrNot"
	  	else
	  	  echo -e "${RED}$progressBar${NC}"
	  	  parallel -j "$threads" fncCheckIPList ::: "$ipList" ::: "$progressBar" ::: "$resultFile" ::: "$scriptDir" ::: "$configId" ::: "$configHost" ::: "$configPort" ::: "$configPath" ::: "$fileSize" ::: "$osVersion" ::: "$v2rayCommand" ::: "$tryCount" ::: "$downThreshold" ::: "$upThreshold" ::: "$downloadOrUpload" ::: "$vpnOrNot" ::: "$quickOrNot"
	  	fi
			killall v2ray > /dev/null 2>&1
			passedIpsCount=$(( passedIpsCount+1 ))
		done
	done
	sort -n -k1 -t, "$resultFile" -o "$resultFile"
}
# End of Function fncMainCFFindSubnet

# Function fncMainCFFindIP
# main Function for IP
function fncMainCFFindIP {
	local threads progressBar resultFile scriptDir configId configHost configPort configPath fileSize osVersion parallelVersion IPFile downloadOrUpload downThreshold upThreshold vpnOrNot quickOrNot
	threads="${1}"
	progressBar="${2}"
	resultFile="${3}"
	scriptDir="${4}"
	configId="${5}"
	configHost="${6}"
	configPort="${7}"
	configPath="${8}"
	fileSize="${9}"
	osVersion="${10}"
	IPFile="${11}"
	tryCount="${12}"
	downThreshold="${13}" 
	upThreshold="${14}"
	downloadOrUpload="${15}"
	vpnOrNot="${16}"
	quickOrNot="${17}"

	if [[ "$osVersion" == "Linux" ]]
	then
		v2rayCommand="v2ray"
	elif [[ "$osVersion" == "Mac"  ]]
	then
		v2rayCommand="v2ray-mac"
	else
		echo "OS not supported only Linux or Mac"
		exit 1
	fi

	parallelVersion=$(parallel --version | head -n1 | grep -Ewo '[0-9]{8}')

	cfIPList=$(cat "$IPFile")
	killall v2ray > /dev/null 2>&1
	tput cuu1; tput ed # rewrites Parallel's bar
	if [[ $parallelVersion -gt 20220515 ]];
	then
	  parallel --ll --bar -j "$threads" fncCheckIPList ::: "$cfIPList" ::: "$progressBar" ::: "$resultFile" ::: "$scriptDir" ::: "$configId" ::: "$configHost" ::: "$configPort" ::: "$configPath" ::: "$fileSize" ::: "$osVersion" ::: "$v2rayCommand" ::: "$tryCount" ::: "$downThreshold" ::: "$upThreshold" ::: "$downloadOrUpload" ::: "$vpnOrNot" ::: "$quickOrNot"
	else
	  echo -e "${RED}$progressBar${NC}"
	  parallel -j "$threads" fncCheckIPList ::: "$cfIPList" ::: "$progressBar" ::: "$resultFile" ::: "$scriptDir" ::: "$configId" ::: "$configHost" ::: "$configPort" ::: "$configPath" ::: "$fileSize" ::: "$osVersion" ::: "$v2rayCommand" ::: "$tryCount" ::: "$downThreshold" ::: "$upThreshold" ::: "$downloadOrUpload" ::: "$vpnOrNot" ::: "$quickOrNot"
	fi
	killall v2ray > /dev/null 2>&1
	sort -n -k1 -t, "$resultFile" -o "$resultFile"
}
# End of Function fncMainCFFindIP

clientConfigFile="https://raw.githubusercontent.com/MortezaBashsiz/CFScanner/main/config/ClientConfig.json"
subnetIPFile="NULL"

# Function fncUsage
# usage function
function fncUsage {
	if [[ "$osVersion" == "Mac" ]]
	then 
		echo -e "Usage: cfScanner [ -v YES/NO ]
			[ -m SUBNET/IP ] 
			[ -t DOWN/UP/BOTH ]
			[ -p <int> ] threads
			[ -n <int> ] trycount
			[ -c <configfile> ]
			[ -s <int> ] speed
			[ -r <int> ] randomness
			[ -d <int> ] download threshold
			[ -u <int> ] upload threshold
			[ -f <custome-ip-file> (if you chose IP mode)]
			[ -q YES/NO]
			[ -h ] help\n"
		exit 2
	elif [[ "$osVersion" == "Linux" ]]
	then
		echo -e "Usage: cfScanner [ -v|--vpn-mode YES/NO ]
			[ -m|--mode  SUBNET/IP ] 
			[ -t|--test-type  DOWN/UP/BOTH ]
			[ -p|--thread <int> ]
			[ -n|--tryCount <int> ]
			[ -c|--config <configfile> ]
			[ -s|--speed <int> ] 
			[ -r|--random <int> ]
			[ -d|--down-threshold <int> ]
			[ -u|--up-threshold <int> ]
			[ -f|--file <custome-ip-file> (if you chose IP mode)]
			[ -q|--quick YES/NO]
			[ -h|--help ]\n"
		 exit 2
	fi
}
# End of Function fncUsage

randomNumber="NULL"
downThreshold="1"
upThreshold="1"
osVersion="$(fncCheckDpnd)"
vpnOrNot="NO"
subnetOrIP="SUBNET"
downloadOrUpload="BOTH"
threads="4"
tryCount="1"
config="NULL"
speed="100"
quickOrNot="NO"

if [[ "$osVersion" == "Mac" ]]
then
	parsedArguments=$(getopt v:m:t:p:n:c:s:r:d:u:f:q:h "$@")
elif [[ "$osVersion" == "Linux" ]]
then
	parsedArguments=$(getopt -a -n cfScanner -o v:m:t:p:n:c:s:r:d:u:f:q:h --long vpn-mode:,mode:,test-type:,thread:,tryCount:,config:,speed:,random:,down-threshold:,up-threshold:,file:,quick:,help -- "$@")
fi

eval set -- "$parsedArguments"
if [[ "$osVersion" == "Mac" ]]
then
	while :
	do
		case "$1" in
			-v) vpnOrNot="$2" ; shift 2 ;;
			-m) subnetOrIP="$2" ; shift 2 ;;
			-t) downloadOrUpload="$2" ; shift 2 ;;
			-p) threads="$2" ; shift 2 ;;
			-n) tryCount="$2" ; shift 2 ;;
			-c) config="$2" ; shift 2 ;;
			-s) speed="$2" ; shift 2 ;;
			-r) randomNumber="$2" ; shift 2 ;;
			-d) downThreshold="$2" ; shift 2 ;;
			-u) upThreshold="$2" ; shift 2 ;;
			-f) subnetIPFile="$2" ; shift 2 ;;
			-q) quickOrNot="$2" ; shift 2 ;;
			-h) fncUsage ;;
			--) shift; break ;;
			*) echo "Unexpected option: $1 is not acceptable"
			fncUsage ;;
		esac
	done
elif [[ "$osVersion" == "Linux" ]]
then
	while :
	do
		case "$1" in
			-v|--vpn-mode) vpnOrNot="$2" ; shift 2 ;;
			-m|--mode) subnetOrIP="$2" ; shift 2 ;;
			-t|--test-type) downloadOrUpload="$2" ; shift 2 ;;
			-p|--thread) threads="$2" ; shift 2 ;;
			-n|--tryCount) tryCount="$2" ; shift 2 ;;
			-c|--config) config="$2" ; shift 2 ;;
			-s|--speed) speed="$2" ; shift 2 ;;
			-r|--random) randomNumber="$2" ; shift 2 ;;
			-d|--down-threshold) downThreshold="$2" ; shift 2 ;;
			-u|--up-threshold) upThreshold="$2" ; shift 2 ;;
			-f|--file) subnetIPFile="$2" ; shift 2 ;;
			-q|--quick) quickOrNot="$2" ; shift 2 ;;
			-h|--help) fncUsage ;;
			--) shift; break ;;
			*) echo "Unexpected option: $1 is not acceptable"
			fncUsage ;;
		esac
	done
fi

validArguments=$?
if [ "$validArguments" != "0" ]; then
  echo "error validate"
  exit 2
fi

if [[ "$vpnOrNot" != "YES" && "$vpnOrNot" != "NO" ]] 
then
	echo "Wrong value: $vpnOrNot Must be YES or NO"
	exit 2
fi
if [[ "$subnetOrIP" != "SUBNET" && "$subnetOrIP" != "IP" ]] 
then
	echo "Wrong value: $subnetOrIP Must be SUBNET or IP"
	exit 2
fi
if [[ "$downloadOrUpload" != "DOWN" && "$downloadOrUpload" != "UP" && "$downloadOrUpload" != "BOTH" ]] 
then
	echo "Wrong value: $downloadOrUpload Must be DOWN or UP or BOTH"
	exit 2
fi

if [[ "$subnetIPFile" != "NULL" ]]
then
	if ! [[ -f "$subnetIPFile" ]]
	then
		echo "file does not exists: $subnetIPFile"
		exit 1
	fi
fi

now=$(date +"%Y%m%d-%H%M%S")
scriptDir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
resultDir="$scriptDir/result"
resultFile="$resultDir/$now-result.cf"
tempConfigDir="$scriptDir/tempConfig"
filesDir="$tempConfigDir"

uploadFile="$filesDir/upload_file"

configId="NULL"
configHost="NULL"
configPort="NULL"
configPath="NULL"

progressBar=""

export GREEN='\033[0;32m'
export BLUE='\033[0;34m'
export RED='\033[0;31m'
export ORANGE='\033[0;33m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

fncCreateDir "${resultDir}"
fncCreateDir "${tempConfigDir}"
echo "" > "$resultFile"

if [[ "$config" == "NULL"  ]]
then
	echo "updating config"
	configRealUrlResult=$(curl -I -L -s "$clientConfigFile" | grep "^HTTP" | grep 200 | awk '{ print $2 }')
	if [[ "$configRealUrlResult" == "200" ]]
	then
		curl -s "$clientConfigFile" -o "$scriptDir"/config.default
		echo "config.default updated with $clientConfigFile"
		echo ""
		config="$scriptDir/config.default"
		cat "$config"
	else
		echo ""
		echo "config file is not available $clientConfigFile"
		echo "use your own"
		echo ""	
		exit 1
	fi
else
	echo ""
	echo "using your own config $config"
	cat "$config"
	echo ""
fi

fileSize="$(( 2*speed*1024 ))"
if [[ "$downloadOrUpload" == "DOWN" || "$downloadOrUpload" == "BOTH" ]]
then
	echo "You are testing download"
fi
if [[ "$downloadOrUpload" == "UP" || "$downloadOrUpload" == "BOTH" ]]
then
	echo "You are testing upload"
	echo "making upload file by size $fileSize Bytes in $uploadFile"
	ddSize="$(( 2*speed ))"
	dd if=/dev/random of="$uploadFile" bs=1024 count="$ddSize" > /dev/null 2>&1
fi

fncValidateConfig "$config"

if [[ "$subnetOrIP" == "SUBNET" ]]
then
	fncMainCFFindSubnet	"$threads" "$progressBar" "$resultFile" "$scriptDir" "$configId" "$configHost" "$configPort" "$configPath" "$fileSize" "$osVersion" "$subnetIPFile" "$tryCount" "$downThreshold" "$upThreshold" "$downloadOrUpload" "$vpnOrNot" "$quickOrNot"
elif [[ "$subnetOrIP" == "IP" ]]
then
	fncMainCFFindIP	"$threads" "$progressBar" "$resultFile" "$scriptDir" "$configId" "$configHost" "$configPort" "$configPath" "$fileSize" "$osVersion" "$subnetIPFile" "$tryCount" "$downThreshold" "$upThreshold" "$downloadOrUpload" "$vpnOrNot" "$quickOrNot"
else
	echo "$subnetOrIP is not correct choose one SUBNET or IP"
	exit 1
fi
