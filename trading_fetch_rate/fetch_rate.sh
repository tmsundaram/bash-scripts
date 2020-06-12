#!/bin/bash
#################################################################
##Purpose: Fetch market price of given material and sent alert ##
##Author : TM Sundaram                                         ##
##Date   : 2020-06-12                                          ##
##Version: 1.0.3                                               ##
##Test   : Tested on Ubuntu 18.04                              ##
#################################################################

##Global variables
OK_STATE=0
FAILED_STATE=1
DDIR="$HOME/TRADING"
CDIR=$(dirname $0)
SDIR=$(cd $CDIR && pwd)
TEMP="$DDIR/tmp"
JQ_CMD="$SDIR/jq"
SYMBOL_DB="$SDIR/symbols.db"
LOG="$TEMP/logs/script_output.log"
TIME_ZONE="Asia/Kolkata"
KEY_FILE="$HOME/keys/metals-api.key"
COUNTER_FILE="$DDIR/tmp/.counter"
COUNTER_MAX=50

##User variables
EMAIL_FROM="ShareM Robot <author.tab@gmail.com>"
EMAIL_TO="sundaram.green4@gmail.com"
EMAIL_SUB="Market rates - $(TZ=${TIME_ZONE} date +"%Y-%m-%d %T")"
EMAIL_ERR_SUB="FetchRate script failure - $(TZ=${TIME_ZONE} date +"%Y-%m-%d %T")"
SEND_EMAIL_ON_FAILURE="true"
MARGIN_PRICE="500" ##value of change in price should notified (latest mode)

function log_msg() {
 echo -e "$(TZ=${TIME_ZONE} date +"%Y-%m-%d %T") >> $@" >> $LOG
}

function mk_dirs() {
	#[ ! -d $TEMP ] && mkdir -p $TEMP
	[ ! -d "$TEMP/logs" ] && mkdir -p $TEMP/logs
	[ ! -s "$COUNTER_FILE" ] && echo "0" > $COUNTER_FILE
}

function send_email() {
	local FUNC=send_email
	local RET=$FAILED_STATE
	local EMAIL_SUB="$1"
	local MAIL_DATA=$2
	
	mailx --subject="${EMAIL_SUB}" -a "From: ${EMAIL_FROM}" -t ${EMAIL_TO} < $MAIL_DATA
	if [ $? -eq $OK_STATE ]; then
		log_msg "$FUNC" "email has been sent"
		RET=$OK_STATE
	else
		log_msg "$FUNC" "error sending email"
	fi

return $RET
}

function error_notify() {
local FUNC=error_notify
local MAIL_DATA="$TEMP/OUT_error.msg"
tail -12 $LOG > $MAIL_DATA
send_email "${EMAIL_ERR_SUB}" $MAIL_DATA
RET=$?

return $RET
}
function build_URL() {
##should return only URL as output##
local FUNC=build_URL
local RET=$FAILED_STATE
local MODE=$1
local BASE=$2
local SYMBOL=$3
local ACCESS_KEY=$4

case $MODE in
	latest) if [ ! -z $SYMBOL ]; then
				echo "https://metals-api.com/api/latest?base=$BASE&symbols=$SYMBOL&access_key=$ACCESS_KEY"
			else
				echo "https://metals-api.com/api/latest?base=$BASE&access_key=$ACCESS_KEY"
			fi
			RET=$OK_STATE
			;;
		*) RET=$FAILED_STATE ;;
esac

return $RET
}

function api_call() {
	local FUNC=api_call
	local RET=$FAILED_STATE
	local URL=$1
	local COUNTER_VALUE=$2
	local KEY_COUNT=$3
	local OUT_FILE="$TEMP/OUT_${MODE}.txt"
	curl --location --request GET --output $OUT_FILE --create-dirs "${URL}"
	if [ $? -eq $OK_STATE ]; then
		log_msg "$FUNC" "api request been sent"
	else
		log_msg "$FUNC" "error sending api request"
		RET=$OK_STATE
	fi

return $RET
}

function validate_api_data() {
	local FUNC=validate_api_data
	local RET=$FAILED_STATE
	local OUT_FILE="$TEMP/OUT_${MODE}.txt"
	RES=$($JQ_CMD '.success' $OUT_FILE)
	if [ $RES == "true" ]; then
		RET=$OK_STATE
	elif [ $RES == "false" ]; then
		RET=$($JQ_CMD '.error.code' $OUT_FILE)
		RES=$($JQ_CMD '"ErrCode:" + (.error.code|tostring) + " - " + .error.type + " - " + .error.info'  $OUT_FILE)
		log_msg "$FUNC" "API error details: $RES"
	else
		RET=$FAILED_STATE
		log_msg "$FUNC" "Unknown error with API response"
	fi
return $RET
}

