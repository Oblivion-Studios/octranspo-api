#!/bin/sh
# Download latest GTFS zip file from OC Transpo (https://www.octranspo.com/files/google_transit.zip)
wget https://www.octranspo.com/files/google_transit.zip
echo "\nDownloaded latest GTFS zip file from OC Transpo\n"

# Finally, compile the new transit data
thor manage:compile octranspo google_transit.zip

# Remove the downloaded zip file
rm -rf google_transit.zip
