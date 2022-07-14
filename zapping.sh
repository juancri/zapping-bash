#!/bin/bash

# Constants
CONFIG_FILE="${HOME}/.config/zapping"
CHANNELS_FILE="${HOME}/.config/zapping.channels"
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

# Pollyfill
# MacOS does not support readarray
readarray() {
	local __resultvar=$1
	declare -a __local_array
	(( i = 0 )) || true
	while IFS=$'\n' read -r line_data; do
		eval "${__resultvar}[${i}]=\"${line_data}\""
		((++i))
	done < "${2}"
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
	read -p "Pres [ENTER] to continue..."

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
  hevc=0 \
  is3g=0 \
  token="${ZAPPING_TOKEN}" \
  User-Agent:"${USER_AGENT}")

# Choose channel
PS3='Select channel: '
echo "${CHANNEL_LIST_RESPONSE}" | jq '(.data[])' | jq -r .name | sort > "${CHANNELS_FILE}"
readarray CHANNEL_NAMES "${CHANNELS_FILE}"
echo "first channel: ${CHANNEL_NAMES[0]}"
select CHANNEL_NAME in "${CHANNEL_NAMES[@]}"
do
	# Send heartbeat
	echo "Sending heartbeat..."
	http -f https://drhouse.zappingtv.com/hb/v1/androidtv/ \
	  playtoken="${PLAY_TOKEN}" \
	  User-Agent:"${USER_AGENT}" > /dev/null

	# Play
	echo "Playing channel: ${CHANNEL_NAME}..."
	STREAM_URL=$(echo "${CHANNEL_LIST_RESPONSE}" | jq -r ".data[] | select(.name == \"${CHANNEL_NAME}\") | .url")
	PLAY_URL="${STREAM_URL}?token=${PLAY_TOKEN}&startTime=1657815766"
	ffmpeg \
	  -user_agent "${USER_AGENT}" \
	  -i "${PLAY_URL}" \
	  -c:a copy \
	  -c:v copy \
	  -f mpegts - | mpv -
done
