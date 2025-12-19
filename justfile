# List available commands
default:
    just -l

alias d := dev

HOST := "austin@192.168.1.121"
PORT := "222"

# Run the dev server, and rebuild assets on exit.
[group("Development")]
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

# Install the projects dependencies
[group("Installation")]
install:
    #!/bin/bash
    just install-zola && install-tailwind

[private]
install-zola:
    #!/bin/bash
    cargo install --locked --git https://github.com/getzola/zola

# Install the latest tailwind binary in your system
[private]
install-tailwind:
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
[private]
run-tailwind:
    #!/bin/bash
    echo "Starting the Tailwind binary."
    ./tailwindcss -i ./styles/styles.css -o ./static/styles/styles.css --watch

# Script to build and minify the Tailwind binary
[private]
build-tailwind:
    #!/bin/bash
    echo -e "\nMinifying css"
    sh -c './tailwindcss -i ./styles/styles.css -o ./static/styles/styles.css --minify'

[private]
build-zola:
    #!/bin/bash
    zola build

# Build the site and static assets.
[group("Build")]
build:
    #!/bin/bash
    just build-tailwind && just build-zola

[private]
docker-build-local:
    docker buildx build --platform linux/amd64 --tag the_peach --file Dockerfile .

# Build an image for local testing and deploy with docker compose
[group('Deploy')]
deploy-local:
    just build && just docker-build-local && docker compose up -d

# Builds the x86 docker image and tags it with the registry location
[private]
build-kube:
    #!/bin/bash
    : ${TAG=$(yq '.' version)}
    docker build --tag registry:5001/the_peach:${TAG} --file Dockerfile .

# Checks if the version in `./version` is already the version specified in the 
# kube-deployment file. If so, requests a new version, updates the version file
# and updates the TAG variable.
[private, no-exit-message]
check-current-version:
    #!/bin/bash
    # Get TAG from the version file if it doesn't already exist
    : ${TAG=$(yq '.' version)}
    # Get the IMAGE specified in the kube-deployment file. (Should be what's 
    # currently deployed in the cluster.)
    IMAGE=$(
        yq -r 'select(.metadata.name=="the-peach-software-company" and 
            .kind=="Deployment").spec.template.spec.containers[].image' \
            kube-deployment.yaml \
    )
    # Get the VERSION specific in the image.
    CURRENT_VERSION="${IMAGE##*:}"

    # Compare the what's in version to what's already deployed to the cluster.
    if [[ "$CURRENT_VERSION" == "$TAG" ]]; then
        echo ""
        echo "Current tag already deployed: $TAG"
        read -p "Enter the new version: " NEW_VERSION

        # Check that the version inputted matches the semver style.
        if [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # Replace what's in the version file with the new version.
            echo "$NEW_VERSION" > ./version
        else
            echo "Invalid version."
            exit 1
        fi
    fi

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
    # Upload the latest build of the image to the internal registry, then
    # update the tag in the kube config file, send it to node0, then apply it.
    # User must be in the deploygrp on node0 to be able to create files there!
    just check-current-version \
        && just upload-kube \
        && just deploy-kube

# Updates the kube-deployment file, then applies it.
[group('Deploy')]
deploy-kube:
    #!/bin/bash
    : ${TAG=$(yq '.' version)}

    echo "Deploying $TAG"

    # Update the tag in the kube config file, send it to node0, then apply it.
    # User must be in the deploygrp on node0 to be able to create files there and
    # tagged image must already be in the private registry!
    yq eval -i 'select(.metadata.name=="the-peach-software-company" and .kind=="Deployment").spec.template.spec.containers[].image = "10.108.202.38:5000/the_peach:'$TAG'"' kube-deployment.yaml \
        && scp -P "{{PORT}}" ./kube-deployment.yaml {{HOST}}:/opt/deploys/the_peach_software_company.yaml \
        && ssh -p "{{PORT}}" {{HOST}} "kubectl apply -f /opt/deploys/the_peach_software_company.yaml"
