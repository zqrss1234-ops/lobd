#!/bin/bash
make package > /tmp/build.log 2>&1
BUILD_EXIT=$?
echo "MAKE_EXIT_CODE=$BUILD_EXIT" >> /tmp/build.log
# Print the log for the workflow
cat /tmp/build.log
exit $BUILD_EXIT
