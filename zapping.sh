#!/bin/bash

print_help() {
	echo "Arguments:"
	echo " -h or --help: Prints this message"
	echo " -v or --verbose: Prints verbose messages"
	echo " -r or --record: Records the stream to a file instead of playing"
	echo " \"channel name\": Auto-plays the channel by its name"
}

# Read arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		-v|--verbose)
			VERBOSE=1
			shift # past argument
			;;
		-r|--record)
			RECORD=1
			shift # past argument
			;;
		-h|--help)
			print_help
			exit
			;;
		*)
			AUTO_CHANNEL=$1
			shift
			;;
	esac
done
echo "verbose: ${VERBOSE}"
echo "Record: ${RECORD}"
echo "Auto channel: $AUTO_CHANNEL"

# Constants
CONFIG_FILE="${HOME}/.config/zapping"
USER_AGENT="Zapping/bash-1.0"

# Check dependencies
case $OSTYPE in
	linux-gnu)
		echo "OS detected: GNU+Linux"
		;;
	darwin)
		echo "OS detected: macOS"
		if ! command -v gdate &> /dev/null
		then
			echo "This script requires gdate"
			exit
		fi
		;;
	*)
		echo "WARNING: OS \"${OSTYPE}\" not supported. Trying anyways."
		;;
esac
if ! command -v mpv &> /dev/null
then
	echo "This script requires mpv"
	MISSING_DEPS=1
fi
if ! command -v jq &> /dev/null
then
	echo "This script requires jq"
	MISSING_DEPS=1
fi
if ! command -v http &> /dev/null
then
	echo "This script requires HTTPie"
	MISSING_DEPS=1
fi
if ! command -v uuidgen &> /dev/null
then
	echo "This script requires uuidgen"
	MISSING_DEPS=1
fi
if [ -n "${RECORD}" ] && ! command -v ffmpeg &> /dev/null
then
	echo "This script requires ffmpeg to record"
	MISSING_DEPS=1
fi
if [ -n "${MISSING_DEPS}" ]
then
	exit
fi

# Functions

to_array() {
	IFS=$'\n' read -d '' -r -a "$1"
}

