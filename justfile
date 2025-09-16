# List available commands
default:
    just -l

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

# Builds the docker image
docker-build:
    docker buildx build --platform linux/arm64/v8 --tag oxidized --file Dockerfile .

docker-deploy:
    DOCKER_HOST="ssh://austin@cluster.local" docker compose up -d

# Builds the new images, saves it to the pi, remotely starts it up with docker compose
deploy:
     just build && just docker-build && docker save oxidized | bzip2 | ssh austin@cluster.local docker load && just docker-deploy
