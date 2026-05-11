#!/bin/bash

cd /home/danila/devops/app || exit

echo "Deploy started"

git pull origin main

sudo systemctl restart app

echo "Deploy finished"
