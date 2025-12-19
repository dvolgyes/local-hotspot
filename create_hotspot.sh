#!/bin/bash

HOTSPOT_NAME="home-hotspot"
# TODO check if the ${HOTSPOT_NAME} exits and if it doesn't:
nmcli con add type wifi ifname wlp4s0 con-name "${HOTSPOT_NAME}" autoconnect yes ssid "${HOTSPOT_NAME}"
nmcli con modify "${HOTSPOT_NAME}" 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
nmcli con modify "${HOTSPOT_NAME}" wifi-sec.key-mgmt wpa-psk
nmcli con modify "${HOTSPOT_NAME}" wifi-sec.psk "dejonekem"

# if exists, enable the connection
nmcli con up "${HOTSPOT_NAME}"
