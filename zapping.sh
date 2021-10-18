#!/bin/bash

# Constants
CONFIG_FILE="${HOME}/.config/zapping"

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

# Load token from file?
if [ -f "${CONFIG_FILE}" ]
then
	ZAPPING_TOKEN=$(cat "${CONFIG_FILE}")
fi

if [ -z "$ZAPPING_TOKEN" ];
then
	# Login
	read -p "Email: " ZAPPING_EMAIL
	read -p "Password: " ZAPPING_PASS
	echo "Logging in..."
	LOGIN_RESPONSE=$(http -f \
	  https://api.zappingtv.com/v16/android/users/login/email \
	  email="${ZAPPING_EMAIL}" \
	  password="${ZAPPING_PASS}")
	ZAPPING_USER_ID=$(echo "${LOGIN_RESPONSE}" | jq -r .data.id)

	# Get token
	echo "Getting token..."
	TOKEN_RESPONSE=$(http -f \
	  https://api.zappingtv.com/v16/android/users/getWebToken \
	  email="${ZAPPING_EMAIL}" \
	  password="${ZAPPING_PASS}" \
	  userID="${ZAPPING_USER_ID}")
	ZAPPING_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r .data)

	# Save token
	echo "Saving token to ${CONFIG_FILE}..."
	echo "${ZAPPING_TOKEN}" > "${CONFIG_FILE}"
fi

# Get channel list
echo "Getting channel list..."
CHANNEL_LIST_RESPONSE=$(http -f \
  https://alquinta.zappingtv.com/v20/android/channelsforuser/ \
  quality=auto \
  hevc=1 \
  is3g=0 \
  token="${ZAPPING_TOKEN}")

# Choose channel
echo "${CHANNEL_LIST_RESPONSE}" > /tmp/channels.json
PS3='Select channel: '
CHANNEL_NAMES_JQ=$(echo "${CHANNEL_LIST_RESPONSE}" | jq '(.data[])' | jq -r .name | sort)
readarray -t CHANNEL_NAMES <<< "${CHANNEL_NAMES_JQ}"
select CHANNEL_NAME in "${CHANNEL_NAMES[@]}"
do
	# Play
	echo "Playing channel: ${CHANNEL_NAME}..."
	CHANNEL_ID=$(echo "${CHANNEL_LIST_RESPONSE}" | jq -r ".data[] | select(.name == \"${CHANNEL_NAME}\") | .id")
	PLAY_CHANNEL_RESPONSE=$(http -f https://alquinta.zappingtv.com/v10/atv/playcanal \
	  media="${CHANNEL_ID}" \
	  token="${ZAPPING_TOKEN}" \
	  sub=0 \
	  qlty=auto \
	  is3g=0 \
	  hevc=1)
	PLAY_URL=$(echo "${PLAY_CHANNEL_RESPONSE}" | jq -r .data.href)
	mpv "${PLAY_URL}" > /dev/null 2>&1
done
