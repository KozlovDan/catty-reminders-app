#!/bin/bash

echo "Deploy started"

cd /home/danila/devops/app || exit

git pull --rebase origin lab1

echo "DEPLOY_REF=$(git rev-parse HEAD)" > .env

sudo systemctl restart app

echo "Deploy finished"
