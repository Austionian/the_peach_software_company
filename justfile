# List available commands
default:
    just -l

HOST := "austin@192.168.1.121"
PORT := "222"

dev:
    #!/bin/bash
    minify() {
        just build-tailwind
    }

    # Add a trap to run the minify function before exiting
    trap "minify; kill 0" SIGINT

    open 'http://127.0.0.1:2222'

    zola serve --port 2222 & just run-tailwind
    TAILWIND_PID=$!

    wait $TAILWIND_PID

# Install the latest tailwind binary in your system
download-tailwind:
    #!/bin/bash
    if [ "$(uname)" == "Darwin" ]; then 
        curl -sLO https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-macos-arm64 
        chmod +x tailwindcss-macos-arm64 
        mv tailwindcss-macos-arm64 tailwindcss 
    elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then 
        if [ "$(uname -m)" == "x86_64" ]; then 
            curl -sLO https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64 
            chmod +x tailwindcss-linux-x64 
            mv tailwindcss-linux-x64 tailwindcss 
        else 
            curl -sLO https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-arm64 
            chmod +x tailwindcss-linux-arm64
            mv tailwindcss-linux-arm64 tailwindcss
        fi
    fi

# Script to run the Tailwind binary in watch mode
run-tailwind:
    #!/bin/bash
    echo "Starting the Tailwind binary."
    ./tailwindcss -i ./styles/styles.css -o ./static/styles/styles.css --watch

# Script to build and minify the Tailwind binary
build-tailwind:
    #!/bin/bash
    echo -e "\nMinifying css"
    sh -c './tailwindcss -i ./styles/styles.css -o ./static/styles/styles.css --minify'

build-zola:
    #!/bin/bash
    zola build

build:
    #!/bin/bash
    just build-tailwind && just build-zola

docker-build-local:
    docker buildx build --platform linux/amd64 --tag localhost:5000/the_peach --file Dockerfile .

deploy-local:
    just build && just docker-build-local && docker compose up -d

# Builds the x86 docker image and tags it with the registry location
[group('Build')]
build-kube:
    docker build --tag registry:5001/the_peach:${TAG:-latest} --file Dockerfile .

# Updates the cluster's registry with the latest image
[private]
upload-kube:
    #!/bin/bash
    : ${TAG=$(yq '.' version)}
    set -euo pipefail

    # Build the image
    just build-kube

    # Launch the tunnel in background
    # Map port 5001 to registry-service:5000
    ssh -L 5001:10.108.202.38:5000 {{HOST}} -p {{PORT}} -N &
    TUNNEL_PID=$!          # capture the background PID

    # Close the tunnel when the process completes or fails
    trap 'echo "Stopping tunnel…"; kill "$TUNNEL_PID" 2>/dev/null || true' EXIT INT TERM

    # Wait for the tunnel to be ready
    echo -n "Waiting for local port 5001 to be ready"
    while ! nc -z localhost 5001; do
        sleep .25
        printf "."
    done
    echo "Tunnel started (PID $TUNNEL_PID) – local port 5001 → 10.108.202.38:5000"

    # Push the image to the registry
    # Requires that `/etc/hosts` has registry 127.0.0.1
    # The hostname needs to be registry becuase that's how the ingress in the 
    # kube cluster knows to route it to the service 
    # i.e. in the cluster itself `curl -H "Host: registry"` is required
    # Docker connects to localhost:5001 and sends Host: registry:5001.
    echo "Pushing image to registry"
    docker push registry:5001/the_peach:$TAG

# Updates the cluster's image and deployment file, then applies it.
[group('Deploy')]
deploy:
    #!/bin/bash
    export TAG=$(yq '.' version)

    # Upload the latest build of the image to the internal registry, then
    # update the tag in the kube config file, send it to node0, then apply it.
    # User must be in the deploygrp on node0 to be able to create files there!
    just upload-kube \
        && just deploy-kube

# Updates the kube-deployment file, then applies it.
[group('Deploy')]
deploy-kube:
    #!/bin/bash
    : ${TAG=$(yq '.' version)}

    # Update the tag in the kube config file, send it to node0, then apply it.
    # User must be in the deploygrp on node0 to be able to create files there and
    # tagged image must already be in the private registry!
    yq eval -i 'select(.metadata.name=="the-peach-software-company" and .kind=="Deployment").spec.template.spec.containers[].image = "10.108.202.38:5000/the_peach:'$TAG'"' kube-deployment.yaml \
        && scp -P "{{PORT}}" ./kube-deployment.yaml {{HOST}}:/opt/deploys/the_peach_software_company.yaml \
        && ssh -p "{{PORT}}" {{HOST}} "kubectl apply -f /opt/deploys/the_peach_software_company.yaml"
