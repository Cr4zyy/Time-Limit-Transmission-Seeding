#!/bin/bash

#VARIABLES set these before you start!
# Transmission config
REMOTE="transmission-remote 127.0.0.1:9091 -n USER:PASSWD" # Change USER, PASSWD and IP as required
# filter what you want
TORRENT_FILTER="iu" # no whitespaces: i (idle), u (uploading), d (downloading)
TORRENT_FILTER_SPECIAL="" # white space seperated: l:label (torrent has "label"), n:str (name contains "str"), r:ratio (minimum upload ratio)
#you can negate a filter by prefixing ~, "~l:alwaysseed" would ignore all torrents with the label 'alwaysseed'

CHECK_ADDED_DATE=1 # Not all versions report the "Seconds Seeding" value, so set to 1, to use "Added Date", this will also check for "Done Date" if set for a more accurate seeding time.
CHECK_ERRORED_TORRENTS=1 # You can either check, 1, or skip, 0, any torrents that are showing any errors currently. 

# The state you want the torrent to be set once time is completed
TORRENT_FINAL_STATE="stop" # "stop" ,"remove" (from transmission) or "remove-and-delete" (!this deletes the downloaded data!)
FILE_DELETE=0 # If above is remove-and-delete, set this to 1, it only applies with r-a-d set, really make sure you want this script to delete the downloaded data

# How long to seed for, these values are combined!
SEED_DAYS=35
SEED_HOURS=0

# MISC VAR
ENABLE_DEBUG=0 # DEBUG WILL NOT STOP/DELETE TORRENT FILES
LOGLINES=1000 # 0 to disable log line limit, useful for debug spam
LOG=$(dirname $0) # log into same dir as script
LOG+="/time_limit.log"


### ---- script begin ---- ###
log() {
    local LEVEL="$1"
    shift

    if [[ "$LEVEL" == "DEBUG" && "$ENABLE_DEBUG" -ne 1 ]]; then
        return
    elif [[ "$LEVEL" == "INFO" || "$LEVEL" == "WARN" ]]; then
        LEVEL="$LEVEL "
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] | [$LEVEL] | $*" | tee -a "$LOG"
}

log INFO "=== $(date) | Transmission seeding time limit started ==="

case "$TORRENT_FINAL_STATE" in
  stop|remove|remove-and-delete)
    ;;
  *)
    log ERROR "Invalid TORRENT_FINAL_STATE: $TORRENT_FINAL_STATE"
    log ERROR "Must be 'stop', 'remove' or 'remove-and-delete'"
    exit 1
    ;;
esac
if [[ "$TORRENT_FINAL_STATE" == "remove-and-delete" && "$FILE_DELETE" -eq 1 ]]; then
    log WARN "=== REMOVE-AND-DELETE and FILE_DELETE ENABLED ==="
    log WARN "Torrent data will be deleted once seed time limit is exceeded"
elif [[ "$TORRENT_FINAL_STATE" == "remove-and-delete" && "$FILE_DELETE" -eq 0 ]]; then
    #just a fail safe warning
    log WARN "=== REMOVE-AND-DELETE ENABLED ==="
    log ERROR "Enabling remove-and-delete requires FILE_DELETE to be set to 1"
    log WARN "Be aware this setting will delete the downloaded data and not just remove it from your client"
    exit 1
elif [[ "$TORRENT_FINAL_STATE" != "remove-and-delete" && "$FILE_DELETE" -eq 1 ]]; then
    log ERROR "=== FILE_DELETE NEEDS REMOVE-AND-DELETE ==="
    log ERROR "Enabling FILE_DELETE will do nothing without remove-and-delete being set in TORRENT_FINAL_STATE"
    exit 1
fi

# split filters
COMBINE_FILTER="${TORRENT_FILTER} ${TORRENT_FILTER_SPECIAL}"
read -ra FILTERS <<< "$COMBINE_FILTER"
TRANS_REMOTE=( "${REMOTE[@]}" )
for f in "${FILTERS[@]}"; do
    TRANS_REMOTE+=("-F" "$f")