function counter_action() {
	local FUNC=counter_action
	local RET=$FAILED_STATE
	local KEY_CNT=$(wc -l $KEY_FILE|awk '{print $1}')
	local COUNTER_VALUE=$(cat $COUNTER_FILE)
	local CURRENT_KEY=$3
	case $1 in 
		stepup) if [ $COUNTER_VALUE	-lt $(echo "($KEY_CNT * $COUNTER_MAX)-1"|bc -l) ]; then
					echo "$COUNTER_VALUE + 1" |bc -l > $COUNTER_FILE
				else
					echo "0" > $COUNTER_FILE
					log_msg "$FUNC" "(action:stepup) Max API request reached for $KEY_CNT keys, so reset counter to Zero"
				fi
				RET=$OK_STATE
				;;
		rotate) 
				#while [ $CURRENT_KEY -le $KEY_CNT ]
				#do
					if [ $CURRENT_KEY -eq $KEY_CNT ]; then
						log_msg "$FUNC" "(action:rotate) - reached last key, so move to first key"
						$CURRENT_KEY=0
					fi
					COUNTER_VALUE=$(echo "$CURRENT_KEY * $MAX_COUNTER"|bc -l)
					echo $COUNTER_VALUE > $COUNTER_FILE
					RET=$CURRENT_KEY
				#done
				;;
			*) log_msg "$FUNC" "Invalid input for counter_action"
				;;
	esac
return $RET
}

function parse_data() {
	local FUNC=parse_data
	local RET=$FAILED_STATE
	local MODE=$1
	local OUT_FILE="$TEMP/OUT_${MODE}.txt"
	[ ! -d $DDIR/$MODE ] && mkdir -p $DDIR/$MODE
	
	case $MODE in
		latest) 
			QTIME=$(TZ=${TIME_ZONE} date -d@$($JQ_CMD '.timestamp' $OUT_FILE) +%Y-%m-%d-%H%M%S)
			QBASE=$($JQ_CMD '.base' $OUT_FILE |sed 's/"//g')
			QSYM_CNT=$($JQ_CMD '.rates|keys|length' $OUT_FILE)
			QSYM_ARR=($($JQ_CMD '.rates|keys[]' $OUT_FILE |sed 's/"//g'))
			local j=0
			while [ $j -lt $QSYM_CNT ];
			do
				##Capture each symbol/code value
				SYM=${QSYM_ARR[$j]}
				DATA_FILE="$DDIR/$MODE/data_${MODE}_${SYM}"
				[ ! -f ${DATA_FILE} ] && touch ${DATA_FILE}
				SYM_VALUE=$($JQ_CMD ".rates.$SYM" $OUT_FILE)
				RES="$QTIME,$QBASE,$SYM,$SYM_VALUE" 
				echo "$RES" >> ${DATA_FILE}
				j=$(expr $j + 1)
			done
			;;
		*) log_msg "$FUNC" "Invalid MODE value"
			;;
	esac
	if [ $? -eq $OK_STATE ]; then
		log_msg "$FUNC" "data parse succeeded"
		RET=$OK_STATE
	else
		log_msg "$FUNC" "failed at step parse_data"
	fi

return $RET
}

function notify_logic_latest() {
	local FUNC="notify_logic"
	local RET=$FAILED_STATE
	local SYM=$1
	local DIFF_PRICE=$2
	local ALERT_FILE="$TEMP/.latest_alert_true"
	case $SYM in 
		XAU) if (( $(echo "$DIFF_PRICE >= $MARGIN_PRICE"|bc -l) )) ; then
				touch $ALERT_FILE
				RET=$OK_STATE
			elif (( $(echo "$DIFF_PRICE <= -${MARGIN_PRICE}"|bc -l) )); then
				touch $ALERT_FILE
				RET=$OK_STATE
			else
				log_msg "$FUNC" "$SYM - alert condition not met"
			fi
			;;
		*)	RET=$OK_STATE ;;
	esac
