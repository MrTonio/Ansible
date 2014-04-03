#!/bin/bash

aptitude update -y && upgrade -y
ssh-keygen && ssh-copy-id s-ansible

