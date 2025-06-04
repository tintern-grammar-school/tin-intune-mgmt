#! /bin/bash

# ------------------------------------------------------------------ #

# Intune Pkg Pre-Install script for Arctic Wolf Agent on macOS
# By John Cleary, Tintern Grammar School

# This Pre-Install script will populate the customer.json file that 
# the Arctic Wolf installer expects. Simply add this script to your 
# Intune package, and it will run before install, meaning the 
# installer can find the customer.json file it checks for.

# Replace YOUR_CUSTOMER_UUUID_HERE and YOUR_CUSTOMER_DNS_HERE from 
# your customer.json file that can be downloaded from your AW Portal.

# Last Updated by jcleary@tintern.vic.edu.au on 2025-05-22 at 13h17m

# ------------------------------------------------------------------ #

# Create customer.json file where expeted by installer
sudo mkdir -p /Library/ArcticWolfNetworks/Agent/etc
echo '{"customerUuid":"YOUR_CUSTOMER_UUUID_HERE","registerDns":"YOUR_CUSTOMER_DNS_HERE"}' | sudo tee /Library/ArcticWolfNetworks/Agent/etc/customer.json > /dev/null

# Set Ownership
sudo chown -R root:wheel /Library/ArcticWolfNetworks/Agent

# Set Permissions
sudo chmod 755 /Library/ArcticWolfNetworks/Agent
sudo chmod 755 /Library/ArcticWolfNetworks/Agent/etc
sudo chmod 644 /Library/ArcticWolfNetworks/Agent/etc/customer.json