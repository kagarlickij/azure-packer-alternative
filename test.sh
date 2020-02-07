#!/bin/bash

IMAGE_NAME='prod-vm1-image'

echo "IMAGE_NAME = $IMAGE_NAME"

IMAGES=$(az image list --resource-group 'packer-images-rg' | jq --raw-output '.[] | .name')
echo "IMAGES = $IMAGES"

if [[ $IMAGES == *"$IMAGE_NAME"* ]]; then {
    echo "It's there!"
} else {
    echo "Not there!"
}
fi
