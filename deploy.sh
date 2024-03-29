#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
docker run --rm --name hugo-deploy -v $(pwd):/src klakegg/hugo

# Go To Public folder
cd public
# Add changes to git.
git add .

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg" --no-gpg-sign

# Push source and build repos.
git push -u origin master

# Come Back up to the Project Root
cd ..

