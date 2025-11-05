#!/bin/bash

# Nutzereingabe für die AWS-Zugangsdaten
read -p "Gib die aws_access_key_id ein (ohne aws_access...=): " aaki
echo
read -p "Gib den vollständigen aws_secret_access_key ein (ohne aws_secret...=): " asak
echo
read -p "Gib den vollständigen aws_session_token ein (ohne aws_session...=): " ast
echo

# AWS-Zugangsdaten in die credentials-Datei schreiben
echo "[default]
aws_access_key_id = $aaki
aws_secret_access_key = $asak
aws_session_token = $ast" > "/home/$USER/.aws/credentials"

# Bestätigung für den Nutzer
echo "AWS-Zugangsdaten wurden erfolgreich in ~/.aws/credentials gespeichert."

