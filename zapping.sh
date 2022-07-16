#!/bin/bash

# Constants
CONFIG_FILE="${HOME}/.config/zapping"
USER_AGENT="Zapping/bash-1.0"

# Check dependencies
if ! command -v mpv &> /dev/null
then
	echo "This script requires mpv"
	exit
fi
if ! command -v jq &> /dev/null
then
	echo "This script requires jq"
	exit
fi
if ! command -v http &> /dev/null
then
	echo "This script requires HTTPie"
	exit
fi
if ! command -v uuidgen &> /dev/null
then
	echo "This script requires uuidgen"
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

# Load token from file?
if [ -f "${CONFIG_FILE}" ]
then
	ZAPPING_TOKEN=$(cat "${CONFIG_FILE}")
fi

if [ -z "$ZAPPING_TOKEN" ];
then
	# Login
	echo "Logging in..."
	UUID=$(uuidgen)
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

# Get play token
echo "Getting play token..."
UUID=$(uuidgen)
DRHOUSE_RESPONSE=$(http -f \
  https://drhouse.zappingtv.com/login/V20/androidtv/ \
  token="${ZAPPING_TOKEN}" \
  uuid="${UUID}" \
  User-Agent:"${USER_AGENT}")
PLAY_TOKEN=$(echo "${DRHOUSE_RESPONSE}" | jq -r .data.playToken)

# Get channel list
echo "Getting channel list..."
CHANNEL_LIST_RESPONSE=$(http -f \
  https://alquinta.zappingtv.com/v20/androidtv/channelswithurl/ \
  quality=auto \
  hevc=1 \
  is3g=0 \
  token="${ZAPPING_TOKEN}" \
  User-Agent:"${USER_AGENT}")

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
				to_array CARDS_TITLES <<< $(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].title")
				to_array CARDS_START_TIMESTAMPS <<< $(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].start_time")
				to_array CARDS_END_TIMESTAMPS <<< $(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].end_time")
				to_array CARDS_TIMES <<< $(echo "${CATCHUP_RESPONSE}" | jq -r ".data[] | select(.title == \"${SECTION_NAME}\") | .cards[].start_time" | xargs -I _ date -d @_  +'%H:%M')
				to_array CARDS <<< "$(join_arrays CARDS_TIMES CARDS_TITLES)"
				PS3='Select card: '
				select CARD_NAME in "${CARDS[@]}"
				do
					echo "Playing ${CARD_NAME}..."
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
			START_TIME=$(date -d"-${TIME_BACK}" +%s)
			echo "Playing from ${START_TIME}..."
			;;
		L | *)
			echo "Playing live..."
			;;
	esac

	# Send heartbeat
	echo "Sending heartbeat..."
	http -f https://drhouse.zappingtv.com/hb/v1/androidtv/ \
	  playtoken="${PLAY_TOKEN}" \
	  User-Agent:"${USER_AGENT}" > /dev/null

	# Play
	echo "Playing channel: ${CHANNEL_NAME}..."
	PLAY_URL=$(echo "${CHANNEL_LIST_RESPONSE}" | jq -r ".data[] | select(.name == \"${CHANNEL_NAME}\") | .url")
	PLAY_URL="${PLAY_URL}?token=${PLAY_TOKEN}${PLAY_EXTRA}"
	if [ -n "${START_TIME}"  ]
	then
		PLAY_URL="${PLAY_URL}&startTime=${START_TIME}"
	fi
	if [ -n "${END_TIME}"  ]
	then
		PLAY_URL="${PLAY_URL}&endTime=${END_TIME}"
	fi
	mpv \
	  --user-agent="${USER_AGENT}" \
	  --demuxer-lavf-o=live_start_index=-99999 \
	  --force-seekable=yes \
	  "${PLAY_URL}"

	# Reset prompt
	PS3='Select channel: '
done