join_arrays() {
	local -n FIRST_ARRAY=$1
	local -n SECOND_ARRAY=$2
	local i
	for (( i = 0; i < ${#FIRST_ARRAY[*]}; ++i))
	do
		echo "${FIRST_ARRAY[$i]}" "${SECOND_ARRAY[$i]}"
	done
}

zdate() {
	if type -t gdate &>/dev/null
	then
		gdate "$@"
	else
		date "$@"
	fi
}

timestamp_to_hh_mm() {
	zdate -d "@$1"  +'%H:%M'
}

zargs() {
	while IFS=$'$\n' read -r line; do
		"$1" "$line"
	done
}

echo_verbose() {
	if [ -n "${VERBOSE}" ]
	then
		echo "$@"
	fi
}

# Export functions
export -f timestamp_to_hh_mm

# Load token from file?
if [ -f "${CONFIG_FILE}" ]
then
	ZAPPING_TOKEN=$(cat "${CONFIG_FILE}")
fi

# Set UUID
UUID=$(uuidgen)
echo_verbose "UUID: ${UUID}"

if [ -z "$ZAPPING_TOKEN" ];
then
	# Login
	echo "Logging in..."
	GETCODE_RESPONSE=$(http -f \
	  https://meteoro.zappingtv.com/activation/V20/androidtv/getcode \
	  uuid="${UUID}" \
	  acquisition="Android TV" \
	  User-Agent:"${USER_AGENT}")
	CODE=$(echo "${GETCODE_RESPONSE}" | jq -r .data.code)
	echo "Visit https://app.zappingtv.com/smart"
	echo "Code: ${CODE}"
	read -r -p "Pres [ENTER] to continue..."

	# Check code
	echo "Checking if the code is linked..."
	CHECKCODE_RESPONSE=$(http -f \
	  https://meteoro.zappingtv.com/activation/V20/androidtv/linked \
	  code="${CODE}" \
	  User-Agent:"${USER_AGENT}")
	CHECKCODE_STATUS=$(echo "${CHECKCODE_RESPONSE}" | jq -r .status)
	ZAPPING_TOKEN=$(echo "${CHECKCODE_RESPONSE}" | jq -r .data.data)
	echo "Status: ${CHECKCODE_STATUS} Token: ${ZAPPING_TOKEN}"

	# Save token
	echo "Saving token to ${CONFIG_FILE}..."
	echo "${ZAPPING_TOKEN}" > "${CONFIG_FILE}"
fi

# Play function
play_or_record() {
	# Get play token
	echo "Getting play token..."
	echo http -f \
		https://drhouse.zappingtv.com/login/V20/androidtv/ \
		token="${ZAPPING_TOKEN}" \
		uuid="${UUID}" \
		User-Agent:"${USER_AGENT}"
	DRHOUSE_RESPONSE=$(http -f \
		https://drhouse.zappingtv.com/login/V20/androidtv/ \
		token="${ZAPPING_TOKEN}" \
		uuid="${UUID}" \
		User-Agent:"${USER_AGENT}")
	PLAY_TOKEN=$(echo "${DRHOUSE_RESPONSE}" | jq -r .data.playToken)
	echo_verbose "Play token: ${PLAY_TOKEN}"

	# Play
	PLAY_URL=$(echo "${CHANNEL_LIST_RESPONSE}" | jq -r ".data[] | select(.name == \"${CHANNEL_NAME}\") | .url")
	PLAY_URL="${PLAY_URL}?token=${PLAY_TOKEN}${PLAY_EXTRA}"
	if [ -n "${START_TIME}" ]
	then
		PLAY_URL="${PLAY_URL}&startTime=${START_TIME}"
	fi
	if [ -n "${END_TIME}" ]
	then
		PLAY_URL="${PLAY_URL}&endTime=${END_TIME}"
	fi
	MPV_VERBOSE_PARAMS=""
	if [ -n "${VERBOSE}" ]
	then
		MPV_VERBOSE_PARAMS="-v"
	fi

	if [ -n "${RECORD}" ]
	then
		RECORDING_FILE="recording-$(date +%Y-%m-%d-%H%M%S).ts"
		echo "Recoding to file ${RECORDING_FILE}"
		echo_verbose "Record URL: ${PLAY_URL}"
		ffmpeg \
		  -user_agent "${USER_AGENT}" \
		  -live_start_index -99999 \
		  -i "${PLAY_URL}" \
		  -acodec copy \
		  -vcodec copy \
		  "${RECORDING_FILE}"
	else
		echo "Playing..."
		echo_verbose "Play URL: ${PLAY_URL}"
		mpv \
		  --user-agent="${USER_AGENT}" \
		  --demuxer-lavf-o=live_start_index=-99999 \
		  $MPV_VERBOSE_PARAMS \
		  --force-seekable=yes \
		  "${PLAY_URL}"
	fi
}

# Get channel list
echo_verbose "Zapping token: $ZAPPING_TOKEN"
echo "Getting channel list..."
CHANNEL_LIST_RESPONSE=$(http -f \
  https://alquinta.zappingtv.com/v20/androidtv/channelswithurl/ \
  quality=auto \
  hevc=1 \
  is3g=0 \
  token="${ZAPPING_TOKEN}" \
  User-Agent:"${USER_AGENT}")

# Auto play?
if [ -n "${AUTO_CHANNEL}" ]
then
	echo "Playing channel automatically: ${AUTO_CHANNEL}"
	CHANNEL_NAME="${AUTO_CHANNEL}"
	play_or_record
	exit
fi

# Choose channel
declare CHANNEL_NAMES
to_array CHANNEL_NAMES <<< "$(echo "${CHANNEL_LIST_RESPONSE}" | jq '(.data[])' | jq -r .name | sort)"
PS3='Select channel: '
select CHANNEL_NAME in "${CHANNEL_NAMES[@]}"
do
	# Live / VOD?
	echo "${CHANNEL_NAME}"
	START_TIME=""
	END_TIME=""
	read -r -p "Play [L]ive, [V]od or [T]ime? (default: Live) " TIME_PLAY_OPTION
	case $TIME_PLAY_OPTION in
		V | v)
			echo "Getting catchup data..."
			CHANNEL_IMAGE=$(echo "${CHANNEL_LIST_RESPONSE}" | jq -r ".data[] | select(.name == \"${CHANNEL_NAME}\") | .image")
			CATCHUP_RESPONSE=$(http POST \
			  "https://charly.zappingtv.com/v3.1/androidtv/${CHANNEL_IMAGE}/catchup/0/live")
			declare SECTION_NAMES
			to_array SECTION_NAMES <<< "$(echo "${CATCHUP_RESPONSE}" | jq -r .data[].title)"
			PS3='Select section: '
			select SECTION_NAME in "${SECTION_NAMES[@]}"
			do
				echo "Section selected: ${SECTION_NAME}"
				to_array CARDS_TITLES <<< "$(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].title")"
				to_array CARDS_START_TIMESTAMPS <<< "$(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].start_time")"
				to_array CARDS_END_TIMESTAMPS <<< "$(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].end_time")"
				to_array CARDS_TIMES <<< "$(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].start_time" | zargs timestamp_to_hh_mm)"
				to_array CARDS <<< "$(join_arrays CARDS_TIMES CARDS_TITLES)"
				PS3='Select card: '
				select CARD_NAME in "${CARDS[@]}"
				do
					echo "${CHANNEL_NAME}: ${CARD_NAME}"
					CARD_INDEX=$(( REPLY - 1 ))
					START_TIME=${CARDS_START_TIMESTAMPS[$CARD_INDEX]}
					END_TIME=${CARDS_END_TIMESTAMPS[$CARD_INDEX]}
					break
				done
				break
			done
			;;
		T | t)
			read -r -p "How much time back (example: 20 minute)? " TIME_BACK
			START_TIME=$(zdate -d"-${TIME_BACK}" +%s)
			echo "${CHANNEL_NAME}: -${TIME_BACK}"
			;;
		L | *)
			echo "${CHANNEL_NAME}: Live"
			;;
	esac

	play_or_record

	# Reset prompt
	PS3='Select channel: '
done
