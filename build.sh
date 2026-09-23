#!/usr/bin/env bash

echo "========== env =========="
env | sort
echo "========================="

echo "IMAGE_NAME                 = ${IMAGE_NAME}"

docker buildx build \
    -t ${IMAGE_NAME} \
    .