return $RET
}
function post-op() {
 local FUNC=post-op
 local RET=$FAILED_STATE
 local MODE=$1
 local BASE=$2
 local SYMBOL=$3
 
 case $MODE in 
	latest) ##process data and
			SYM_ARR=($(echo $SYMBOL|sed 's/,/ /g'))
			SYM_CNT=${#SYM_ARR[@]}
			OUT_TMP="$TEMP/OUT_${MODE}_tmp"
			ALERT_FILE="$TEMP/.latest_alert_true"
			rm -f $ALERT_FILE
			echo -e "Mode: ${MODE}\nBase: $BASE" > $OUT_TMP
			local j=0
			while [ $j -lt $SYM_CNT ]; do
				SYM=${SYM_ARR[$j]}
				SYM_NAME=$(grep -w -m1 $SYM $SYMBOL_DB |cut -d" " -f2-)
				DATA_FILE="$DDIR/$MODE/data_${MODE}_${SYM}"
				RES=$(tail -n-1 $DATA_FILE)
				C_TIME=$(echo $RES|awk -F, '{print $1}')
				C_PRICE=$(echo $RES|awk -F, '{print $4}')
				RES=$(tail -n-2 $DATA_FILE|head -1)
				P_TIME=$(echo $RES|awk -F, '{print $1}')
				P_PRICE=$(echo $RES|awk -F, '{print $4}')
				if (( $(echo "$P_PRICE == $C_PRICE" |bc -l) )); then
					log_msg "$FUNC" "$SYM ($SYM_NAME) no change in price"
				else
					echo -e "\nUnit Code: $SYM ($SYM_NAME)\n\t=> Previous: $P_TIME\t$P_PRICE\n\t=> Current: $C_TIME\t$C_PRICE" >> $OUT_TMP
					##Find difference price##
					DIFF_PRICE=$(echo "$C_PRICE - $P_PRICE"|bc -l)
					if (( $(echo "$DIFF_PRICE > 0"|bc -l) )) ; then
						echo -e "\tDiff(Rs): Up/Sell +${DIFF_PRICE}" >> $OUT_TMP
					elif (( $(echo "$DIFF_PRICE < 0"|bc -l) )) ; then
						echo -e "\tDiff(Rs): Down/Buy ${DIFF_PRICE}" >> $OUT_TMP
					else
						echo -e "\tDiff(RS): Unknown-Change ${DIFF_PRICE}" >> $OUT_TMP
					fi
					[ ! -f $ALERT_FILE ] && notify_logic_latest $SYM $DIFF_PRICE
				fi
				j=$(expr $j + 1)
			done
			if [ $? -eq $OK_STATE ] && [ -s "$OUT_TMP" ]; then
				##check and send email
				if [ -f $ALERT_FILE ]; then
					send_email "${EMAIL_SUB}" $OUT_TMP
					RET=$?
				else
					log_msg "$FUNC" "not sending alert"
					RET=$OK_STATE
				fi
			else
				log_msg "$FUNC" "failed to process data"
			fi
			;;
		*) log_msg "$FUNC" "Invalid mode"
			;;
 esac
return $RET
}

function do-op() {
	local FUNC=do-op
	local RET=$FAILED_STATE
	local MODE=$1
	local BASE=$2
	local ACCESS_KEY=""
	local SYMBOL=$3

	##Retrive access_key and fetch data
	local KEY_CNT=$(wc -l $KEY_FILE|awk '{print $1}')
	local J=1
	while [ $J -le $KEY_CNT ];
	do
		local COUNTER_VALUE=$(cat $COUNTER_FILE)
		if [ $COUNTER_VALUE -lt $(echo "$COUNTER_MAX * $J" |bc -l) ]; then
			ACCESS_KEY=$(sed -n ${J}p $KEY_FILE)
			if [ $? -eq $OK_STATE ]; then
				##Build URL
				RES=$(build_URL $MODE $BASE $SYMBOL $ACCESS_KEY)
				if [ $? -eq $OK_STATE ]; then
					URL=$RES
					##Query API endpoint
					api_call $URL $COUNTER_VALUE
					if [ $? -eq $OK_STATE ]; then
						validate_api_data
						case $? in
						0) 	counter_action stepup 
							parse_data $MODE
							RET=$?
							break
							;;
						104) counter_action rotate $J
							 J=$?
							 ROTATE_BAL=$(echo "$KEY_CNT - 1" | bc -l)
							 if [ $ROTATE_BAL -eq "0" ]; then
								log_msg "$FUNC" "(action:rotate) all keys reacehd request limit, no more keys to try"
								J=$KEY_CNT
							 fi
							 ;;
						 *) log_msg "$FUNC" "failed at step validate_api_data"
							;;
						esac
					else
						log_msg "$FUNC" "failed at step api_call for key:$J"
					fi
				else
					log_msg "$FUNC" "failed at step build_URL"
					break
				fi
			else
				log_msg "$FUNC" "failed to fetch access_key"
			fi
		else
			log_msg "$FUNC" "API request count=${COUNTER_VALUE}, Not using key $J"
		fi
	J=$(echo "$J + 1"|bc -l)
	done
