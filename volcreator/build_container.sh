#! /bin/bash

docker build --pull -t johnstrunk/volcreator . \
        && \
docker push johnstrunk/volcreator
