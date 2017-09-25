#! /bin/bash

docker build --pull -t johnstrunk/volrecycler . \
        && \
docker push johnstrunk/volrecycler