done

# time convert
SEED_DAYS_SECONDS=$(( SEED_DAYS * 86400 ))   # 86400 seconds in a day
SEED_HOURS_SECONDS=$(( SEED_HOURS * 3600 ))  # 3600 seconds in an hour
SEED_TIME_LIMIT=$(( SEED_DAYS_SECONDS + SEED_HOURS_SECONDS ))

log DEBUG "=== config variables ==="
log DEBUG "REMOTE :: $REMOTE"
log DEBUG "TORRENT_FILTER :: $TORRENT_FILTER"
log DEBUG "TORRENT_FILTER_SPECIAL :: $TORRENT_FILTER_SPECIAL"
log DEBUG "CHECK_ADDED_DATE :: $CHECK_ADDED_DATE"
log DEBUG "CHECK_ERRORED_TORRENTS :: $CHECK_ERRORED_TORRENTS"
log DEBUG "TORRENT_FINAL_STATE :: $TORRENT_FINAL_STATE"
log DEBUG "FILE_DELETE :: $FILE_DELETE"
log DEBUG "SEED_DAYS :: $SEED_DAYS"
log DEBUG "SEED_HOURS :: $SEED_HOURS"
log DEBUG "=== generated variables ==="
log DEBUG "COMBINE_FILTER :: $COMBINE_FILTER"
log DEBUG "TRANS_REMOTE :: ${TRANS_REMOTE[@]}"
log DEBUG "SEED_TIME_LIMIT :: $SEED_TIME_LIMIT"
log DEBUG "=== variables end ==="

# list torrents matching filter
log DEBUG "Getting list of torrents matching filters"
TORRENT_LIST=$(${TRANS_REMOTE[*]} -l)

TORRENT_IDS=$(echo "$TORRENT_LIST" | awk 'NR > 1 && $1 ~ /^[0-9]+$/ { print $1 }')
if [[ $CHECK_ERRORED_TORRENTS -eq 1 ]]; then
    log DEBUG "Checking for any errored torrents and adding them"
    ERROR_TORRENT_IDS=$(echo "$TORRENT_LIST" | awk 'NR > 1 && $1 ~ /^[0-9]+\*$/ { gsub(/\*/, "", $1); print $1 }')
    log DEBUG "Found $(echo "$ERROR_TORRENT_IDS" | wc -w) errored torrents"
fi
ALL_IDS="$TORRENT_IDS $ERROR_TORRENT_IDS"
log INFO "Starting processing of $(echo "$ALL_IDS" | wc -w) different torrents"
log DEBUG "ID List: $(echo "$ALL_IDS" | paste -sd ' ' -)"

EXCEEDED_IDS=()
NO_SEED_TIME_IDS=()
NOW=$(date +%s )

