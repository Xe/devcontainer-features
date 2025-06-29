#!/bin/bash

set -e

source dev-container-features-test-lib

check "yoke version" yoke version

reportResults