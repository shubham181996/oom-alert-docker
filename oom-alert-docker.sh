#!/bin/bash

SOCKET="/var/run/docker.sock"
API_URL="http://localhost"
LOG_FILE="/root/shell_scripts/container_Resource_OOM_Pressure_Monitor/logs/monitor-new.log"

#Check Dependencies

for cmd in curl jq; do
	if  ! command -v "$cmd" ; then
		echo "ERROR: $cmd is not installed"
		exit 1
	fi
done

#Check Docker Socket

if [ ! -S "$SOCKET" ]; then
	echo echo "ERROR: Docker socket not found: $SOCKET"
	exit 1 
fi

log_message(){
        echo "$(date '+%F %T') | $1" | tee -a "$LOG_FILE"
}

#GET DOCKER API VERSION

get_api_version(){
	local response
	response=$(curl -fsS --max-time 5 --unix-socket "$SOCKET" "$API_URL/version") || { 
		log_message "ERROR: Cannot connect to Docker API" 	
		retrun 1
	}

	API_VERSION=$(jq -r '.ApiVersion // empty' <<< "$response")
	if [[ -z "$API_VERSION" ]]; then
		log_message "ERROR: Unable to detect API version"
		return 1
	fi
}

#get_api_version

#GET_RUNNING_CONTAINER

get_container(){
	curl -fsS --max-time 10 --unix-socket "$SOCKET" "$API_URL/v{$API_VERSION}/containers/json"
}
#get_container

#Get individual container information

get_container_details(){
	local container_id="$1"
	curl -fsS --max-time 10 --unix-socket "$SOCKET" "$API_URL/v{$API_VERSION}/containers/${container_id}/json"
}
#get_container_details

#Display Container information

monitor_conatiners(){
	local containers
	containers=$(get_container) || {
		log_message "ERROR: Failed to retrieve containers"
	return 1
	}
	
	
	if [[ "$(jq 'length' <<< "$containers")" -eq 0 ]]; then
		log_message "No Running containers found"
		retrun 0
	fi

	 printf "\n%-20s %-18s %-12s %-12s %-12s\n" \
        "CONTAINER" "CONTAINER ID" "PID" "PRIORITY" "Status"

	printf '%s\n' "----------------------------------------------------------------------------------------"

	while IFS=$'\t' read -r id name image; do
		local details
		local pid
		local priority
		local memory

		details=$(get_container_details "$id") || {
			log_message "WARNING: Cannot inspect $name"
		continue
		}
		pid=$(jq -r '.State.Pid // 0'  <<< "$details")

		priority=$(jq -r '.Config.Labels["monitor.priority"] // "normal"' <<< "$details")

		memory=$(docker stats --no-stream --format "{{.MemPerc}}" "$id")

		printf "%-20s %-18s %-12s %-12s %-12s\n" \
                         "$name" "${id:0:12}" "$pid" "$priority" "$memory"
		log_message "Container=$name | ID=${id:0:12} | PID=$pid | Priority=$priority | Mem=$memory"
	done < <(jq -r '.[] | [.id,(.Names[0] | ltrimstr("/")), .Image] | @tsv' <<< "$containers"
)

}

# ------------------------------------------
# Main
# ------------------------------------------

main() {

    log_message "Docker OOM Monitor Stage 1 Started"

    get_api_version || exit 1

    monitor_conatiners

    log_message "Stage 1 Execution Completed"
}

main