return $RET
}

function pre-op() {
 local FUNC=pre-op
 local RET=$FAILED_STATE
 local MODE=$1
 local BASE=$2
 local SYMBOL=$3
 
 if [ -s $KEY_FILE ]; then
	 ##mode dependant checks
	 case $MODE in
		latest) if [ -f "$(which bc)" ] && [ -f "$(which curl)" ] && [ -f "$(which mailx)" ] && [ -f "$JQ_CMD" ]; then
					RET=$OK_STATE
				else
					log_msg "$FUNC" "missing commands 'bc' 'curl' 'mailx' 'jq'"
				fi
				;;
		*) 	log_msg "$FUNC" "Invalid mode selected"
				;;
	 esac
else
	log_msg "$FUNC" "Access_key's not found at $KEY_FILE"
fi	

return $RET
}

function help() {
	local FUNC=help
	local RET=$FAILED_STATE
	echo -e "\tSupported arguments"
	echo -e "\t*\t-b [code] - base currency/material code, Ex: INR"
	echo -e "\t*\t-m [latest] - query mode/type, supported values: latest"
	echo -e "\t*\t-s [code1,code2,..] - currency/material code to be queried seperated by comma. Ex: XAG,XAU" 
	echo -e "\t \t-h - Show this help message"
exit $FAILED_STATE
}

function main() {
 local FUNC=main
 local RET=$FAILED_STATE
 
 log_msg "$FUNC" "Started"
 
 if [ "$#" -ge 4 ]; then
	local RET=${FAILED_STATE}
	local MFLAG=$FAILED_STATE
	local BFLAG=$FAILED_STATE
	while getopts "hm:b:s:" opt ;
	do
		case $opt in
			h) help ;;
			m) MFLAG=${OK_STATE}; MODE=${OPTARG} ;;
			b) BFLAG=${OK_STATE}; BASE=${OPTARG} ;;
			s) SFLAG=${OK_STATE}; SYMBOL=${OPTARG} ;;
			*) help ;;
		esac
	done
	if [ $MFLAG -eq $OK_STATE ] && [ $BFLAG -eq $OK_STATE ] && [ $SFLAG -eq $OK_STATE ] ; then
		log_msg "$FUNC" "starting pre-op"
		pre-op $MODE $BASE $SYMBOL
		if [ $? -eq $OK_STATE ]; then
			log_msg "$FUNC" "starting do-op"
			do-op $MODE $BASE $SYMBOL
			if [ $? -eq $OK_STATE ]; then
				log_msg "$FUNC" "starting post-op"
				post-op $MODE $BASE $SYMBOL
				if [ $? -eq $OK_STATE ] ; then
					RET=$OK_STATE
					log_msg "$FUNC" "post-op succeeded"
				else
					log_msg "$FUNC" "failed in post-op"
					[ $SEND_EMAIL_ON_FAILURE == "true" ] && error_notify
				fi
			else
				log_msg "$FUNC" "failed in do-op : $RES"
				[ $SEND_EMAIL_ON_FAILURE == "true" ] && error_notify
			fi
		else
			log_msg "$FUNC" "failed in pre-op"
		fi			
	else
		log_msg "$FUNC" "Fault: Missing required parameters, must supply base, mode and symbol values"
		help
	fi
 else
	log_msg "$FUNC" "Fault: Missing minimum required parameters"
	help
 fi

log_msg "$FUNC" "ended with exit code $RET"

return $RET
}

##Beginning of script##
mk_dirs

log_msg "---------------------------------------"
log_msg "Program: $0" "Started"
log_msg "---------------------------------------"
main "$@"
RET=$?
if [ $RET -eq $OK_STATE ]; then
	log_msg "Program: $0" "ended with success status"
else
	log_msg "Program: $0" "ended with failure status"
fi
log_msg "-----X---------X------------X--------\n\n"
exit $RET
