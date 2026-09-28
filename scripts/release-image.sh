#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="${1:?Usage: $0 <version>}"

ACR_REGISTRY="crpi-066qvm3u7gug6i9w.cn-hangzhou.personal.cr.aliyuncs.com"
ACR_IMAGE="${ACR_REGISTRY}/shiran-kubeforge/kubeforge"

LOCAL_IMAGE="kubeforge:${VERSION}"
REMOTE_IMAGE="${ACR_IMAGE}:${VERSION}"

CONTAINER_NAME="kubeforge-verify-${VERSION//[^a-zA-Z0-9_.-]/-}"

EXPECTED_TEXT="${EXPECTED_TEXT:-KubeForge}"


cleanup() {
    echo "[CLEANUP] remove test container"
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}


on_error() {
    EXIT_CODE=$?
    echo "[FAILED] line=${BASH_LINENO[0]} exit=${EXIT_CODE}" >&2
    exit "${EXIT_CODE}"
}


trap cleanup EXIT
trap on_error ERR


echo "[1/6] Build image"

docker build \
    -t "${LOCAL_IMAGE}" .


echo "[2/6] Validate nginx configuration"

docker run --rm \
    "${LOCAL_IMAGE}" \
    nginx -t


echo "[3/6] Start candidate container"


docker run -d \
    --name "${CONTAINER_NAME}" \
    -p 18080:80 \
    "${LOCAL_IMAGE}"


echo "[4/6] Wait HTTP ready"


for attempt in $(seq 1 20)
do

    if curl -fsS http://127.0.0.1:18080 >/dev/null
    then
        break
    fi


    if [ "${attempt}" -eq 20 ]
    then
        echo "HTTP endpoint failed"
        exit 1
    fi


    sleep 1

done



echo "[5/6] Check page content"


response=$(curl -fsS http://127.0.0.1:18080)


echo "${response}" | grep -Fq "${EXPECTED_TEXT}"



echo "[6/6] Push image"


docker tag \
    "${LOCAL_IMAGE}" \
    "${REMOTE_IMAGE}"


docker push \
    "${REMOTE_IMAGE}"


echo "[SUCCESS] pushed ${REMOTE_IMAGE}"