for ID in $ALL_IDS; do
    log DEBUG "Torrent ID: $ID | Processing |"
    ID_JSON=$($REMOTE -j -t $ID -i)
    
    ID_SEEDTIME=$(echo "$ID_JSON" | jq '.arguments.torrents[0].secondsSeeding')
    ID_ADDEDTIME=$(echo "$ID_JSON" | jq '.arguments.torrents[0].addedDate')
    ID_DONETIME=$(echo "$ID_JSON" | jq '.arguments.torrents[0].doneDate')
    
    TIME_SINCE_ADD=""
    
    if [[ $CHECK_ADDED_DATE -eq 1 && $ID_SEEDTIME -lt $SEED_TIME_LIMIT ]]; then
    
        if [[ $ID_SEEDTIME -gt 0 ]]; then
            if [[ $ID_SEEDTIME -gt $SEED_TIME_LIMIT ]]; then
                EXCEEDED_IDS+=("$ID")
                log DEBUG "Torrent ID: $ID | Will $TORRENT_FINAL_STATE | Exceeds secondsSeeding: $ID_SEEDTIME"
            else
                log DEBUG "Torrent ID: $ID | No action | secondsSeeding $ID_SEEDTIME is less than $SEED_TIME_LIMIT limit"
            fi
        else
    
            # doneDate more accurate for actual seeding time
            if [[ $ID_DONETIME -gt $ID_ADDEDTIME ]]; then
                TIME_SINCE_ADD=$(( NOW - ID_DONETIME ))
            else
                TIME_SINCE_ADD=$(( NOW - ID_ADDEDTIME ))
            fi
            
            if [[ $TIME_SINCE_ADD -gt $SEED_TIME_LIMIT ]]; then
                log DEBUG "Torrent ID: $ID | Will $TORRENT_FINAL_STATE | Exceeds      addedDate: $TIME_SINCE_ADD"
                NO_SEED_TIME_IDS+=("$ID")
            else
                log DEBUG "Torrent ID: $ID | No action | TIME_SINCE_ADD $TIME_SINCE_ADD is less than $SEED_TIME_LIMIT limit"
            fi
        fi
        
    elif [[ $ID_SEEDTIME -gt $SEED_TIME_LIMIT ]]; then
    
        EXCEEDED_IDS+=("$ID")
        log DEBUG "Torrent ID: $ID | Will $TORRENT_FINAL_STATE | Exceeds secondsSeeding: $ID_SEEDTIME"
        
    else
        log DEBUG "Torrent ID: $ID | No action | secondsSeeding $ID_SEEDTIME is less than $SEED_TIME_LIMIT limit"
    fi
    log DEBUG "____________________________________________________"

done



if [[ ${#EXCEEDED_IDS[@]} -eq 0 && ${#NO_SEED_TIME_IDS[@]} -eq 0 ]]; then
    log INFO "No torrents matching filters are older than the time limit."
    log DEBUG "ID Lists: ${EXCEEDED_IDS[@]} | ${NO_SEED_TIME_IDS[@]}"
else
    log DEBUG "=== DEBUG is NOT changing the following torrents ==="
    
    log INFO "The following torrent IDs have exceeded the set time limit:"
    log INFO "${EXCEEDED_IDS[@]}"
    
    if [[ $CHECK_ADDED_DATE -eq 1 ]]; then
        log INFO "These IDs do not show a 'Seconds Seeding' value. Instead they were checked against their 'Added Date' or 'Done Date's"
        log INFO "${NO_SEED_TIME_IDS[@]}"
    fi

    PROCESSED_IDS=("${EXCEEDED_IDS[@]}" "${NO_SEED_TIME_IDS[@]}")
    COMMA_IDS=$(IFS=,; echo "${PROCESSED_IDS[*]}")

    log DEBUG "=== DEBUG is NOT changing the following torrents ==="
    log DEBUG "IDs to $TORRENT_FINAL_STATE: ${EXCEEDED_IDS[@]} ${NO_SEED_TIME_IDS[@]}"
    log INFO "Applying '$TORRENT_FINAL_STATE' to all IDs listed above"

    log DEBUG "$REMOTE -t "$COMMA_IDS" --$TORRENT_FINAL_STATE"
    # only if debug off
    if [[ $ENABLE_DEBUG -eq 0 ]]; then
        $REMOTE -t "$COMMA_IDS" --$TORRENT_FINAL_STATE
    fi

    COUNT_ACTIONED=${#PROCESSED_IDS[@]}
    log DEBUG "=== DEBUG is NOT changing the following torrents ==="
    log INFO "Completed setting '$TORRENT_FINAL_STATE' status on $COUNT_ACTIONED torrents"
    log DEBUG "IDs processed: ${PROCESSED_IDS[@]}"
fi

if [[ $LINECOUNT -ne 0 ]]; then
    LINECOUNT=$(wc -l < $LOG)
    if [[ $LINECOUNT -gt $LOGLINES ]]; then
        echo "$(tail -$LOGLINES $LOG)" > "$LOG"
    fi
fi
